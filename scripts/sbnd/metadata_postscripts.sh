#!/bin/bash

# Copied from Vito's area, /exp/icarus/app/users/vito/sam/declare_file.sh
# Adapted for use on postscript stage
# Essentially, build the metadata for the file manually while ignoring artroot.
# Most of this stuff is already exported as env variables, from the prescripts stage.

>&2 echo -e "\n\nSTARTING metadata_postscripts...\n\n"
echo -e "\n\nArgs 1 is " $1 " and 2 is " $2

# Retire any declared files before moving on.
candFile=''
otherFile='' # to handle choppy in decode and nhit_fail in reco1. Also hist in reco2
larcvFile=''
flatFile=''
dataTier=''
processName=''
case $1 in
    "decode")
	decodedFile=$(find ./ -iname '*filtered*.root' | grep -v 'reco')
	candFile=$decodedFile
	otherFile=$(find ./ -iname '*choppy*.root' | grep -v 'reco')
	dataTier='decoded-raw'
	processName='DECODE'
	;;
    "reco1")
	reco1File=$(find ./ -iname 'reco1_*.root' | grep -v 'reco2' | grep -v 'hist')
	candFile=$reco1File
	otherFile=$(find ./ -iname '*nhit_fail*.root' | grep -v 'reco2' | grep -v 'hist')
	larcvFile=$(find ./ -iname '*larcv*.root' | grep -v 'reco2' | grep -v 'hist')
	dataTier='reconstructed'
	processName='Reco1'
	;;
    "reco2")
	reco2File=$(find ./ -iname 'reco2*.root' | grep -v 'caf' | grep -v 'hist')
	candFile=$reco2File
	dataTier='reconstructed'
	if [[ $2 == "true" ]] ; then otherFile=$(find ./ -iname '*.root' | grep 'reco2' | grep 'hist') ; fi
	processName='Reco2'
	;;
    "caf")
	cafFile=$(find ./ -iname 'reco2*.caf.root' | grep -v 'flat' | grep -v 'hist')
	candFile=$cafFile
	flatFile=$(find ./ -iname 'reco2*.flat.caf.root' | grep -v 'hist')
	dataTier='caf'
	processName='caf'
	;;
    *)
	>&2 echo "UNKNOWN STAGE"
esac

>&2 echo -e "\n\nPassed retire check...\n\n"
>&2 echo -e "\n\nHere is the contents of the dir BEFORE renaming...\n\n"
>&2 ls -ltrh
>&2 echo -e "\n\nAnd here is the candidate file...\n\n"
>&2 echo $candFile
>&2 echo -e "\n\nAnd here is the other file...\n\n"
>&2 echo $otherFile

if [[ ${candFile} == "" ]] ; then return ; fi

samweb -e ${SAM_EXPERIMENT} get-metadata --json $(basename ${PARENT_FILE_SAM}) > old_par_md.json

# now I will touch new json files.
MD_FILE=md_$1.json
OTHER_MD_FILE=md_other$1.json
LARCV_MD_FILE=md_larcv$1.json
FLAT_MD_FILE=md_flat$1.json
touch ${MD_FILE}
>&2 echo "Touched $(basename ${MD_FILE})"
if [ ${otherFile} != "" ] && [ $2 == "true" ] ; then touch ${OTHER_MD_FILE} ; fi
if [[ ${larcvFile} != "" ]] ; then touch ${LARCV_MD_FILE}.json ; fi
if [[ ${flatFile} != "" ]] ; then touch ${FLAT_MD_FILE}.json ; fi

