#!/bin/bash

echo
echo "Removing defintion: $DEF"
echo

    for FILE in $(samweb -e sbnd list-files "defname: $DEF")
    do
	echo -e '\t' $FILE
	LOC=$(samweb -e sbnd get-file-access-url $FILE)
	ifdh rm $LOC
	samweb -e sbnd retire-file $FILE
    done

    samweb -e sbnd delete-definition $DEF
done
