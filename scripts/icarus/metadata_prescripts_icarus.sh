#!/bin/sh
# TODO: If we run this with DATA, ensure a wrapper can be done for POT counting.

source /cvmfs/larsoft.opensciencegrid.org/products/setup
setup ifdhc v2_8_0 -q e26:p3915:prof
echo "ifdh in use: $(command -v ifdh) (IFDHC_VERSION=${IFDHC_VERSION:-unset})"

export MT_ENV_FCLNAME=$1
# NB: I am writing this for Ar25 which does overlays.
# For overlays, delegate PARENT_FILE_SAM finding to the `stashDataFile.sh' script
echo "sh ${CONDOR_DIR_INPUT}/icaruspoms_metadata_injector.sh --writeExtraMetadata ${PARENT_FILE_SAM} > extra_metadata.json"
sh ${CONDOR_DIR_INPUT}/icaruspoms_metadata_injector.sh --writeExtraMetadata ${PARENT_FILE_SAM} > extra_metadata.json
echo "Start exporting now..."
export MT_CONFIGURATION=$(cat extra_metadata.json | echo $(awk -F "\"configuration.name\":" '{print $2}') | echo $(awk -F "\"," '{print $1}') | echo $(awk -F "\"" '{print $2}'))
export MT_BEAMTYPE=$(cat extra_metadata.json | echo $(awk -F "\"sbn_dm.beam_type\":" '{print $2}') | echo $(awk -F "\"," '{print $1}') | echo $(awk -F "\"" '{print $2}'))
export MT_DETECTOR=$(cat extra_metadata.json | echo $(awk -F "\"sbn_dm.detector\":" '{print $2}') | echo $(awk -F "\"," '{print $1}') | echo $(awk -F "\"" '{print $2}'))
export MT_EVENTCOUNT=$(cat extra_metadata.json | echo $(awk -F "\"sbn_dm.event_count\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
export MT_RANDOM=$(cat extra_metadata.json | echo $(awk -F "\"sbnd.random\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
export MT_RANDOMRUN=$(cat extra_metadata.json | echo $(awk -F "\"sbnd.random_run\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
export MT_DATASTREAM=$(cat extra_metadata.json | echo $(awk -F "\"data_stream\":" '{print $2}') | echo $(awk -F "," '{print $1}'))
# find the stream name from the PARENT_FILE_SAM
#filtered_stream_name=${PARENT_FILE_SAM#*_strm}
#filtered_stream_name=${filtered_stream_name%_*}
#filtered_stream_name=${filtered_stream_name,,} # to lowercase
#export MT_SBND_STREAM_NAME=${filtered_stream_name} # this is it

echo "metadata_prescripts.sh done"
