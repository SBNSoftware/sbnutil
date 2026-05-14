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

def retire_file(filename: pathlib.Path, dry_run=False, delete=True) -> int:
    """Remove a file's location, retire it from SAM, and delete the file"""

    recuperated_size = 0
    try:
        if delete:
            recuperated_size = file_size(filename)
    except Exception as e:
        logger.error(f"Could not process {filename.name} due to exception: {e}")
        return 0

    if dry_run:
        logger.debug(f"SAMWeb_Client.removeFileLocation({filename.name}, {filename.parent})")
        logger.debug(f"SAMWeb_Client.retireFile({filename.name})")
        if delete:
            logger.debug(f"Unlink {filename.name}")
    else:
        try:
            SAMWeb_Client.removeFileLocation(filename.name, filename.parent)
        except samweb_client.exceptions.FileLocationNotFound as e:
            logger.error(f"Could not remove file {filename.name} from location as it was not located there")

        SAMWeb_Client.retireFile(filename.name)
        if delete:
            filename.unlink()

    return recuperated_size

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

    ndeleted = 0
    nskip = 0
    file_size_reclaimed = 0
    while True:
        try:
            item = _queue.get(timeout=10)
        except queue.Empty:
            break

        logger.debug(f'{pid=} Got {item}')
        now = datetime.now()

        try:
            dry_run=args.dry_run
            delete=args.delete
            this_size = retire_file(item, dry_run, delete)
            logger.warning(f'{pid=} Retired {item}, saving {this_size} bytes.')
            file_size_reclaimed += this_size
            ndeleted += 1
        except samweb_client.exceptions.FileNotFound as e:
            logger.warning(f'{pid=} Skipping {item}, file not found ({e}).')
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

    _result.put((ndeleted, nskip, file_size_reclaimed))

    logger.info(f"Reclaimed {file_size_reclaimed} bytes.")

def main(args: dict) -> None:

    if args.dry_run:
        logger.info("I will not actually delete files, I am in dry_run mode.")

    if not args.delete:
        logger.info("I will only remove file locations and retire them from SAM.")
    
    filename = pathlib.Path(args.filename)
    if not args.recursive:
        retire_file(filename, dry_run=args.dry_run, delete=args.delete)
        sys.exit(0)

    # recursive case, use mutlithreading
    if not filename.is_dir():
        raise RuntimeError(f'Recursive mode requested but {filename} is not a directory.')

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
    
        logger.debug(f'queuing {f}')

        file_queue.put(f)
        nfiles_reset += 1
        nfiles += 1

        # spawn a new process for files until we reach the max number
        # of processes. New process is only spawned once there are at least
        # NFILES_MIN files (fewer processes for small batches of O(10) files)
        if nprocesses < NPROCESS_MAX and (nfiles_reset > NFILES_MIN or nprocesses == 0):
            nprocesses += 1
            logger.info(f'spawning process {nprocesses=}')
            t = multiprocessing.Process(target=_callback, args=(file_queue, result_queue, args.dry_run, args.delete))
            processes.append(t)
            t.start()
            nfiles_reset = 0


    ndeleted = 0
    nskip = 0
    full_size = 0
    for p in processes:
        p.join()
    tend = datetime.now()

    while True:
        try:
            nd, ns, fs = result_queue.get(block=False)
            ndeleted += nd
            nskip += ns
            full_size += fs
        except queue.Empty:
            break

    logger.info('Done')
    dt = (tend - tstart).total_seconds()
    logger.info(f'Processed {nfiles} files (deleted={ndeleted}, skip={nskip}) in {dt:.2f} seconds ({(nskip + ndeleted) / dt:.2f} files per second)')
    logger.warning(f"Reclaimed {full_size/1024**4} TB from {ndeleted} files")


if __name__ == '__main__':
    formatter = logging.Formatter('[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s')

    file_handler = logging.FileHandler(filename='sam_delete.log')
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)

    stdout_handler = logging.StreamHandler(stream=sys.stdout)
    stdout_handler.setLevel(logging.WARNING)
    stdout_handler.setFormatter(formatter)

    logger.setLevel(logging.DEBUG)
    logger.addHandler(file_handler)
    logger.addHandler(stdout_handler)

    parser = argparse.ArgumentParser(
        prog='sam_delete',
        description='Retires and deletes files from SAM.')
    parser.add_argument('filename')
    parser.add_argument('-R', '--recursive', action='store_true', help='If filename is a directory, glob for files within.')
    parser.add_argument('-D', '--dry_run', action='store_true', help='Do not actually retire files')
    parser.add_argument('-d', '--delete', action='store_true', help='Delete file from disk after it has been retired from SAM')
    args = parser.parse_args()

    main(args)
