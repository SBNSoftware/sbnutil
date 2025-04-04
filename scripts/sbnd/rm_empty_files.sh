#!/bin/sh
# Run event_count program on artroot files produced by a given fcl
# If files have no events, remove them.

if [ -z $1 ]; then
    exit 1
fi

FCLFILE=$1
SEARCH_PATH="."
# SEARCH_PATH="/pnfs/sbn/data_add/sbnd/commissioning/run17899_decoded"

# for getting the file patterns from the fcl file
# PATTERNS=$(fhicl-dump "${FCLFILE}" \
#        | grep "fileName" \
#        | awk '{print $2}' \
#        | sed 's/"//g' \
#        | sed -r 's/\%[[:alpha:]]+/\*/g')

PATTERNS=("*.root")

for p in ${PATTERNS[@]}; do
    echo "Pattern ${p}"
    find "${SEARCH_PATH}" -name $p -exec sh -c 'count_events "$0" | head -n 1 | awk "{if(\$4==0){print \$1}}" | xargs -r rm' {} \;
done