# Calculate a new hash. This is to make sure the hash comes from md5sum on the caf file, rather than inheriting one of its parents's hash
old_hash=$(echo ${candFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
echo ${old_hash}${RANDOM}${old_hash}${RANDOM} > fudge.txt # make a new file with essentially random contents, leads to random hash
md5_sum=$(md5sum fudge.txt | awk -F " " '{print $1}')
used_hash=${md5_sum:0:8}-${md5_sum:8:4}-${md5_sum:12:4}-${md5_sum:16:4}-${md5_sum:20:12}
used_hash_prebit=${used_hash:0:2}
echo "The new hash based on MD5 is ${used_hash}"

old_other_hash=$(echo ${otherFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
old_larcv_hash=$(echo ${larcvFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
old_flat_hash=$(echo ${flatFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')

# excise the hash
excised_candFile=${candFile%-${old_hash}*}
excised_otherFile=${otherFile%-${old_other_hash}*}
excised_larcvFile=${larcvFile%-${old_larcv_hash}*}
excised_flatFile=${flatFile%-${old_flat_hash}*}

# inject this hash into the file
newCandFile=${excised_candFile%.root}-${used_hash}.root
if [[ $1 == "caf" ]] ; then
    newCandFile=${excised_candFile%.root}-${used_hash}.caf.root
fi
echo "Injecting the new hash, this becomes ${newCandFile}"
mv ${candFile} ${newCandFile}
newOtherFile=${excised_otherFile%.root}-${used_hash}.root
newLarcvFile=${excised_larcvFile%.root}-${used_hash}.root
newFlatFile=${excised_flatFile%.root}-${used_hash}.flat.caf.root
if [[ ${otherFile} != "" ]] ; then
    echo "Injecting the new hash, the other becomes ${newOtherFile}" ; mv ${otherFile} ${newOtherFile} ; fi
if [[ ${larcvFile} != "" ]] ; then
    echo "Injecting the new hash, the larcv becomes ${newLarcvFile}" ; mv ${larcvFile} ${newLarcvFile} ; fi
if [[ ${flatFile} != "" ]] ; then
    echo "Injecting the new hash, the flat becomes ${newFlatFile}" ; mv ${flatFile} ${newFlatFile} ; fi

# Get the runs 
subRun=$(grep messages.log -e 'subRun' | head -n 1 | awk -F "subRun: " '{print $2}' | awk -F " " '{print $1}')
runString=$(cat old_par_md.json | grep -A 4 -e "\"runs\":" | grep -v "\"runs\"" | tr -d ' ' | tr '\n' ':' | awk -v mysub="$subRun" -F "\"commissioning\"" '{print $1mysub",:|commissioning|"$2}' | tr '|' "\"" | tr ':' '\n' | sed "s/commissioning/physics/g")
if [[ $1 != "decode" ]] ; then
    runString=$(cat old_par_md.json | grep -A 5 -e "\"runs\":" | grep -v "\"runs\"")
fi

#thisParentsRunString=$(cat old_par_md.json | grep -A 5 -e "\"runs\":" | grep -v "\"runs\"")
#runString=${thisParentsRunString}","
#runString=$(echo ${runString} | sed "s/commissioning/physics/g")
#runString=$(echo ${runString} |sed '$ s/,$//') # remove last comma
#runString=$(echo ${runString} |sed '$ s/]$//') # remove last ]

# construct the candFile's json
echo -e "{" >> ${MD_FILE}

echo -e " \"file_name\": \"$(basename ${newCandFile})\"," >> ${MD_FILE}
echo -e " \"file_size\": $(stat -c %s ${newCandFile} | awk -F " " '{print $1}')," >> ${MD_FILE}
echo -e " \"data_tier\": \"${dataTier}\"," >> ${MD_FILE}
echo -e " \"data_stream\": \"${MT_SBND_STREAM_NAME}\"," >> ${MD_FILE}

# file format
echo -e " \"file_format\": \"artroot\"," >> ${MD_FILE}

# Checksum
echo -e " \"checksum\": [" >> ${MD_FILE}
echo -e "$(samweb file-checksum --type=enstore,adler32,md5 ${newCandFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${MD_FILE}
echo -e " ]," >> ${MD_FILE}

# Dataset tag - figure out the raw file creation date. Continue until no parents
RAW_FILE=$(cat old_par_md.json | jq .file_name | tr -d "\"")
while [[ $(samweb -e ${SAM_EXPERIMENT} get-metadata --json ${RAW_FILE} | jq .parents[0].file_name | tr -d "\"") != "null" ]] ; do
    RAW_FILE=$(samweb -e ${SAM_EXPERIMENT} get-metadata --json ${RAW_FILE} | jq .parents[0].file_name | tr -d "\"") ; done
FDATE=$(samweb -e ${SAM_EXPERIMENT} get-metadata --json ${RAW_FILE} | jq .create_date | tr -d "\"" | awk -F "T" '{print $1}' | tr -d "-")
echo "Getting physics date from raw event file ${RAW_FILE} made on ${FDATE}"

export MT_DTAG=${MT_PRODUCTIONNAME}_${MT_SBND_STREAM_NAME}_${SBNDCODE_VERSION}_${MT_PROJECTSTAGE}
export MT_DTAG_CONCAT=${MT_PRODUCTIONNAME}_${SBNDCODE_VERSION}_${MT_PROJECTSTAGE}
export OTHER_MT_DTAG=${MT_PRODUCTIONNAME}_${MT_SBND_STREAM_NAME}_${SBNDCODE_VERSION}_hist${MT_PROJECTSTAGE}
export OTHER_MT_DTAG_CONCAT=${MT_PRODUCTIONNAME}_${SBNDCODE_VERSION}_hist${MT_PROJECTSTAGE}
export LARCV_MT_DTAG=${MT_PRODUCTIONNAME}_${MT_SBND_STREAM_NAME}_${SBNDCODE_VERSION}_larcv${MT_PROJECTSTAGE}
export LARCV_MT_DTAG_CONCAT=${MT_PRODUCTIONNAME}_${SBNDCODE_VERSION}_larcv${MT_PROJECTSTAGE}
export FLAT_MT_DTAG=${MT_PRODUCTIONNAME}_${MT_SBND_STREAM_NAME}_${SBNDCODE_VERSION}_flat${MT_PROJECTSTAGE}
export FLAT_MT_DTAG_CONCAT=${MT_PRODUCTIONNAME}_${SBNDCODE_VERSION}_flat${MT_PROJECTSTAGE}

# Hmm - should we add a poms_task field?
echo -e " \"Dataset.Tag\": \"${MT_DTAG}\"," >> ${MD_FILE}
#echo -e " \"poms_task\": \"poms_depends_${POMS_TASK_ID}_1\"," >> ${MD_FILE}
echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${MD_FILE}
echo -e " \"file_type\": \"data\"," >> ${MD_FILE}
echo -e " \"group\": \"sbnd\"," >> ${MD_FILE}
echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${MD_FILE}
echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${MD_FILE}
echo -e " \"art.file_format_version\": 15," >> ${MD_FILE}
echo -e " \"art.process_name\": \"${processName}\"," >> ${MD_FILE}
echo -e " \"art.run_type\": \"physics\"," >> ${MD_FILE}
echo -e " \"fcl.name\": \"${MT_ENV_FCLNAME}\"," >> ${MD_FILE}
echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${MD_FILE}
echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${MD_FILE}
echo -e " \"configuration.name\": \"${MT_CONFIGURATION}\"," >> ${MD_FILE}
echo -e " \"sbn_dm.beam_type\": \"${MT_BEAMTYPE}\"," >> ${MD_FILE}
echo -e " \"sbn_dm.detector\": \"${MT_DETECTOR}\"," >> ${MD_FILE}
echo -e " \"sbn_dm.event_count\": ${MT_EVENTCOUNT}," >> ${MD_FILE}
echo -e " \"sbnd.random\": \"${MT_RANDOM}\"," >> ${MD_FILE}
echo -e " \"sbnd.random_run\": \"${MT_RANDOMRUN}\"," >> ${MD_FILE}
echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\"," >> ${MD_FILE}
echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${MD_FILE}
echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${MD_FILE}
echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\"," >> ${MD_FILE}
echo -e " \"runs\": [" >> ${MD_FILE}
echo -e " ${runString}" >> ${MD_FILE}
echo -e " ]," >> ${MD_FILE}
echo -e " \"parents\": [" >> ${MD_FILE}
echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }" >> ${MD_FILE}
echo -e "  ]" >> ${MD_FILE}
echo -e " }" >> ${MD_FILE}

>&2 echo -e "\n\nHere is the json...\n\n"
>&2 cat ${MD_FILE}

# If this is reco1, save the larcv json
echo -e "{" >> ${LARCV_MD_FILE}
echo -e " \"file_name\": \"$(basename ${newLarcvFile})\"," >> ${LARCV_MD_FILE}
echo -e " \"file_size\": $(stat -c %s ${newLarcvFile} | awk -F " " '{print $1}')," >> ${LARCV_MD_FILE}
echo -e " \"data_tier\": \"${dataTier}\"," >> ${LARCV_MD_FILE}
echo -e " \"data_stream\": \"${MT_SBND_STREAM_NAME}\"," >> ${LARCV_MD_FILE}

echo -e " \"file_format\": \"artroot\"," >> ${LARCV_MD_FILE}
echo -e " \"checksum\": [" >> ${LARCV_MD_FILE}
echo -e "$(samweb file-checksum --type=enstore,adler32,md5 ${newLarcvFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${LARCV_MD_FILE}
echo -e " ]," >> ${LARCV_MD_FILE}

echo -e " \"Dataset.Tag\": \"${LARCV_MT_DTAG}\"," >> ${LARCV_MD_FILE}
echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${LARCV_MD_FILE}
echo -e " \"file_type\": \"data\"," >> ${LARCV_MD_FILE}
echo -e " \"group\": \"sbnd\"," >> ${LARCV_MD_FILE}
echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${LARCV_MD_FILE}
echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${LARCV_MD_FILE}
echo -e " \"art.file_format_version\": 15," >> ${LARCV_MD_FILE}
echo -e " \"art.process_name\": \"${processName}\"," >> ${LARCV_MD_FILE}
echo -e " \"art.run_type\": \"physics\"," >> ${LARCV_MD_FILE}
echo -e " \"fcl.name\": \"${MT_ENV_FCLNAME}\"," >> ${LARCV_MD_FILE}
echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${LARCV_MD_FILE}
echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${LARCV_MD_FILE}
echo -e " \"configuration.name\": \"${MT_CONFIGURATION}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbn_dm.beam_type\": \"${MT_BEAMTYPE}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbn_dm.detector\": \"${MT_DETECTOR}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbn_dm.event_count\": ${MT_EVENTCOUNT}," >> ${LARCV_MD_FILE}
echo -e " \"sbnd.random\": \"${MT_RANDOM}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbnd.random_run\": \"${MT_RANDOMRUN}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${LARCV_MD_FILE}
echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\"," >> ${LARCV_MD_FILE}
echo -e " \"runs\": [" >> ${LARCV_MD_FILE}
echo -e " ${runString}" >> ${LARCV_MD_FILE}
echo -e " ]," >> ${LARCV_MD_FILE}
echo -e " \"parents\": [" >> ${LARCV_MD_FILE}
echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }" >> ${LARCV_MD_FILE}
echo -e "  ]" >> ${LARCV_MD_FILE}
echo -e " }" >> ${LARCV_MD_FILE}

>&2 echo -e "\n\nHere is the larcv json...\n\n"
>&2 cat ${LARCV_MD_FILE}

# If want to save calib tuples, construct the json
if [ ${otherFile} != "" ] && [ $2=="true" ] ; then

    echo -e "{" >> ${OTHER_MD_FILE}

    echo -e " \"file_name\": \"$(basename ${newOtherFile})\"," >> ${OTHER_MD_FILE}
    echo -e " \"file_size\": $(stat -c %s ${newOtherFile} | awk -F " " '{print $1}')," >> ${OTHER_MD_FILE}
    echo -e " \"data_tier\": \"${dataTier}\"," >> ${OTHER_MD_FILE}

    # I just have to lookup some stuff.. ugh
    echo -e " \"data_stream\": \"${MT_SBND_STREAM_NAME}\"," >> ${OTHER_MD_FILE}

    # file format
    echo -e " \"file_format\": \"root\"," >> ${OTHER_MD_FILE}

    # Checksum
    echo -e " \"checksum\": [" >> ${OTHER_MD_FILE}
    echo -e "$(samweb file-checksum --type=enstore,adler32,md5 ${newOtherFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${OTHER_MD_FILE}
    echo -e " ]," >> ${OTHER_MD_FILE}
    
    # Hmm - should we add a poms_task field?
    echo -e " \"Dataset.Tag\": \"${OTHER_MT_DTAG}\"," >> ${OTHER_MD_FILE}
    #echo -e " \"poms_task\": \"poms_depends_${POMS_TASK_ID}_1\"," >> ${OTHER_MD_FILE}
    echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${OTHER_MD_FILE}
    echo -e " \"file_type\": \"data\"," >> ${OTHER_MD_FILE}
    echo -e " \"group\": \"sbnd\"," >> ${OTHER_MD_FILE}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${OTHER_MD_FILE}
    echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${OTHER_MD_FILE}
    echo -e " \"art.file_format_version\": 15," >> ${OTHER_MD_FILE}
    echo -e " \"art.process_name\": \"${processName}\"," >> ${OTHER_MD_FILE}
    echo -e " \"art.run_type\": \"physics\"," >> ${OTHER_MD_FILE}
    echo -e " \"fcl.name\": \"${MT_ENV_FCLNAME}\"," >> ${OTHER_MD_FILE}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${OTHER_MD_FILE}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${OTHER_MD_FILE}
    echo -e " \"configuration.name\": \"${MT_CONFIGURATION}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbn_dm.beam_type\": \"${MT_BEAMTYPE}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbn_dm.detector\": \"${MT_DETECTOR}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbn_dm.event_count\": ${MT_EVENTCOUNT}," >> ${OTHER_MD_FILE}
    echo -e " \"sbnd.random\": \"${MT_RANDOM}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbnd.random_run\": \"${MT_RANDOMRUN}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${OTHER_MD_FILE}
    echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\"," >> ${OTHER_MD_FILE}
    echo -e " \"runs\": [" >> ${OTHER_MD_FILE}
    echo -e " ${runString}" >> ${OTHER_MD_FILE}
    echo -e " ]," >> ${OTHER_MD_FILE}
    echo -e " \"parents\": [" >> ${OTHER_MD_FILE}
    echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }" >> ${OTHER_MD_FILE}
    echo -e "  ]" >> ${OTHER_MD_FILE}
    echo -e " }" >> ${OTHER_MD_FILE}

    >&2 echo -e "\n\nHere is the calib json...\n\n"
    >&2 cat ${OTHER_MD_FILE}
fi

# If this is caf stage, construct the flat file's json
if [[ ${flatFile} != "" ]] ; then
    echo -e "{" >> ${FLAT_MD_FILE}

    echo -e " \"file_name\": \"$(basename ${newFlatFile})\"," >> ${FLAT_MD_FILE}
    echo -e " \"file_size\": $(stat -c %s ${newFlatFile} | awk -F " " '{print $1}')," >> ${FLAT_MD_FILE}
    echo -e " \"data_tier\": \"flat_${dataTier}\"," >> ${FLAT_MD_FILE}

    # I just have to lookup some stuff.. ugh
    echo -e " \"data_stream\": \"${MT_SBND_STREAM_NAME}\"," >> ${FLAT_MD_FILE}

    # file format
    echo -e " \"file_format\": \"root\"," >> ${FLAT_MD_FILE}

    # Checksum
    echo -e " \"checksum\": [" >> ${FLAT_MD_FILE}
    echo -e "$(samweb file-checksum --type=enstore,adler32,md5 ${newFlatFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${FLAT_MD_FILE}
    echo -e " ]," >> ${FLAT_MD_FILE}

    echo -e " \"Dataset.Tag\": \"${FLAT_MT_DTAG}\"," >> ${FLAT_MD_FILE}
    #echo -e " \"poms_task\": \"poms_depends_${POMS_TASK_ID}_1\"," >> ${FLAT_MD_FILE}
    echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${FLAT_MD_FILE}
    echo -e " \"file_type\": \"data\"," >> ${FLAT_MD_FILE}
    echo -e " \"group\": \"sbnd\"," >> ${FLAT_MD_FILE}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${FLAT_MD_FILE}
    echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${FLAT_MD_FILE}
    echo -e " \"art.file_format_version\": 15," >> ${FLAT_MD_FILE}
    echo -e " \"art.process_name\": \"${processName}\"," >> ${FLAT_MD_FILE}
    echo -e " \"art.run_type\": \"physics\"," >> ${FLAT_MD_FILE}
    echo -e " \"fcl.name\": \"${MT_ENV_FCLNAME}\"," >> ${FLAT_MD_FILE}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${FLAT_MD_FILE}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${FLAT_MD_FILE}
    echo -e " \"configuration.name\": \"${MT_CONFIGURATION}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbn_dm.beam_type\": \"${MT_BEAMTYPE}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbn_dm.detector\": \"${MT_DETECTOR}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbn_dm.event_count\": ${MT_EVENTCOUNT}," >> ${FLAT_MD_FILE}
    echo -e " \"sbnd.random\": \"${MT_RANDOM}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbnd.random_run\": \"${MT_RANDOMRUN}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${FLAT_MD_FILE}
    echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\"," >> ${FLAT_MD_FILE}
    echo -e " \"runs\": [" >> ${FLAT_MD_FILE}
    echo -e " ${runString}" >> ${FLAT_MD_FILE}
    echo -e " ]," >> ${FLAT_MD_FILE}
    echo -e " \"parents\": [" >> ${FLAT_MD_FILE}
    echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }" >> ${FLAT_MD_FILE}
    echo -e "  ]" >> ${FLAT_MD_FILE}
    echo -e " }" >> ${FLAT_MD_FILE}

>&2 echo -e "\n\nHere is the flat file's json...\n\n"
>&2 cat ${FLAT_MD_FILE}
fi

echo "Here are the contents of my workdir..."
ls -ltrh

# Retire any declared files before moving on.
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newCandFile))
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newCandFile) ; fi
if [[ ${otherFile} != "" ]] ; then
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newOtherFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newOtherFile) ; fi
fi
if [[ ${larcvFile} != "" ]] ; then
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newLarcvFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newLarcvFile) ; fi
fi
if [[ ${flatFile} != "" ]] ; then
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newFlatFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newFlatFile) ; fi
fi

