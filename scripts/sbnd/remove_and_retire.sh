#!/bin/bash

echo
echo "Starting removal and retiring script"
echo "With input list $1"
echo

for FILE in `cat $1`
do
    echo "Removing $FILE"
    LOC=$(samweb -e sbnd get-file-access-url $FILE)
    ifdh rm $LOC
    samweb -e sbnd retire-file $FILE
done

echo
echo "---- Finishing Script ----"
echo
