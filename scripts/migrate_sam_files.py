#! /usr/bin/env python
########################################################################
#
# Name: migrate_sam_files.py
#
# Purpose: Migrate files from source SAM database (SBND or ICARUS) to 
#          target SAM database (SBN).
#
# Usage:
#
# migrate_sam_files.py [options]
#
# Options:
#
# -h|--help             - Print help.
# -e|--experiment <exp> - Experiment (default $SAM_EXPERIMENT).
# -n|--nfiles <n>       - Number of files to query per iteration (default no limit).
# --def <defname>       - Parent definition (optional, default none).
# --file <filename>     - File name (optional, default none).
# --niter <niter>       - Number of iterations (default 1).
# --invalid <file>      - Save unmigrated files in specified file.
#
# Usage notes:
#
#
# 1.  This script can be invoked without any options.  In that case, every
#     file in the source sam database will be migrated to the target database.
#
# 2.  Use options -n|--nfiles, --def, and/or --file to limit the files being
#     migrated at one time.  With option --file, only one file is migrated.
#     It is generally a good idea to specify at least one of these options,
#     to limit the number of files returned by the initial sam query.
#
# 3.  The maximum number of files migrated is <n>*<niter>.
#
# 4.  This script checks and updates parameter sbn.migrate in the source database.
#     The meaning of sbn.migrate is as follows.
#
#     0 - File has been migrated successfully (no further checking needed).
#     1 - File should be checked.
#     2 - Error.  File can not be migrated because of invalid metadata.
#     
#
########################################################################
#
# Created: 9-Aug-2021  H. Greenlee
#
########################################################################

from __future__ import print_function
import sys, os
import samweb_cli

# Statistics.

nqueried = 0
ndeclared = 0
nmodified = 0
nlocations = 0
nmigrated = 0

# Source database metadata queue (list of metadata dictionaries, including file name).

queued_metadata1 = []

# Help function.

def help():

    filename = sys.argv[0]
    file = open(filename, 'r')

    doprint=0
    
    for line in file.readlines():
        if line[2:22] == 'migrate_sam_files.py':
            doprint = 1
        elif (line.startswith('######') or line.startswith('# Usage notes:')) and doprint:
            doprint = 0
        if doprint:
            if len(line) > 2:
                print(line[2:], end='')
            else:
                print()


# Function to flush metadata queue.

def flushMetadata(samweb):

    global queued_metadata1

    if len(queued_metadata1) > 0:
        for md in queued_metadata1:
            print('Updating metadata for file %s' % md['file_name'])
        samweb.modifyMetadata(queued_metadata1)
    queued_metadata1 = []

    # Done.

    return


# Function to update metadata of one file.

def modifyFileMetadata(samweb, f, md):

    global queued_metadata1

    # Add file name to metadata.

    md['file_name'] = f

    # Add metadata to queue.

    queued_metadata1.append(md)

    # Maybe flush queue.

    if len(queued_metadata1) > 21:
        flushMetadata(samweb)

    # Done.

    return


# Print metadata.

def print_metadata(f, md):
    print('\nMetadata for file %s\n' % f)
    for k in md:
        print('%s = %s' % (k, md[k]))


# Check file metadata.
#
# Returns the original value of sbn.migrate in the source database (0, 1, or None).