# now validate the metadata
echo "Validating metadata...."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${MD_FILE}
if [ ${otherFile} != "" ] && [ $2=="true" ] ; then samweb -e ${SAM_EXPERIMENT} validate-metadata ${OTHER_MD_FILE} ; fi
if [[ ${larcvFile} != "" ]] ; then samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD_FILE} ; fi
if [[ ${flatFile} != "" ]] ; then samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD_FILE} ; fi
>&2 echo -e "\n\nAbout to declare metadata...\n\n"

# and finally, declare these!

FULL_IFDH_OUTDIR=${IFDH_OUTPUT_DIR}/${MT_SBND_STREAM_NAME}/${used_hash_prebit}/
OTHER_FULL_IFDH_OUTDIR=
LARCV_FULL_IFDH_OUTDIR=${IFDH_LARCV_OUTPUT_DIR}/${MT_SBND_STREAM_NAME}/${used_hash_prebit}/
FLAT_FULL_IFDH_OUTDIR=${IFDH_FLAT_OUTPUT_DIR}/${MT_SBND_STREAM_NAME}/${used_hash_prebit}/
if [[ $1 == "decode" ]] ; then
    FULL_IFDH_OUTDIR=${IFDH_OUTPUT_DIR}/filtered/${MT_SBND_STREAM_NAME}/${used_hash_prebit}/
    OTHER_FULL_IFDH_OUTDIR=${IFDH_OUTPUT_DIR}/choppy/${MT_SBND_STREAM_NAME}/${used_hash_prebit}/
