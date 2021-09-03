#! /usr/bin/env python
########################################################################
#
# Name: metadata_estractor.py
#
# Purpose: Metadata extractor for artroot files, based on sam_metadata_dumper.
#          Metadata is output to standard output in json format.
#
# Usage:
#
# sbnpoms_metadata_extractor.py [options] <artroot-file>
#
# Arguments:
#
# <artroot-file> - Path of artroot file.
#
# Options:
#
# -h|--help - Print help.
# -e|--experiment <exp> - Experiment (default $SAM_EXPERIMENT).
#
########################################################################
#
# Created: 31-Aug-2021  H. Greenlee
#
########################################################################

import sys, os, subprocess, json
import samweb_cli

samweb = None
experiment = ''

# Help function.

def help():

    filename = sys.argv[0]
    file = open(filename, 'r')

    doprint=0
    
    for line in file.readlines():
        if line.startswith('# sbnpoms_metadata_extractor.py'):
            doprint = 1
        elif (line.startswith('######') or line.startswith('# Usage notes:')) and doprint:
            doprint = 0
        if doprint:
            if len(line) > 2:
                print(line[2:], end='')
            else:
                print()


# Get initialized samweb object.

def get_samweb():

    global samweb
    global experiment

    if samweb == None:
        samweb = samweb_cli.SAMWebClient(experiment=experiment)

    return samweb


# Check the validity of a single parent.
# Return value is a guaranteed valid list of parents (may be empty list)
# Fcl list also updated to include fcls associated with virtual parents.

def check_parent(parentarg, dir, fcllist):

    result = []

    # Parent arg can be passed in different ways depending on the source.

    parent = ''
    if type(parentarg) == type(''):
        parent = parentarg
    elif type(parentarg) == type(b''):
        parent = parentarg.decode('utf8')
    elif type(parentarg) == type({}):
        if 'file_name' in parentarg:
            parent = parentarg['file_name']
        elif 'file_id' in parentarg:
            parent = parentarg['file_id']
    if parent == '' or type(parent) != type(''):
        raise FileNotFoundError


    # Check whether this parent file has metadata already.

    samweb = get_samweb()
    has_metadata = False
    try:
        mdparent = samweb.getMetadata(parent)
        has_metadata = True
    except samweb_cli.FileNotFound:
        has_metadata = False

    if has_metadata:

        # If this parent has metadata, return this one file in the form of a list.
        # Don't add anything to fcl list.

        result = [parent]

    else:

        # If this parent doesn't have metadata, try to locate file.

        local_file = os.path.join(dir, parent)
        if os.path.exists(local_file):

            # Found local file.  Extract parent information from file.

            md = get_metadata(local_file)

            if 'parents' in md:
                for prnt in md['parents']:
                    result.extend(check_parent(prnt, dir, fcllist))

            # Append fcl file to front of fcl list.

            if 'fcl.name' in md and not md['fcl.name'] in fcllist:
                fcllist.insert(1, md['fcl.name'])

        else:

            # Couldn't find file.  Raise exception.

            raise FileNotFoundError

    # Done.

    return result


# Validate parents metadata according to the following method.
#
# 1.  If parent is already declared to sam, do nothing.
#
# 2.  If parent is not declared to sam, look for local file with
#     the same name in the same directory as the original file, or the
#     the current directory, and extract parents recursively from local
#     file.
#
# 3.  If parent is not declared, and there is no local file with the same
#     name can be found, raise an exception.

def validate_parents(md, dir):
    if 'parents' in md:
        parents = md['parents']
        new_parents = []
        fcllist = []
        for parent in parents:
            new_parents.extend(check_parent(parent, dir, fcllist))
        if len(new_parents) == 0:

            # If updated parent list is empty, delete 'parents' from metadata.

            del md['parents']

        else:

            # Insert updated parent list into metadata.

            md['parents'] = new_parents

        # Maybe update fcl.name parameter.

        if len(fcllist) > 0:
            if 'fcl.name' in md and not md['fcl.name'] in fcllist:
                fcllist.append(md['fcl.name'])
            md['fcl.name'] = '/'.join(fcllist)

    # Done.

    return


# Function to extract metadata as python dictionary.

def get_metadata(artroot):

    # Run sam_metadata_dumper.

    md = {}
    cmd = ['sam_metadata_dumper', artroot]
    proc = subprocess.run(cmd, capture_output=True, encoding='utf8')
    if proc.returncode == 0:

        # Sam_metadata_dumper succeeded.
        # Parse json output into python dictionary.

        md0 = json.loads(proc.stdout)

        # Loop over one key to extract file name.

        for k in md0:
            md = md0[k]
            md['file_name'] = k
            break

    else:

        # Sam_metadata_dumper failed.
        # Try to read metadata for corrsponding json file.

        jsonfile = '%s.json' % artroot
        if os.path.exists(jsonfile):
            f = open(jsonfile)
            md = json.load(f)
        else:
            print('sam_metadata_dumper returned status %d' % proc.returncode)
            print('No corresponding json file found, giving up.')
            sys.exit(proc.returncode)

    # Do metadata checks and updates here.
    # Make sure metadata contains file name.

    if not 'file_name' in md:
        md['file_name'] = os.path.basename(artroot)
            
    # Make sure metadata contains file size.

    if not 'file_size' in md and os.path.exists(artroot):
        stat = os.stat(artroot)
        md['file_size'] = stat.st_size

    # Make sure application family/name/version is its own dictionary

    if not 'application' in md:
        md['application'] = {}
        if 'application.family' in md:
            md['application']['family'] = md['application.family']
            del md['application.family']
        if 'art.process_name' in md:
            md['application']['name'] = md['art.process_name']
        if 'application.version' in md:
            md['application']['version'] = md['application.version']
            del md['application.version']

    # Handle first/last event.

    if 'art.first_event' in md:
        md['first_event'] = md['art.first_event'][2]
        del md['art.first_event']
    if 'art.last_event' in md:
        md['last_event'] = md['art.last_event'][2]
        del md['art.last_event']

    # Ignore 'art.run_type' (run_type is also contained in 'runs' metadata).

    if 'art.run_type' in md:
        del md['art.run_type']

    # Done.

    return md


# Main procedure.

def main(argv):

    global experiment

    # Parse arguments.

    artroot = ''
    experiment = ''
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
        elif args[0].startswith('-'):
            print('Unknown option %s' % args[0])
            sys.exit(1)
        else:

            # Positional arguments.

            if artroot == '':
                artroot = args[0]
                del args[0]
            else:
                print('More than one positional argument not allowed.')
                sys.exit(1)

    # Check validity of options and arguments.

    if artroot == '':
        print('No artroot file specified.')
        sys.exit(1)

    if not os.path.exists(artroot) and not os.path.exists('%s.json' % artroot):
        print('Artroot file %s does not exist and there is no corresponding json file.' % artroot)
        sys.exit(1)

    # Extract metadata as python dictionary.

    md = get_metadata(artroot)

    # Validate parent metadata.

    dir = os.path.dirname(os.path.abspath(artroot))
    validate_parents(md, dir)

    # Pretty print json metadata.

    json.dump(md, sys.stdout, sort_keys=True, indent=2)
    print()   # Json dump misses final newline.

    # Done

    return 0

# Invoke main program.

if __name__ == "__main__":
    sys.exit(main(sys.argv))