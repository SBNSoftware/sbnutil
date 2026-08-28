#! /bin/bash -
# fife_wrap's multifile loop always appends the SAM-consumed filename as the
# trailing, unflagged argument to executable index 0 (see fife_wrap's
# file_loop(): "if i == 0: cmdlist.append(fname)"). It never does this for
# any later executable. This script exists purely to occupy that index-0
# slot, so it can capture that value for a later executable (mix) to use.
#
# Depending on sam_consumer.schema (this campaign uses schema=root), $1 may
# be a local path OR a root://... XROOTD URL -- it is not something you can
# mv/cp as a local file. lar's -s understands both forms natively, so we just
# record the string as-is rather than trying to move any bytes around.
echo "$1" > real_data_input.txt
cat real_data_input.txt

export my_furi="$1" && echo "my_furi is ${my_furi}"
export PARENT_FILE_SAM=$(basename ${my_furi}) && echo "Here is the PARENT_FILE_SAM..." && echo " ${PARENT_FILE_SAM}"

