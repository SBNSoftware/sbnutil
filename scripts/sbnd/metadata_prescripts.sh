#!/bin/sh
sh sbnpoms_wrapperfcl_maker.sh --fclname $1 --wrappername ${CONDOR_DIR_INPUT}/$2

export MT_ENV_FCLNAME=$1
export my_cpurl=$(ifdh findProject ${SAM_PROJECT} ${SAM_STATION} ${EXPERIMENT}) && echo " my_cpurl is ${my_cpurl}"
export my_furi=$(ifdh getNextFile ${my_cpurl} ${SAM_CONSUMER_ID}) && echo "my_furi is ${my_furi}"
export PARENT_FILE_SAM=$(basename ${my_furi}) && echo "Here is the PARENT_FILE_SAM..." && echo " ${PARENT_FILE_SAM}"
sh ${CONDOR_DIR_INPUT}/sbndpoms_metadata_injector.sh --writeExtraMetadata ${PARENT_FILE_SAM} > extra_metadata.json
export MT_CONFIGURATION=$(cat extra_metadata.json | echo $(awk -F "\"configuration.name\":" '{print $2}') | echo $(awk -F "\"," '{print $1}') | echo $(awk -F "\"" '{print $2}'))
export MT_BEAMTYPE=$(cat extra_metadata.json | echo $(awk -F "\"sbn_dm.beam_type\":" '{print $2}') | echo $(awk -F "\"," '{print $1}') | echo $(awk -F "\"" '{print $2}'))
export MT_DETECTOR=$(cat extra_metadata.json | echo $(awk -F "\"sbn_dm.detector\":" '{print $2}') | echo $(awk -F "\"," '{print $1}') | echo $(awk -F "\"" '{print $2}'))
export MT_EVENTCOUNT=$(cat extra_metadata.json | echo $(awk -F "\"sbn_dm.event_count\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
export MT_RANDOM=$(cat extra_metadata.json | echo $(awk -F "\"sbnd.random\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
export MT_RANDOMRUN=$(cat extra_metadata.json | echo $(awk -F "\"sbnd.random_run\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
export MT_DATASTREAM=$(cat extra_metadata.json | echo $(awk -F "\"data_stream\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
# find the stream name from the PARENT_FILE_SAM
filtered_stream_name=${PARENT_FILE_SAM#*_strm}
filtered_stream_name=${filtered_stream_name%_*}
filtered_stream_name=${filtered_stream_name,,} # to lowercase
export MT_SBND_STREAM_NAME=${filtered_stream_name} # this is it
echo "metadata_prescripts.sh done"