elif [[ $1 == "reco1" ]] ; then
    OTHER_FULL_IFDH_OUTDIR=${IFDH_OUTPUT_DIR}/nhit_fail/${MT_SBND_STREAM_NAME}/${used_hash_prebit}/
elif [[ $1 == "reco2" ]] ; then
    OTHER_FULL_IFDH_OUTDIR=${FULL_IFDH_OUTDIR}
fi

>&2 echo -e "\n\nDone with ifdh definitions...\n\n"

if samweb -e ${SAM_EXPERIMENT} validate-metadata ${MD_FILE} ; then
    # copy this back
    ifdh cp -D ${newCandFile} ${FULL_IFDH_OUTDIR} && echo "COPYING FILE TO ${FULL_IFDH_OUTDIR}..."
    echo "DECLARING OUTPUT FILE ${newCandFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${MD_FILE}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newCandFile}) ${FULL_IFDH_OUTDIR} && echo "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newCandFile}) ${FULL_IFDH_OUTDIR}"
    >&2 echo -e "\n\nsamweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newCandFile}) ${FULL_IFDH_OUTDIR}\n\n"

    # also create the definition...
    #echo "Creating definition ${MT_DTAG_CONCAT}..."
    echo "Creating definition ${MT_DTAG}..."
    #>&2 "Creating definition ${MT_DTAG_CONCAT}..."
    >&2 "Creating definition ${MT_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${MT_DTAG} "Dataset.Tag ${MT_DTAG}"

    # It would also be useful to have a definition not broken up by stream
    #samweb -e ${SAM_EXPERIMENT} create-definition ${MT_DTAG_CONCAT} "Dataset.Tag like ${MT_PRODUCTIONNAME}%_${MT_PROJECTSTAGE} and sbnd_project.version ${SBNDCODE_VERSION}"

    if [[ ${otherFile} != "" ]] ; then
	ifdh cp -D ${newOtherFile} ${OTHER_FULL_IFDH_OUTDIR} && echo "COPYING OTHER FILE TO ${OTHER_FULL_IFDH_OUTDIR}..."
	echo "OTHER OUTPUT FILE IS ${newOtherFile}"
    fi
   