def check_metadata(samweb1, samweb2, experiment, f, invalid_file):

    global ndeclared
    global nmodified

    print('Checking metadata for file %s' % f)

    # Get metadata for this file.

    md1 = samweb1.getMetadata(f)

    # Check migrate flag.
    # If the migrate flag is zero, this file does not require further checking.

    migrate = None
    if 'sbn.migrate' in md1:
        migrate = md1['sbn.migrate']
        if migrate == 0:
            print('Migrate flag is already reset.')
            return migrate
        if migrate == 2:
            print('Metadata flag is already invalid.')
            return migrate

    # Remove keys that we never want to migrate in the target database.

    for k in ('file_id', 'process_id', 'create_date', 'update_date', 'update_user', 'sbn.migrate', 'sbnd.genie_tune', 'sbnd.genie_tag'):
        if k in md1:
            del md1[k]

    # Add keys that are not in the original database.

    md1['sbn.experiment'] = experiment
    md1['loc.scratch'] = 0

    # Fix up md5 checksum.

    if 'checksum' in md1:
        new_checksum = []
        checksum_updated = False
        for checksum in md1['checksum']:
            if checksum.startswith('md5:'):
                value = checksum[4:]
                while len(value) < 32:
                    value = '0' + value
                    checksum_updated = True
                checksum = 'md5:%s' % value
            new_checksum.append(checksum)
        if checksum_updated:
            print('Fixing md5 checksum for file %s' % f)
            md1['checksum'] = new_checksum

    # Check parents.

    parents_ok = True
    if 'parents' in md1:
        for parent in md1['parents']:

            # Remove file_id from parent dictionary.

            if 'file_id' in parent:
                del parent['file_id']

            # Check whether this parent is retired.
            # Samweb can not declare the child of a retired parent.

            if 'retired' in parent and parent['retired']:
                parents_ok = False

            # Make sure parent is declared in target database.

            if parents_ok:
                pfname = parent['file_name']
                parents_ok = check_file(samweb1, samweb2, experiment, pfname, invalid_file)

    # Quit if this file has any retired parents.

    if not parents_ok:

        # Set the migrate flag to '2' so that this file won't be checked again.

        print('Setting invalid metadata flag in source database.')
        mdr = {}
        mdr['sbn.migrate'] = 2
        samweb1.modifyFileMetadata(f, md=mdr)
        migrate = 2
        nmodified += 1
        return migrate

    # At this point, we think that we need to add or update metadata for file f in 
    # the target database.

    md2 = {}
    md_update = {}
    try:
        md2 = samweb2.getMetadata(f)
    except:
        md2 = {}

    # Calculate metadata update for target datagase.
    # 
    # When modifying metadata (as opposed to declaring for the first time),
    # never update certain fields, including 'user' and 'parents.'

    for k in md1:
        if k in md2:
            if md2[k] != md1[k] and k != 'parents' and k != 'user':
                print('Updating field %s' % k)
                md_update[k] = md1[k]
        else:
            #print('Adding field %s' % k)
            md_update[k] = md1[k]

    if len(md_update) > 0:
        if len(md2) > 0:
            print('Updating metadata for file %s in target database.' % f)
            #print(md_update)
            samweb2.modifyFileMetadata(f, md=md_update)
            nmodified += 1
        else:
            print('Declaring file %s in target database.' % f)
            samweb2.declareFile(md=md_update)
            ndeclared += 1
    else:
        print('Metadata for file %s in target database is already up to date.' % f)

    # Done.

    return migrate


# Check file locations.
# Return True if location check was successful, False otherwise.

def check_locations(samweb1, samweb2, f, invalid_file):

    global nlocations

    print('Checking locations for file %s' % f)
    locs1 = samweb1.locateFile(f)
    locs2_ok = False
    locs2 = []
    try:
        locs2 = samweb2.locateFile(f)
        locs2_ok = True
    except:
        locs2 = []
        locs2_ok = False

    # If locate-file failed in target database, that means that this file has not been
    # declared in the target database.
    # There are use cases where this can happen.
    # In these case, print an error message and quite.

    if not locs2_ok:
        print('Unable to check locations for file %s' % f)
        print('File may not be declared.')
        if invalid_file != '':
            fl = open(invalid_file, 'a')
            fl.write('%s\n' % f)
            fl.close()
        return False

    has_loc1 = False
    for loc1 in locs1:
        has_loc1 = True
        fp1 = loc1['full_path']
        if fp1.find('/scratch/') > 0:
            print('Skipping scratch location %s' % fp1)
        else:
            print('Checking location %s' % fp1)

            # Look for location with the same full_path.

            loc_match = False
            for loc2 in locs2:
                fp2 = loc2['full_path']
                if fp2 == fp1:
                    loc_match = True
                    break
            if loc_match:
                print('Location already exists in target database.')
            else:
                print('Adding location in target database.')
                samweb2.addFileLocation(f, loc1['location'])
                nlocations += 1

    if not has_loc1:
        print('No locations found.')

    # Done.

    return True


