#!/usr/bin/bash

echo -e "Inside build_event_numbers.sh "

DECODE_FILE=$(find ./ -iname 'decoded-raw_filtered_*.root' | head -n 1)
RECO1_FILE=$(find ./ -iname '*.root' | grep 'reco1' | grep -v 'reco2' | grep -v 'hist')
RECO2_FILE=$(find ./ -iname '*.root' | grep 'reco2' | grep -v 'caf' | grep -v 'hist')
#CAF_FILE=$(find ./ -iname '*.caf.root' | grep -v 'flat' | grep -v 'hist')

ACTIVE_FILE=
case $1 in
    "decode")
	ACTIVE_FILE=${DECODE_FILE}
	;;
    "reco1")
	ACTIVE_FILE=${RECO1_FILE}
	;;
    "reco2")
	ACTIVE_FILE=${RECO2_FILE}
	;;
    "caf")
	ACTIVE_FILE=${CAF_FILE}
	;;
    "reco2_caf")
	ACTIVE_FILE=$(find /srv/jsb_tmp/ -iname '*LOG*')
	;;
	  "decode_reco1_reco2")
	ACTIVE_FILE=$(find /srv/jsb_tmp/ -iname '*LOG*')
	;;
    "decode_reco1_reco2_caf")
	ACTIVE_FILE=$(find /srv/jsb_tmp/ -iname '*LOG*')
	;;
    *)
	>&2 echo "ERROR on build_event_numbers.sh: unknown stage"
	echo -e "ERROR on build_event_numbers.sh: unknown stage"
	exit 1
esac

echo -e "Building event numbers for input file "$ACTIVE_FILE " ..."
>&2 echo -e "Building event numbers for input file "$ACTIVE_FILE " ..."

#cmd="lar -c eventdump.fcl -s $ACTIVE_FILE | grep 'Begin processing' | awk -F \"event: \" '{print $2}' | awk -F \" at\" '{print $1}' > list_dump.log"
#>&2 echo -e "Using command ${cmd}"

#eval $cmd
#cat list_dump.log
#>&2 cat list_dump.log

EVENTSTRING="_"
#for i in $(grep ${ACTIVE_FILE} -e "GnocchiCalorimetry" | awk -F "event: " {'print $2'} | uniq | tr -d '') ; do
for i in $(grep ${ACTIVE_FILE} -e "Begin processing" | awk -F "event: " {'print $2'} | awk -F " " '{print $1}' | sort -nu | tr -d '') ; do
    EVENTSTRING=${EVENTSTRING}${i}"_"
done

echo "Exporting MT_EVENTSTRING=${EVENTSTRING}"

export MT_EVENTSTRING=${EVENTSTRING}

echo -e "build_event_numbers.sh Done"
