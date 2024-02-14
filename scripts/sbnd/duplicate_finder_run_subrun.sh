#!/bin/bash

echo
echo "Starting duplicate finder script"
echo "With defname: $1"
echo "Placing duplicates in $2"
echo

TOTALFILES=0
DUPES=0
touch $2

for FILE in $(samweb -e sbnd list-definition-files $1); 
do 
  let "TOTALFILES=TOTALFILES+1"
  echo "Processing file $TOTALFILES: $FILE"

  RUN=$(samweb -e sbnd get-metadata $FILE | grep Runs |  cut -d":" -f2 | cut -d "(" -f1); 
  RUN_FILES=$(samweb -e sbnd list-files "defname:$1 and run_number $RUN")

  if [[ $(echo "$RUN_FILES" | wc -l) -gt 1 ]]
  then
      echo "=========================================================="
      echo "NEW DUPLICATES for Run: $RUN"
      for DUPE in $RUN_FILES
      do
	  if [[ "$DUPE" != "$FILE" && `cat $2 | grep $FILE | wc -l` -eq 0 ]]
	  then
	      echo -e "\t $DUPE"
	      echo $DUPE >> $2
	      let "DUPES=DUPES+1"
	  fi
      done
      echo "=========================================================="
  fi
done

echo
echo "---- Finishing Script ----"
echo "Processed $TOTALFILES files"
echo "with $DUPES duplicate files"
echo "which should be removed and"
echo "retired."
echo

