#!/bin/bash

# =============================================================================
# mix_sbnnusyst.sh
#
# fife_wrap 'mix' hook for the AR23+ CAF reprocessing (sbnnusyst) POMS stage.
#
# fife_wrap (multifile mode) calls this after fetching each input file, with
#   ${fname} = the fetched file  and  ${furi} = its xrootd URI
# in the environment.
#
# On the FIRST call this script records the current file's xrootd URI in
# input.list and then DRAINS every remaining file in the SAM project queue
# (up to the [sam_consumer] limit = n_files_per_job) into input.list, marking
# each drained file 'transferred'. The fife_wrap file loop therefore makes
# exactly ONE pass, and UpdateReweight runs exactly ONCE over the full list.
#
# Bookkeeping:
#   - the FIRST file's final status (consumed/skipped) is set by fife_wrap
#     itself, based on the executable's exit code
#   - the DRAINED files are marked 'consumed' by
#     metadata_postscripts_sbnnusyst.sh only after a successful run, so a
#     failed job leaves them recoverable
#
# Needs: my_cpurl (exported by metadata_prescripts_sbnnusyst.sh) and
#        SAM_CONSUMER_ID (exported by fife_wrap).
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

echo "Current file: ${furi}"
echo "${furi}" >> input.list

# Drain the rest of the SAM queue into input.list
lastf="${furi}"
while : ; do
    nextf=$(ifdh getNextFile ${my_cpurl} ${SAM_CONSUMER_ID})
    if [[ -z "${nextf}" || "${nextf}" == "${lastf}" ]]; then
        break
    fi
    ifdh updateFileStatus ${my_cpurl} ${SAM_CONSUMER_ID} $(basename ${nextf}) transferred
    echo "${nextf}" >> input.list
    lastf="${nextf}"
done

echo "input.list now contains $(wc -l < input.list) files:"
cat input.list

echo "$0 done"
