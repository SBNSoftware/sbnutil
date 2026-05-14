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
from collections import defaultdict

import samweb_client
import samweb_client.utility


SAMWeb_Client = samweb_client.SAMWebClient()
NPROCESS_MAX = 10 # max processes
SAM_RPS_MAX = 4.0 # max requests per second per process
NFILES_MIN = 10 # only spawn a new process after seeing at least this many files
SMEAR_MAX = 1.25 # random factor to smear out the time between requests. Set to 1 for no smearing

logger = logging.getLogger(__name__)

try:
    EXPERIMENT = os.environ["EXPERIMENT"]
except KeyError:
    raise RuntimeError("Must set EXPERIMENT environment variable.")

def _buildAncestors(_queue: multiprocessing.Queue(), _result: multiprocessing.Queue()):
    """
    Populates a dictionary with the parents for each file seen
    """

    # random sleeps ensures the process declarations are somewhat spread out
    # first random sleep spreads out the processes 
    time.sleep(random.uniform(0, 5))
    pid = multiprocessing.current_process().name
    logger.info(f'{pid=} start')

    res_dict = {}
    while True:
        try:
            item = _queue.get(timeout=10)
        except queue.Empty:
            break

        logger.warning(f'{pid=} Got {item}')
        now = datetime.now()

        try:
            check_parent = SAMWeb_Client.getMetadata(item)['parents'][0]['file_name']
            # remove the hash
            strmIndex = check_parent.find('strm', 0)
            index = check_parent.find('-', strmIndex)
            check_parent = check_parent[:index]
            res_dict[item] = check_parent
            logger.debug(f"{pid=} Added parent {check_parent}")
        except Exception as e:
            logger.warning(f'{pid=} Skipping {item}, cannot get parents ({e}).')
            continue

        last_request = datetime.now()
        dt = (last_request - now).total_seconds()

        wait = (1.0 / SAM_RPS_MAX) - dt

        # rate limit
        if wait > 0:
            # once again, add a little variance
            wait *= random.uniform(1, SMEAR_MAX)
            logger.debug(f'{pid=} Adding sleep: {wait}')
            time.sleep(wait)

    _result.put((res_dict))
    return

def retire_file(filename: str, dry_run=False, delete=True):
    """Remove a file's location, retire it from SAM, and delete the file"""

    loc = None
    fpath = None
    try:
        loc = SAMWeb_Client.locateFile(filename)
        loc = loc[0]["location"]
        loc=loc.removeprefix("enstore:")
        loc=loc.removeprefix("dcache:")
        fpath = f"{loc}/{filename}"
    except Exception as e:
        logger.warning(f"Cannot remove file location for {filename} ({e})")

    if dry_run:
        if loc is not None:
            logger.debug(f"SAMWeb_Client.removeFileLocation({filename}, {loc})")
        logger.debug(f"SAMWeb_Client.retireFile({filename})")
        if (loc is not None and delete):
            logger.debug(f"os.system('rm -f {fpath}')")

    else:
        if loc is not None:
            try:
                SAMWeb_Client.removeFileLocation(filename, loc)
            except samweb_client.exceptions.FileLocationNotFound as e:
                logger.error(f"Could not remove file {filename} from location {loc} as it was not located there")
        logger.warning(f"Retiring file {filename}...")
        SAMWeb_Client.retireFile(filename)
        if (loc is not None and delete):
            os.system('rm -f {fpath}')

    return

def _removeDuplicates(_queue: multiprocessing.Queue(), _result: multiprocessing.Queue()):
    """
    Retires each file inside the queue
    """

    # random sleeps ensures the process declarations are somewhat spread out
    # first random sleep spreads out the processes 
    time.sleep(random.uniform(0, 5))
    pid = multiprocessing.current_process().name
    logger.info(f'{pid=} start')

    nretired = 0
    while True:
        try:
            item = _queue.get(timeout=10)
        except queue.Empty:
            break

        logger.warning(f'{pid=} Got {item}')
        now = datetime.now()

        # Add a check. If the item has children, complain and do nothing. You should do cleanup
        # downstream first to avoid breaking parent links
        try:
            try:
                if( SAMWeb_Client.getFileLineage( "children", item ) is not None ):
                    retire_file(item, dry_run=args.dry_run, delete=args.delete)
                    nretired += 1
                else:
                    logger.warning(f'{pid=} Skipping {item}, there are children!! Deal with these first')
                    continue
            except Exception:
                try:
                    retire_file(item, dry_run=args.dry_run, delete=args.delete)
                    nretired += 1
                except Exception as e:
                    logger.warning(f'{pid=} Skipping {item}, exception ({e}).')
        except Exception as e:
            logger.warning(f'{pid=} Skipping {item}, exception ({e}).')
            continue

        last_request = datetime.now()
        dt = (last_request - now).total_seconds()

        wait = (1.0 / SAM_RPS_MAX) - dt

        # rate limit
        if wait > 0:
            # once again, add a little variance
            wait *= random.uniform(1, SMEAR_MAX)
            logger.debug(f'{pid=} Adding sleep: {wait}')
            time.sleep(wait)

    _result.put((nretired))
    return