fi

if [ ${otherFile} != "" ] && [ $2 == "true" ] ; then
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${OTHER_MD_FILE} ; then
	# we always copy this back, see call in above block
	#ifdh cp -D ${newOtherFile} ${OTHER_FULL_IFDH_OUTDIR} && echo "COPYING FILE TO ${OTHER_FULL_IFDH_OUTDIR}..."
	echo "DECLARING OUTPUT FILE ${newOtherFile}"
	samweb -e ${SAM_EXPERIMENT} declare-file ${OTHER_MD_FILE}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newOtherFile}) ${OTHER_FULL_IFDH_OUTDIR} && echo "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newOtherFile}) ${OTHER_FULL_IFDH_OUTDIR}"

	# also create the definition...
	#echo "Creating definition ${OTHER_MT_DTAG_CONCAT}..."
	echo "Creating definition ${OTHER_MT_DTAG}..."
	#>&2 "Creating definition ${OTHER_MT_DTAG_CONCAT}..."
	>&2 "Creating definition ${OTHER_MT_DTAG}..."
	samweb -e ${SAM_EXPERIMENT} create-definition ${OTHER_MT_DTAG} "Dataset.Tag ${OTHER_MT_DTAG}"
	#samweb -e ${SAM_EXPERIMENT} create-definition ${OTHER_MT_DTAG_CONCAT} "Dataset.Tag like ${MT_PRODUCTIONNAME}%_hist${MT_PROJECTSTAGE} and sbnd_project.version ${SBNDCODE_VERSION}"
    fi
