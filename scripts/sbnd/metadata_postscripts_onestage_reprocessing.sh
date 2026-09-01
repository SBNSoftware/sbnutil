#!/bin/bash

# Copied from Vito's area, /exp/icarus/app/users/vito/sam/declare_file.sh
# Adapted for use on postscript stage for UNIFIED/ONESTAGE pipelines
# This version handles naming scheme: data_filtered_decoded_reco1.root, etc.
# Essentially, build the metadata for the file manually while ignoring artroot.
# Most of this stuff is already exported as env variables, from the prescripts stage.

>&2 echo -e "\n\nSTARTING $0...\n\n"

# Retire any declared files before moving on.
histFile='' # Calib ntuples
cafFile=''  # CAF trees
flatFile='' # FlatCAF trees

>&2 echo -e "\n\nUsing fcl list $1...\n\n"

# Find the files.
histFile=$(find ./ -iname 'hist*.root' | grep 'reco2' | head -n 1)
cafFile=$(find ./ -iname '*.caf.root' | grep -v 'flat')
flatFile=$(find ./ -iname '*.caf.root' | grep 'flat')

>&2 echo -e "\n\nHere is the contents of the dir BEFORE renaming...\n\n"
>&2 ls -ltrh

>&2 echo -e "\n\nhistFile: ${histFile}"
>&2 echo -e "\n\ncafFile: ${cafFile}"
>&2 echo -e "\n\nflatFile: ${flatFile}"

# We will set the reco1 artroot file as the parent for both stages.
samweb -e ${SAM_EXPERIMENT} get-metadata --json $(basename ${PARENT_FILE_SAM}) > old_par_md.json
par_name=$(cat old_par_md.json | jq -r .'file_name')
par_name=${par_name/.root/}

# Get the filenames and rename them to something sensible
mv ${histFile} hist_reco2_${par_name}.root
histFile=hist_reco2_${par_name}.root
mv ${cafFile} reco2_${par_name}.caf.root
cafFile=reco2_${par_name}.caf.root
mv ${flatFile} reco2_${par_name}.flat.caf.root
flatFile=reco2_${par_name}.flat.caf.root

# Get the runs 
subRun=$(grep messages.log -e 'subRun' | head -n 1 | awk -F "subRun: " '{print $2}' | awk -F " " '{print $1}')
runString=$(cat old_par_md.json | grep -A 5 -e "\"runs\":" | grep -v "\"runs\"")

# We'll pass the fcl-file-list here, under fcl.name
fcl_list=$1

# Rename files uniquely, based on their own md5sum.
# This ensures that we have unique file names
md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
md5_caf=$(md5sum ${cafFile} | awk -F " " '{print $1}')
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

# To make things a bit more unique, I will pipe this to a file, append some random numbers, and md5sum
echo $md5_hist > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
echo $md5_caf > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_caf=$(md5sum ${cafFile} | awk -F " " '{print $1}')
echo $md5_flat > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

