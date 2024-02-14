#!/bin/bash

if [[ $2 ]]
then
    DEFS=$(samweb -e sbnd list-definitions | grep 23B | grep $1 | grep -v $2)
else
    DEFS=$(samweb -e sbnd list-definitions | grep 23B | grep $1)
fi

for DEF in ${DEFS}
do
    if [[ $DEF == *"Slice"* || $DEF == *"slice"* || $DEF == *"test"* ]]
    then
	continue
    fi

    echo "$DEF"
done
    

