#!/usr/bin/env python3

import sys
import time
import argparse
import os
import json
import pathlib
import multiprocessing
import queue
import tempfile
import random
import logging
from datetime import datetime

import samweb_client
import samweb_client.utility


SAMWeb_Client = samweb_client.SAMWebClient()
NPROCESS_MAX = 10 # max processes
SAM_RPS_MAX = 5.0 # max requests per second per process
NFILES_MIN = 10 # only spawn a new process after seeing at least this many files
SMEAR_MAX = 1.1 # random factor to smear out the time between requests. Set to 1 for no smearing

logger = logging.getLogger(__name__)


class MetadataNotFoundException(Exception):
    pass


try:
    EXPERIMENT = os.environ["EXPERIMENT"]
except KeyError:
    raise RuntimeError("Must set EXPERIMENT environment variable.")


def require_file(filename:pathlib.Path) -> None:
    """Raise if the file is missing or the path is a directory."""
    if filename.is_dir():
        raise IsADirectoryError(f'Attempt to call file size with a directory {filename}.')

    if not filename.is_file():
        raise FileNotFoundError(f'Attempt to call file size with an invalid file {filename}. Does it exist?')


def file_size(filename: pathlib.Path) -> int:
    """File size in bytes."""
    require_file(filename)
    return filename.stat().st_size


def metadata_file(filename: pathlib.Path) -> pathlib.Path:
    """Expected metadata filename, appends .json."""
    require_file(filename)
    stem = filename.suffix
    return filename.with_suffix('.'.join([stem, 'json']))


def update_metadata(metadata: dict, filename: pathlib.Path, do_file_size=True, do_checksum=True) -> dict:
    """Return metadata dict with common additions: file size & checksums."""
    result = metadata.copy()

    if do_file_size:
        result['file_size'] = file_size(filename)

    if do_checksum:
        result['checksum'] = samweb_client.utility.fileChecksum(\
                str(filename), checksum_types=['enstore', 'adler32', 'md5'])

    # add extra modifications here
    # ...
    result['file_name'] = filename
    result['file_format'] = 'root'
    result['data_tier'] = 'cafana'
    result['application'] = { 'family': 'art', 'name': 'cafmaker', 'version': 'v10_06_02' }
    result['fcl.name'] = "cafmakerjob_sbnd_sce_systtools_and_fluxwgt.fcl"
    result['production.name'] = 'MCP2025B_NueCC'
    result['production.type'] = 'aurora'
    result['file_name'] = filename.name
    result["sbnd_project.stage"] = "caf"
    '''
    result['file_format'] = 'artroot'
    result['data_tier'] = 'reconstructed'
    result['application'] = { 'family': 'art', 'name': 'reco2', 'version': 'v10_06_02' }
    # result['fcl.name'] = "prodgenie_corsika_proton_rockbox_ccnue_sbnd.fcl/standard_g4_rockbox_sbnd.fcl/standard_detsim_sbnd.fcl/standard_reco1_sbnd.fcl"
    result['fcl.name'] = "prodgenie_corsika_proton_rockbox_ccnue_sbnd.fcl/standard_g4_rockbox_sbnd.fcl/standard_detsim_sbnd.fcl/standard_reco1_sbnd.fcl/standard_reco2_sbnd.fcl"
    result['production.name'] = 'MCP2025B_NueCC'
    result['production.type'] = 'aurora'
    result['file_name'] = filename.name
    # del result['parents']
    '''

    return result


def declare_file(filename: pathlib.Path, validate=False, delete=False):
    """Declare a file to SAM & add its file location."""
    meta_filename = metadata_file(filename)
    if not meta_filename.is_file():
        raise MetadataNotFoundException(f'Tried to declare {filename} but {meta_filename} was not found!.')

    with open(meta_filename, 'r') as f:
        d = json.load(f)
        d = update_metadata(d, filename)

    if validate:
        SAMWeb_Client.validateFileMetadata(d)

    SAMWeb_Client.declareFile(d)
    SAMWeb_Client.addFileLocation(filename.name, filename.parent)

    if delete:
        meta_filename.unlink()