# In case there is a hash in the filenames, remove it
old_hist_hash=$(echo ${histFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_histFile=${histFile%-${old_hist_hash}*}
old_caf_hash=$(echo ${cafFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_cafFile=${cafFile%-${old_caf_hash}*}
old_flat_hash=$(echo ${flatFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_flatFile=${flatFile%-${old_flat_hash}*}

used_hist_hash=${md5_hist:0:8}-${md5_hist:8:4}-${md5_hist:12:4}-${md5_hist:16:4}-${md5_hist:20:12}
used_caf_hash=${md5_caf:0:8}-${md5_caf:8:4}-${md5_caf:12:4}-${md5_caf:16:4}-${md5_caf:20:12}
used_flat_hash=${md5_flat:0:8}-${md5_flat:8:4}-${md5_flat:12:4}-${md5_flat:16:4}-${md5_flat:20:12}

used_hist_prebit=${used_hist_hash:0:2}
used_caf_prebit=${used_caf_hash:0:2}
used_flat_prebit=${used_flat_hash:0:2}

# Definitive names for the outputs
newHistFile=${excised_histFile%.root}-${used_hist_hash}.root
newCafFile=${excised_cafFile%.root}-${used_caf_hash}.caf.root
newFlatFile=${excised_flatFile%.root}-${used_flat_hash}.flat.caf.root

mv ${histFile} ${newHistFile}
mv ${cafFile} ${newCafFile}
mv ${flatFile} ${newFlatFile}

>&2 echo -e "\n\nDefinitive hist name: ${newHistFile}"
>&2 echo -e "\n\nDefinitive caf name: ${newCafFile}"
>&2 echo -e "\n\nDefinitive flat name: ${newFlatFile}"

# Construct json files.
HIST_MD=md_hist.json
CAF_MD=md_caf.json
FLAT_MD=md_flat.json

touch ${HIST_MD}; touch ${CAF_MD}; touch ${FLAT_MD}			 

for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e "{" >> ${mdFile}
done

# file names
echo -e " \"file_name\": \"$(basename ${newHistFile})\"," >> ${HIST_MD}
echo -e " \"file_name\": \"$(basename ${newCafFile})\"," >> ${CAF_MD}
echo -e " \"file_name\": \"$(basename ${newFlatFile})\"," >> ${FLAT_MD}

# file sizes
echo -e " \"file_size\": $(stat -c %s ${newHistFile} | awk -F " " '{print $1}')," >> ${HIST_MD}
echo -e " \"file_size\": $(stat -c %s ${newCafFile} | awk -F " " '{print $1}')," >> ${CAF_MD}
echo -e " \"file_size\": $(stat -c %s ${newFlatFile} | awk -F " " '{print $1}')," >> ${FLAT_MD}

# Specific data tiers for outputs
echo -e " \"data_tier\": \"root-tuple\"," >> ${HIST_MD}
echo -e " \"data_tier\": \"caf\"," >> ${CAF_MD}
echo -e " \"data_tier\": \"flat_caf\"," >> ${FLAT_MD}

# data stream is common
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e  " \"data_stream\": \"${MT_SBND_STREAM_NAME}\"," >> ${mdFile}
done

# file formats
echo -e " \"file_format\": \"root\"," >> ${HIST_MD}
echo -e " \"file_format\": \"caf\"," >> ${CAF_MD}
echo -e " \"file_format\": \"flat_caf\"," >> ${FLAT_MD}

# Checksums
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"checksum\": [" >> ${mdFile}
done
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newHistFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${HIST_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newCafFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${CAF_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newFlatFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${FLAT_MD}
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " ]," >> ${mdFile}
done

# Dataset tags
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_PRODUCTIONNAME}_${SBNDCODE_VERSION}
export HIST_DTAG=${DTAG_PREAMBLE}_histreco2_sbnd
export CAF_DTAG=${DTAG_PREAMBLE}_caf_sbnd
export FLAT_DTAG=${DTAG_PREAMBLE}_flatcaf_sbnd

echo -e " \"Dataset.Tag\": \"${HIST_DTAG}\"," >> ${HIST_MD}
echo -e " \"Dataset.Tag\": \"${CAF_DTAG}\"," >> ${CAF_MD}
echo -e " \"Dataset.Tag\": \"${FLAT_DTAG}\"," >> ${FLAT_MD}

# Common tags
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${mdFile}
    echo -e " \"file_type\": \"data\"," >> ${mdFile}
    echo -e " \"group\": \"sbnd\"," >> ${mdFile}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${mdFile}
    echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${mdFile}
    echo -e " \"art.file_format_version\": 15," >> ${mdFile}
    echo -e " \"art.run_type\": \"physics\"," >> ${mdFile}
done
# Insert process names
echo -e " \"art.process_name\": \"Reco2\"," >> ${HIST_MD}
echo -e " \"art.process_name\": \"caf\"," >> ${CAF_MD}
echo -e " \"art.process_name\": \"caf\"," >> ${FLAT_MD}
# Back to common tage
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"fcl.name\": \"${fcl_list}\"," >> ${mdFile}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${mdFile}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${mdFile}
    echo -e " \"configuration.name\": \"${MT_CONFIGURATION}\"," >> ${mdFile}
    echo -e " \"sbn_dm.beam_type\": \"${MT_BEAMTYPE}\"," >> ${mdFile}
    echo -e " \"sbn_dm.detector\": \"${MT_DETECTOR}\"," >> ${mdFile}
    echo -e " \"sbn_dm.event_count\": ${MT_EVENTCOUNT}," >> ${mdFile}
    echo -e " \"sbnd.random\": \"${MT_RANDOM}\"," >> ${mdFile}
    if [[ ! -z ${MT_EVENTSTRING} ]] ; then
	echo -e " \"sbnd.random_run\": \"${MT_RANDOMRUN}\"," >> ${mdFile}
	echo -e " \"sbnd.event_number_list\": \"${MT_EVENTSTRING}\"," >> ${mdFile}
    else
	echo -e " \"sbnd.random_run\": \"${MT_RANDOMRUN}\"," >> ${mdFile}
    fi
    echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\"," >> ${mdFile}
    echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${mdFile}
    echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${mdFile}
    echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\"," >> ${mdFile}
    echo -e " \"runs\": [" >> ${mdFile}
    echo -e " ${runString}" >> ${mdFile}
    echo -e " ]," >> ${mdFile}
    echo -e " \"parents\": [" >> ${mdFile}
    echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }" >> ${mdFile}
    echo -e "  ]" >> ${mdFile}
    echo -e " }" >> ${mdFile}
done


>&2 echo -e "\n\nHere is the hist json...\n\n"
>&2 cat ${HIST_MD}

>&2 echo -e "\n\nHere is the caf json...\n\n"
>&2 cat ${CAF_MD}

>&2 echo -e "\n\nHere is the flat json...\n\n"
>&2 cat ${FLAT_MD}

echo "Here are the contents of my workdir..."
ls -ltrh

# Retire any declared files before moving on.
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newHistFile))
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newHistFile) ; fi
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newCafFile))
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newCafFile) ; fi
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newFlatFile))
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newFlatFile) ; fi

