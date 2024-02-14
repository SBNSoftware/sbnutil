#!/bin/bash

echo
echo "Starting find incomplete runs script"
echo -e "\tList of definitions in $1"
echo -e "\tSaving incomplete runs in $2.removal.runs.txt"
echo -e "\tand corresponding files in $2.removal.files.txt"
echo

TOTALFILES=0
touch $2.removal.runs.txt
touch $2.removal.files.txt

for DEF in `cat $1`
do
    echo "Definition: $DEF"
    echo

    for FILE in $(samweb -e sbnd list-definition-files $DEF); 
    do 
	let "TOTALFILES=TOTALFILES+1"
	echo "Processing file $TOTALFILES: $FILE"
	
	RUN=$(samweb -e sbnd get-metadata $FILE | grep Runs |  cut -d":" -f2 | cut -d "(" -f1); 
	
	for DEF2 in `cat $1`
	do
	    if [[ $DEF == $DEF2 ]]
	    then
		continue
	    elif [[ $(samweb -e sbnd list-files "defname:$DEF2 and run_number $RUN" | wc -l) -ne 1 ]]
	    then
		if [[ `cat $2.removal.runs.txt | grep $RUN | wc -l` -eq 0 ]]
		then 
		    echo $RUN >> $2.removal.runs.txt
		fi
	    fi
	done
    done
done

echo
echo "Script finished"
echo "Total number of runs: $(cat $2.removal.runs.txt | wc -l)"

for DEF in `cat $1`
do
    TOTAL=0
    for RUNS in `cat $2.removal.runs.txt`
    do
	FILES=$(samweb -e sbnd list-files "defname: $DEF and run_number $RUNS")

	for FILE in $FILES
	do
	    if [[ $FILE ]]
	    then
		let "TOTAL += 1"
		echo $FILE >> $2.removal.files.txt
	    fi
	done
    done
    
    echo "For $DEF we have:"
    echo "$TOTAL to be removed"
    echo
done
