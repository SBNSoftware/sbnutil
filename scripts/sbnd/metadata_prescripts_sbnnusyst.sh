#!/bin/bash

# =============================================================================
# metadata_prescripts_sbnnusyst.sh
#
# Prescript for the AR23+ CAF reprocessing (sbnnusyst) POMS stage.
# Tweaked from metadata_prescripts.sh:
#   - takes NO arguments (there are no wrapper fcls to build for
#     UpdateReweight, so the sbnpoms_wrapperfcl_maker.sh calls are gone)
#   - does NOT call getNextFile itself: input files are handled by the
#     fife_wrap multifile loop + mix_sbnnusyst.sh, which fills input.list
#
# What it does:
#   - exports my_cpurl (the SAM project URL), needed together with
#     SAM_CONSUMER_ID (exported by fife_wrap before prescripts run) by
#     mix_sbnnusyst.sh to drain the file queue and by the postscript to mark
#     files consumed
#   - initialises an empty input.list in the job work directory
#
# fife_wrap runs pre/mix/post scripts through a common bash and re-inhales
# the environment afterwards, so exports made here are visible to the mix
# script, the executable and the postscripts.
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

echo "export my_cpurl=\$(ifdh findProject ${SAM_PROJECT} ${SAM_STATION} ${EXPERIMENT})"
export my_cpurl=$(ifdh findProject ${SAM_PROJECT} ${SAM_STATION} ${EXPERIMENT})
echo "my_cpurl is ${my_cpurl}"
echo "SAM_CONSUMER_ID is ${SAM_CONSUMER_ID}"

export WORKDIR=${PWD}
echo "WORKDIR is ${WORKDIR}"

# job_setup.mix must be a single space-free token (see cfg), so the mix
# script is executed directly rather than sourced -- make sure the dropbox
# copy is executable (fife_wrap only chmods prescript/postscript files).
chmod +x ${CONDOR_DIR_INPUT}/mix_sbnnusyst.sh 2>/dev/null \
    && echo "chmod +x ${CONDOR_DIR_INPUT}/mix_sbnnusyst.sh" \
    || echo "WARNING: could not chmod ${CONDOR_DIR_INPUT}/mix_sbnnusyst.sh"

# fresh input.list for this job; filled by mix_sbnnusyst.sh
rm -f input.list
touch input.list

echo "$0 done"