fi

if [[ ${larcvFile} != "" ]] ; then
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD_FILE} ; then
	# copy this back
	ifdh cp -D ${newLarcvFile} ${LARCV_FULL_IFDH_OUTDIR} && echo "COPYING FILE TO ${LARCV_FULL_IFDH_OUTDIR}..."
	echo "DECLARING OUTPUT FILE ${newLarcvFile}"
	samweb -e ${SAM_EXPERIMENT} declare-file ${LARCV_MD_FILE}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newLarcvFile}) ${LARCV_FULL_IFDH_OUTDIR} && echo "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newLarcvFile}) ${LARCV_FULL_IFDH_OUTDIR}"

	# also create the definition...
	#echo "Creating definition ${LARCV_MT_DTAG_CONCAT}..."
	echo "Creating definition ${LARCV_MT_DTAG}..."
	#>&2 "Creating definition ${LARCV_MT_DTAG_CONCAT}..."
	>&2 "Creating definition ${LARCV_MT_DTAG}..."
	samweb -e ${SAM_EXPERIMENT} create-definition ${LARCV_MT_DTAG} "Dataset.Tag ${LARCV_MT_DTAG}"
	#samweb -e ${SAM_EXPERIMENT} create-definition ${LARCV_MT_DTAG_CONCAT} "Dataset.Tag like ${MT_PRODUCTIONNAME}%_larcv${MT_PROJECTSTAGE} and sbnd_project.version ${SBNDCODE_VERSION}"
    fi
