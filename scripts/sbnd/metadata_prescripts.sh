#!/bin/sh
sh sbnpoms_wrapperfcl_maker.sh --fclname $1 --wrappername ${CONDOR_DIR_INPUT}/$2
if [[ $# -gt 2 ]] ; then
    echo "I will try to make the POT wrapper fcl file now"
    echo "Running command: sh sbnpoms_wrapperfcl_maker.sh --fclname $3 --wrappername ${CONDOR_DIR_INPUT}/$4"
    sh sbnpoms_wrapperfcl_maker.sh --fclname $3 --wrappername ${CONDOR_DIR_INPUT}/$4
    echo "Done. Here it is:"
    cat ${CONDOR_DIR_INPUT}/$4
fi

export MT_ENV_FCLNAME=$1
echo "export my_cpurl=$(ifdh findProject ${SAM_PROJECT} ${SAM_STATION} ${EXPERIMENT}) && echo \"my_cpurl is ${my_cpurl}\""
export my_cpurl=$(ifdh findProject ${SAM_PROJECT} ${SAM_STATION} ${EXPERIMENT}) && echo "my_cpurl is ${my_cpurl}"
echo "export my_furi=$(ifdh getNextFile ${my_cpurl} ${SAM_CONSUMER_ID}) && echo \"my_furi is ${my_furi}\""
export my_furi=$(ifdh getNextFile ${my_cpurl} ${SAM_CONSUMER_ID}) && echo "my_furi is ${my_furi}"
echo "export PARENT_FILE_SAM=$(basename ${my_furi}) && echo \"Here is the PARENT_FILE_SAM...\" && echo \" ${PARENT_FILE_SAM}\""
export PARENT_FILE_SAM=$(basename ${my_furi}) && echo "Here is the PARENT_FILE_SAM..." && echo " ${PARENT_FILE_SAM}"
if [[ $(echo $1 | grep -e "genie") == "" ]] ; then
    echo "sh ${CONDOR_DIR_INPUT}/sbndpoms_metadata_injector.sh --writeExtraMetadata ${PARENT_FILE_SAM} > extra_metadata.json"
    sh ${CONDOR_DIR_INPUT}/sbndpoms_metadata_injector.sh --writeExtraMetadata ${PARENT_FILE_SAM} > extra_metadata.json
    echo "Start exporting now..."
    export MT_CONFIGURATION=$(jq -r '."configuration.name" // empty' extra_metadata.json)
    export MT_BEAMTYPE=$(jq -r '."sbn_dm.beam_type" // empty' extra_metadata.json)
    export MT_DETECTOR=$(jq -r '."sbn_dm.detector" // empty' extra_metadata.json)
    export MT_EVENTCOUNT=$(jq -r '."sbn_dm.event_count" // empty' extra_metadata.json)
    export MT_RANDOM=$(jq -r '."sbnd.random" // empty' extra_metadata.json)
    export MT_RANDOMRUN=$(jq -r '."sbnd.random_run" // empty' extra_metadata.json)
    export MT_DATASTREAM=$(jq -r '.data_stream // empty' extra_metadata.json)
    # find the stream name from the PARENT_FILE_SAM
    filtered_stream_name=${PARENT_FILE_SAM#*_strm}
    filtered_stream_name=${filtered_stream_name%_*}
    filtered_stream_name=${filtered_stream_name,,} # to lowercase
    export MT_SBND_STREAM_NAME=${filtered_stream_name} # this is it
else
    # fetch PARENT_FILE_SAM (which is a fcl) to ${WORKDIR}
    echo -e "Fetching ${PARENT_FILE_SAM} to ${WORKDIR}..."
    xurl=$(samweb get-file-access-url --schema=xroot ${PARENT_FILE_SAM})
    ifdh cp -D ${xurl} ${WORKDIR}
    # Pipe it to a file we can name
    cp ${WORKDIR}/${PARENT_FILE_SAM} ${WORKDIR}/initial.fcl
    echo -e "And here is the contents of ${WORKDIR}...."
    ls -lt ${WORKDIR}
fi
echo "metadata_prescripts.sh done"