def _callback(_queue: multiprocessing.Queue, _result: multiprocessing.Queue, validate=False, delete=False):
    """
    Callback function for each process. Wraps getting files from a common queue
    shared between processes with file declaration.
    """
    # random sleeps ensures the process declarations are somewhat spread out
    # first random sleep spreads out the processes 
    time.sleep(random.uniform(0, 5))
    pid = multiprocessing.current_process().name
    logger.info(f'{pid=} start')

    ndeclared = 0
    nskip = 0
    while True:
        try:
            item = _queue.get(timeout=10)
        except queue.Empty:
            break

        logger.debug(f'{pid=} Got {item}')
        now = datetime.now()

        try:
            declare_file(item, validate, delete)
            logger.info(f'{pid=} Declared {item}.')
            ndeclared += 1
        except samweb_client.exceptions.FileAlreadyExists:
            logger.warning(f'{pid=} Skipping {item}, already declared.')
            nskip += 1
        except MetadataNotFoundException:
            # logger.warning(f'{pid=} Skipping {item}, metadata not found.')
            nskip += 1
        except samweb_client.exceptions.InvalidMetadata as e:
            logger.warning(f'{pid=} Skipping {item}, metadata invalid ({e}).')
            nskip += 1

        last_request = datetime.now()
        dt = (last_request - now).total_seconds()

        wait = (1.0 / SAM_RPS_MAX) - dt

        # rate limit
        if wait > 0:
            # once again, add a little variance
            wait *= random.uniform(1, SMEAR_MAX)
            logger.debug(f'{pid=} Sleeping {wait:0.4f}s')
            time.sleep(wait)

    _result.put((ndeclared, nskip))


def main(args: dict) -> None:
    filename = pathlib.Path(args.filename)
    if not args.recursive:
        declare_file(filename, validate=args.validate, delete=args.delete_json)
        sys.exit(0)

    # recursive case, use mutlithreading
    if not filename.is_dir():
        raise RuntimeError(f'Recusive mode requested but {filename} is not a directory.')

    tstart = datetime.now()
    files = filename.rglob('*[!json]')
    nprocesses = 0

    # file counter only used to limit spawning new processes. Wait for NFILES_MIN files before spawning
    nfiles_reset = 0
    nfiles = 0
    file_queue = multiprocessing.Queue()
    result_queue = multiprocessing.Queue()
    processes = []
    for f in files:
        if not f.is_file():
            continue
        meta_filename = metadata_file(f)
        if not meta_filename.is_file():
            continue
    

        logger.debug(f'adding {f}')

        file_queue.put(f)
        nfiles_reset += 1
        nfiles += 1

        # spawn a new process for files until we reach the max number
        # of processes. New process is only spawned once there are at least
        # NFILES_MIN files (fewer processes for small batches of O(10) files)
        if nprocesses < NPROCESS_MAX and (nfiles_reset > NFILES_MIN or nprocesses == 0):
            nprocesses += 1
            logger.info(f'spawning process {nprocesses=}')
            t = multiprocessing.Process(target=_callback, args=(file_queue, result_queue, args.validate, args.delete_json))
            processes.append(t)
            t.start()
            nfiles_reset = 0


    ndeclared = 0
    nskip = 0
    for p in processes:
        p.join()
    tend = datetime.now()

    while True:
        try:
            nd, ns = result_queue.get(block=False)
            ndeclared += nd
            nskip += ns
        except queue.Empty:
            break

    logger.info('Done')
    dt = (tend - tstart).total_seconds()
    logger.info(f'Processed {nfiles} files (declared={ndeclared}, skip={nskip}) in {dt:.2f} seconds ({(nskip + ndeclared) / dt:.2f} files per second)')


if __name__ == '__main__':
    formatter = logging.Formatter('[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s')

    file_handler = logging.FileHandler(filename='sam_declare.log')
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)

    stdout_handler = logging.StreamHandler(stream=sys.stdout)
    stdout_handler.setLevel(logging.INFO)
    stdout_handler.setFormatter(formatter)

    logger.setLevel(logging.DEBUG)
    logger.addHandler(file_handler)
    logger.addHandler(stdout_handler)

    parser = argparse.ArgumentParser(
        prog='sam_declare',
        description='Declare files to SAM, adding common metadata fields and file locations.')
    parser.add_argument('filename')
    parser.add_argument('-R', '--recursive', action='store_true', help='If filename is a directory, glob for files within.')
    parser.add_argument('-V', '--validate', action='store_true', help='Validate metadata before declaring')
    parser.add_argument('-d', '--delete-json', action='store_true', help='Remove json file after declaration')
    args = parser.parse_args()

    main(args)
