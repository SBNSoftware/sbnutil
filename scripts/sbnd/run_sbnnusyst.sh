#!/bin/bash

# =============================================================================
# run_sbnnusyst.sh
#
# Executable wrapper for the sbnnusyst POMS stage.
#
# In multifile mode fife_wrap appends the fetched name of the current input
# file to the end of the first executable's command line, and UpdateReweight
# exits with usage on any unknown argument (confirmed in a real job). The
# cfg therefore runs
#     sh ${CONDOR_DIR_INPUT}/run_sbnnusyst.sh <knobs.fcl> [<appended fname>]
# This wrapper uses only $1 (the fcl) and ignores everything else.
# =============================================================================

fcl=$1
shift
echo "(ignoring extra arguments: $@)"
echo "Running: UpdateReweight -c ${fcl} -i input.list -o output.root"
UpdateReweight -c ${fcl} -i input.list -o output.root