fi

if [[ ${flatFile} != "" ]] ; then
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD_FILE} ; then
	# copy this back
	ifdh cp -D ${newFlatFile} ${FLAT_FULL_IFDH_OUTDIR} && echo "COPYING FILE TO ${FLAT_FULL_IFDH_OUTDIR}..."
	echo "DECLARING OUTPUT FILE ${newFlatFile}"
	samweb -e ${SAM_EXPERIMENT} declare-file ${FLAT_MD_FILE}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newFlatFile}) ${FLAT_FULL_IFDH_OUTDIR} && echo "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newFlatFile}) ${FLAT_FULL_IFDH_OUTDIR}"

	# also create the definition...
	#echo "Creating definition ${FLAT_MT_DTAG_CONCAT}..."
	echo "Creating definition ${FLAT_MT_DTAG}..."
	#>&2 "Creating definition ${FLAT_MT_DTAG_CONCAT}..."
	>&2 "Creating definition ${FLAT_MT_DTAG}..."
	samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_MT_DTAG} "Dataset.Tag ${FLAT_MT_DTAG}"
	#samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_MT_DTAG_CONCAT} "Dataset.Tag like ${MT_PRODUCTIONNAME}%_flat${MT_PROJECTSTAGE} and sbnd_project.version ${SBNDCODE_VERSION}"
    fi
fi

>&2 echo -e "\n\nDone\n\n"

echo "metadata_postscripts.sh done"