# now validate the metadata
echo "Validating metadata...."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD}

# and finally, declare these!
# Set output directories based on stage
FULL_HIST_OUTDIR=${IFDH_OUTPUT_DIR}/calib/${MT_SBND_STREAM_NAME}/${used_hist_prebit}/
FULL_CAF_OUTDIR=${IFDH_OUTPUT_DIR}/caf/${MT_SBND_STREAM_NAME}/${used_caf_prebit}/
FULL_FLAT_OUTDIR=${IFDH_OUTPUT_DIR}/flatcaf/${MT_SBND_STREAM_NAME}/${used_flat_prebit}/

if samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD} ; then
    # copy this back
    ifdh cp -D ${newHistFile} ${FULL_HIST_OUTDIR} && echo "COPYING HIST FILE $(basename ${newHistFile}) TO ${FULL_HIST_OUTDIR}..."
    echo "DECLARING HISTOGRAM FILE ${newHistFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${HIST_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newHistFile}) ${FULL_HIST_OUTDIR}
    >&2 echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newHistFile}) ${FULL_HIST_OUTDIR}"

    >&2 echo -e "Creating definition ${HIST_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${HIST_DTAG} "Dataset.Tag ${HIST_DTAG}"
fi
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD} ; then
    # copy this back
    ifdh cp -D ${newCafFile} ${FULL_CAF_OUTDIR} && echo "COPYING CAF FILE $(basename ${newCafFile}) TO ${FULL_CAF_OUTDIR}..."
    echo "DECLARING CAF FILE ${newCafFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${CAF_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newCafFile}) ${FULL_CAF_OUTDIR}
    >&2 echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newCafFile}) ${FULL_CAF_OUTDIR}"

    >&2 echo -e "Creating definition ${CAF_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${CAF_DTAG} "Dataset.Tag ${CAF_DTAG}"
fi
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD} ; then
    # copy this back
    ifdh cp -D ${newFlatFile} ${FULL_FLAT_OUTDIR} && echo "COPYING FLATCAF FILE $(basename ${newFlatFile}) TO ${FULL_FLAT_OUTDIR}..."
    echo "DECLARING FLAT FILE ${newFlatFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${FLAT_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newFlatFile}) ${FULL_FLAT_OUTDIR}
    >&2 echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newFlatFile}) ${FULL_FLAT_OUTDIR}"

    >&2 echo -e "Creating definition ${FLAT_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_DTAG} "Dataset.Tag ${FLAT_DTAG}"
fi

>&2 echo -e "\n\nDone\n\n"

echo "metadata_postscripts.sh done"
