#!/usr/bin/bash

echo "Here is the working directory..."
pwd
echo "Here are the contents of the current directory..."
ls

if [[ ( $1 == "" ) || ( $# -lt 1 ) ]] ; then
    echo "Error - need at least 1 argument."
    echo "Usage: export_pot_counter.sh <stage>"
fi

# Figure out the file to rename the POT_counted to...
# should be something like %(basename)s_filtered_%%ifb with ifb ofc not evaluated
proper_name="I_AM_UNSET.root"
if [[ $1 == "decode" ]] ; then
    choppy_file=$(find ./ -iname '*choppy*.root' | grep -v 'hist')
    proper_name=decoded-raw_filtered_${choppy_file#*choppy_}
else
    echo "Error - I don't know how to do other stages yet..."
fi

# We need to manually copy the file, and remove the old one
mv $(pwd)/POT_counted.root ${proper_name}
rm -f to_count.root
echo "After copying, here is the contents of the workdir..."
ls