# Check file metadata and locations.
# Return True of metadata + location check was successful, False otherwise.

def check_file(samweb1, samweb2, experiment, f, invalid_file):

    global nmigrated

    ok = True

    migrate = check_metadata(samweb1, samweb2, experiment, f, invalid_file)
    if migrate != 0 and migrate != 2:
        ok = check_locations(samweb1, samweb2, f, invalid_file)
        if ok:

            # Update parameter sbn.migrate to be 0 in source database.

            print('Setting parameter sbn.migrate to 0 in source database')
            md_update = {'sbn.migrate': 0}
            modifyFileMetadata(samweb1, f, md_update)
            nmigrated += 1
    if ok and migrate == 2:
        ok = False

    # Done.

    return ok


# Main procedure.

def main(argv):

    global nqueried
    global ndeclared
    global nmodified
    global nlocations
    global nmigrated

    # Parse arguments.

    experiment = ''
    nfiles = 0
    defname = ''
    filename = ''
    niter = 1
    invalid_file = ''
    if 'SAM_EXPERIMENT' in os.environ:
        experiment = os.environ['SAM_EXPERIMENT']

    args = argv[1:]
    while len(args) > 0:
        if args[0] == '-h' or args[0] == '--help' :
            help()
            return 0
        elif (args[0] == '-e' or args[0] == '--experiment') and len(args) > 1:
            experiment = args[1]
            del args[0:2]
        elif (args[0] == '-n' or args[0] == '--nfiles') and len(args) > 1:
            nfiles = int(args[1])
            del args[0:2]
        elif (args[0] == '--def') and len(args) > 1:
            defname = args[1]
            del args[0:2]
        elif (args[0] == '--file') and len(args) > 1:
            filename = args[1]
            del args[0:2]
        elif args[0] == '--niter' and len(args) > 1:
            niter = int(args[1])
            del args[0:2]
        elif args[0] == '--invalid' and len(args) > 1:
            invalid_file = args[1]
            del args[0:2]
        else:
            print('Unknown option %s' % args[0])
            sys.exit(1)

    if invalid_file != '' and os.path.exists(invalid_file):
        os.remove(invalid_file)

    # Prepare sam query.

    samweb1 = samweb_cli.SAMWebClient(experiment=experiment)
    samweb2 = samweb_cli.SAMWebClient(experiment='sbn')
    dim = ''
    if filename != '':
        dim = 'file_name %s' % filename
    elif defname != '':
        dim = 'defname: %s' % defname
    else:
        dim = 'file_id > 0'
    dim += ' minus sbn.migrate 0,2 with availability anylocation,anystatus'
    if nfiles > 0:
        dim += ' with limit %d' % nfiles

    # Iteration loop.

    while niter > 0:
        niter -= 1
        files = samweb1.listFiles(dimensions=dim)
        if len(files) == 0:
            print('No more files.')
            break
        nqueried += len(files)
        for f in files:
            check_file(samweb1, samweb2, experiment, f, invalid_file)

    # Flush metadata.

    flushMetadata(samweb1)

    # Print statistical summary.

    print('\n%d files queried.' % nqueried)
    print('%d files declared.' % ndeclared)
    print('%d files modified.' % nmodified)
    print('%d locations added.' % nlocations)
    print('%d files migrated.' % nmigrated)

    # Done

    return 0

# Invoke main program.

if __name__ == "__main__":
    sys.exit(main(sys.argv))
