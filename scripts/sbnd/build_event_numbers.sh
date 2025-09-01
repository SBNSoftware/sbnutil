#!/usr/bin/bash

DECODE_FILE=$(find ./ -iname 'decoded-raw_filtered_*.root' | head -n 1)

echo "Building event numbers for input file "$DECODE_FILE

EVENTSTRING="_"$(lar -c eventdump.fcl -s $DECODE_FILE | grep 'Begin processing' | awk -F "event: " '{print $2}' | awk -F " at" '{print $1}' | tr '\n' '_')

echo "Exporting MT_EVENTSTRING=${EVENTSTRING}"

export MT_EVENTSTRING=${EVENTSTRING}