def main(args: dict) -> None:

    if args.dry_run:
        logger.info("I will not actually delete files, I am in dry_run mode.")

    if not args.delete:
        logger.info("I will only remove file locations and retire them from SAM.")
    
    tstart = datetime.now()
    try:
        files = SAMWeb_Client.listFiles(defname=args.dataset, stream=False)
        print("We start off with", len(files), "files")
    except Exception as e:
        logger.fatal(f"FATAL - Cannot get dataset ({e})")
        exit(1)
    nprocesses = 0

    # file counter only used to limit spawning new processes. Wait for NFILES_MIN files before spawning
    nfiles_reset = 0
    nfiles = 0
    file1_queue = multiprocessing.Queue()
    ancestor_queue = multiprocessing.Queue()
    processes = []

    # In the first loop, find all the ancestors of all the files and build a dictionary out of them
    # This should consume < 100 MB of memory
    
    for f in files:
        file1_queue.put(f)
        nfiles_reset += 1
        nfiles += 1

        # spawn a new process for files until we reach the max number
        # of processes. New process is only spawned once there are at least
        # NFILES_MIN files (fewer processes for small batches of O(10) files)
        if nprocesses < NPROCESS_MAX and (nfiles_reset > NFILES_MIN or nprocesses == 0):
            nprocesses += 1
            logger.info(f'Spawning process {nprocesses=}')
            t = multiprocessing.Process(target=_buildAncestors, args=(file1_queue, ancestor_queue))
            processes.append(t)
            t.start()
            nfiles_reset = 0

    ancestor_map = {}
    for _ in processes:
        rd = ancestor_queue.get(block=True) # wait until result
        logger.warning(f"Updating global map with another {len(rd)} entries")
        ancestor_map.update(rd)
    for p in processes:
        p.join(timeout=20)

    logger.warning(f"Ancestor map has {len(ancestor_map)} items")

    files_to_retire = []
    # Given that, find a list of all the files that need to be retired
    # Invert the map
    inverse_map = defaultdict(list)
    for key, item in ancestor_map.items():
        inverse_map[item].append(key)

    # Get duplicates
    for files in inverse_map.values():
        if len(files) > 1:
            for f in files:
                try:
                    SAMWeb_Client.getMetadata(f)
                except: # Definitely retire children of retired files
                    logger.warning(f"Adding {f} to be retired, its parent is not found in SAM")
                    files_to_retire.extend(f)
                    files = files[1:]
            files_to_retire.extend(files[1:]) # all but 0th key

    logger.warning(f"There are {len(files_to_retire)} duplicates here")

    # Remove duplicates
    nprocesses = 0
    # file counter only used to limit spawning new processes. Wait for NFILES_MIN files before spawning
    nfiles_reset = 0
    nfiles = 0
    file2_queue = multiprocessing.Queue()
    retired_queue = multiprocessing.Queue()
    processes = []
    for f in files_to_retire:
        file2_queue.put(f)
        nfiles_reset += 1
        nfiles += 1

        # spawn a new process for files until we reach the max number
        # of processes. New process is only spawned once there are at least
        # NFILES_MIN files (fewer processes for small batches of O(10) files)
        if nprocesses < NPROCESS_MAX and (nfiles_reset > NFILES_MIN or nprocesses == 0):
            nprocesses += 1
            logger.info(f'Spawning process {nprocesses=}')
            t = multiprocessing.Process(target=_removeDuplicates, args=(file2_queue, retired_queue))
            processes.append(t)
            t.start()
            nfiles_reset = 0

    nretired = 0
    for p in processes:
        p.join(timeout=20)
    tend = datetime.now()
    while True:
        try:
            nr = retired_queue.get(block=False)
            nretired += nr
        except queue.Empty:
            break
            
    logger.info('Done')
    dt = (tend - tstart).total_seconds()
    logger.info(f'Processed {nfiles} files in {dt:.2f} seconds ({nfiles / dt:.2f} files per second) and removed {nretired} files')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        prog='sam_delete_duplicates',
        description='Retires and deletes duplicate files from SAM.')
    parser.add_argument('-s', '--dataset', type=str, required=True, help='SAM dataset to iterate over')
    parser.add_argument('-D', '--dry_run', action='store_true', help='Do not actually retire files')
    parser.add_argument('-d', '--delete', action='store_false', help='Delete file from disk after it has been retired from SAM')
    args = parser.parse_args()

    formatter = logging.Formatter('[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s')

    file_handler = logging.FileHandler(filename='sam_delete_duplicates.log')
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)

    stdout_handler = logging.StreamHandler(stream=sys.stdout)
    stdout_handler.setLevel(logging.WARNING)
    stdout_handler.setFormatter(formatter)

    logger.setLevel(logging.DEBUG)
    logger.addHandler(file_handler)
    logger.addHandler(stdout_handler)


    main(args)
