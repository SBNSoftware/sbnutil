#!/bin/bash

# Adapted from ICARUS metadata_postscripts_MC_onestage.sh
# Essentially, build the metadata for the file manually while ignoring artroot.
# Most of this stuff is already exported as env variables, from the prescripts stage.
# Notice that this is the 2-stage overlay workflow gen-->stage0 + stage1 -> caf

>&2 echo -e "\n\nSTARTING $0...\n\n"

parentFile=$(basename ${PARENT_FILE_SAM}) # This is either a raw file or a stage0 file
stage0File=''  # Artroot stage0 files
larcvFile=''   # LarCV files
histFile=''    # Calib ntuples
cafFile=''     # CAF trees
flatFile=''    # FlatCAF trees

# We'll pass the fcl-file-list here, under fcl.name
fcl_list=$1

>&2 echo -e "\n\nUsing fcl_list $1...\n\n"

stage0File=$(find ./ -iname '*.root' | grep 'stage0' | grep -v 'hist' | grep -v 'stage1' | grep -v 'caf')
larcvFile=$(find ./ -iname 'larcv*.root' | grep -v 'stage1')
histFile=$(find ./ -iname 'hist*.root' | grep 'stage1' | head -n 1)
cafFile=$(find ./ -iname '*stage1.caf.root')
flatFile=$(find ./ -iname '*stage1.flat.caf.root')

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

if [[ ! -z ${stage0File} ]] ; then
    echo -e "stage0File: ${stage0File}"
else
    echo -e "larcvFile: ${larcvFile}"
    echo -e "histFile: ${histFile}"
    echo -e "cafFile: ${cafFile}"
    echo -e "flatFile: ${flatFile}"
fi

>&2 echo -e "\n\nFrom parent file ${parentFile} I get metadata..."
samweb -e ${SAM_EXPERIMENT} get-metadata --json ${parentFile} > old_par_md.json
par_name=${parentFile/.root/}

# Get the first and last event as well as the run and subrun
# There could be a more elegant way to do this. Or, we could invoke the wrath of Bash.
# Scour the message logs, find any lines with timesamps and run/subrun/event, remove away any code,
# these are in tokens 'run: X subRun: Y event: Z', extract uniques, and sort for first/last based on Z
#source_log=messages.log
#first_token=$(cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5n | head -n 1)
#last_token=$(cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5nr | head -n 1)
#run_no=$(echo ${first_token} | awk -F " " '{print $1}')
#subrun_no=$(echo ${first_token} | awk -F " " '{print $3}')
#first_event=$(echo ${first_token} | awk -F " " '{print $5}')
#last_event=$(echo ${last_token} | awk -F " " '{print $5}')

# Get event_count from specific JSON file
#json_file="hist_gen_g4_detsim_stage0_stage1_caf.root.json"
#event_count=$(grep '"event_count":' "$json_file" | head -1 | sed 's/.*"event_count": *//' | sed 's/[^0-9].*//')
event_count=${MT_EVENTCOUNT}

#########################

# Rename files uniquely, based on their own md5sum.
# This ensures that we have unique file names
# In case there is a hash in the filenames, remove it
declare -a MDFILES=()
if [[ ! -z ${stage0File} ]] ; then
    md5_stage0=$(md5sum ${stage0File} | awk -F " " '{print $1}')
    
    echo $md5_stage0 > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
    md5_stage0=$(md5sum ${stage0File} | awk -F " " '{print $1}')

    old_stage0_hash=$(echo ${stage0File} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
    excised_stage0File=${stage0File%-${old_stage0_hash}*}

    used_stage0_hash=${md5_stage0:0:8}-${md5_stage0:8:4}-${md5_stage0:12:4}-${md5_stage0:16:4}-${md5_stage0:20:12}

    used_stage0_prebit=${used_stage0_hash:0:2}

    newStage0File=${excised_stage0File%.root}-${used_stage0_hash}.root

    mv ${stage0File} ${newStage0File}

    echo -e "Definitive stage0 name: ${newStage0File}"

    STAGE0_MD=md_stage0.json
    touch ${STAGE0_MD}
    MDFILES+=(${STAGE0_MD})
else
    md5_larcv=$(md5sum ${larcvFile} | awk -F " " '{print $1}')
    md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
    md5_caf=$(md5sum ${cafFile} | awk -F " " '{print $1}')
    md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

    echo $md5_larcv > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
    md5_larcv=$(md5sum ${larcvFile} | awk -F " " '{print $1}')
    echo $md5_hist > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
    md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
    echo $md5_caf > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
    md5_caf=$(md5sum ${cafFile} | awk -F " " '{print $1}')
    echo $md5_flat > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
    md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

    old_larcv_hash=$(echo ${larcvFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
    excised_larcvFile=${larcvFile%-${old_larcv_hash}*}
    old_hist_hash=$(echo ${histFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
    excised_histFile=${histFile%-${old_hist_hash}*}
    old_caf_hash=$(echo ${cafFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
    excised_cafFile=${cafFile%-${old_caf_hash}*}
    old_flat_hash=$(echo ${flatFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
    excised_flatFile=${flatFile%-${old_flat_hash}*}

    used_larcv_hash=${md5_larcv:0:8}-${md5_larcv:8:4}-${md5_larcv:12:4}-${md5_larcv:16:4}-${md5_larcv:20:12}
    used_hist_hash=${md5_hist:0:8}-${md5_hist:8:4}-${md5_hist:12:4}-${md5_hist:16:4}-${md5_hist:20:12}
    used_caf_hash=${md5_caf:0:8}-${md5_caf:8:4}-${md5_caf:12:4}-${md5_caf:16:4}-${md5_caf:20:12}
    used_flat_hash=${md5_flat:0:8}-${md5_flat:8:4}-${md5_flat:12:4}-${md5_flat:16:4}-${md5_flat:20:12}

    used_larcv_prebit=${used_larcv_hash:0:2}
    used_hist_prebit=${used_hist_hash:0:2}
    used_caf_prebit=${used_caf_hash:0:2}
    used_flat_prebit=${used_flat_hash:0:2}

    newLarcvFile=${excised_larcvFile%.root}-${used_larcv_hash}.root
    newHistFile=${excised_histFile%.root}-${used_hist_hash}.root
    newCafFile=${excised_cafFile%.root}-${used_caf_hash}.caf.root
    newFlatFile=${excised_flatFile%.root}-${used_flat_hash}.flat.caf.root

    mv ${larcvFile} ${newLarcvFile}
    mv ${histFile} ${newHistFile}
    mv ${cafFile} ${newCafFile}
    mv ${flatFile} ${newFlatFile}

    echo -e "Definitive larcv name: ${newLarcvFile}"
    echo -e "Definitive hist name: ${newHistFile}"
    echo -e "Definitive caf name: ${newCafFile}"
    echo -e "Definitive flat name: ${newFlatFile}"

    LARCV_MD=md_larcv.json
    HIST_MD=md_hist.json
    CAF_MD=md_caf.json
    FLAT_MD=md_flat.json
    touch ${LARCV_MD}; touch ${HIST_MD}; touch ${CAF_MD}; touch ${FLAT_MD}

    MDFILES+=$(${LARCV_MD})
    MDFILES+=$(${HIST_MD})
    MDFILES+=$(${CAF_MD})
    MDFILES+=$(${FLAT_MD})
fi

for mdFile in "${MDFILES[@]}" ; do
    echo -e "{" >> ${mdFile}
done

# file names
if [[ ! -z ${stage0File} ]] ; then
    echo -e " \"file_name\": \"$(basename ${newStage0File})\"," >> ${STAGE0_MD}
else
    echo -e " \"file_name\": \"$(basename ${newLarcvFile})\"," >> ${LARCV_MD}
    echo -e " \"file_name\": \"$(basename ${newHistFile})\"," >> ${HIST_MD}
    echo -e " \"file_name\": \"$(basename ${newCafFile})\"," >> ${CAF_MD}
    echo -e " \"file_name\": \"$(basename ${newFlatFile})\"," >> ${FLAT_MD}
fi

# file sizes
if [[ ! -z ${stage0File} ]] ; then
    echo -e " \"file_size\": $(stat -c %s ${newStage0File} | awk -F " " '{print $1}')," >> ${STAGE0_MD}
else
    echo -e " \"file_size\": $(stat -c %s ${newLarcvFile} | awk -F " " '{print $1}')," >> ${LARCV_MD}
    echo -e " \"file_size\": $(stat -c %s ${newHistFile} | awk -F " " '{print $1}')," >> ${HIST_MD}
    echo -e " \"file_size\": $(stat -c %s ${newCafFile} | awk -F " " '{print $1}')," >> ${CAF_MD}
    echo -e " \"file_size\": $(stat -c %s ${newFlatFile} | awk -F " " '{print $1}')," >> ${FLAT_MD}
fi

# Specific data tiers for outputs
if [[ ! -z ${stage0File} ]] ; then
    echo -e " \"data_tier\": \"reconstructed\"," >> ${STAGE0_MD}
else
    echo -e " \"data_tier\": \"larcv\"," >> ${LARCV_MD}
    echo -e " \"data_tier\": \"root-tuple\"," >> ${HIST_MD}
    echo -e " \"data_tier\": \"caf\"," >> ${CAF_MD}
    echo -e " \"data_tier\": \"flat_caf\"," >> ${FLAT_MD}
fi

# file formats
if [[ ! -z ${stage0File} ]] ; then
    echo -e " \"file_format\": \"artroot\"," >> ${STAGE0_MD}
else
    echo -e " \"file_format\": \"larcv\"," >> ${LARCV_MD}
    echo -e " \"file_format\": \"root\"," >> ${HIST_MD}
    echo -e " \"file_format\": \"caf\"," >> ${CAF_MD}
    echo -e " \"file_format\": \"flat_caf\"," >> ${FLAT_MD}
fi

# Checksums
for mdFile in "${MDFILES[@]}" ; do
    echo -e " \"checksum\": [" >> ${mdFile}
done
if [[ ! -z ${stage0File} ]] ; then
    echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newStage0File} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${STAGE0_MD}
else
    echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newLarcvFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${LARCV_MD}
    echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newHistFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${HIST_MD}
    echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newCafFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${CAF_MD}
    echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newFlatFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${FLAT_MD}
fi
for mdFile in "${MDFILES[@]}" ; do
    echo -e " ]," >> ${mdFile}
done

# Dataset tags
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${ICARUSCODE_VERSION}
export STAGE0_DTAG=${DTAG_PREAMBLE}_stage0_icarus
export LARCV_DTAG=${DTAG_PREAMBLE}_larcvstage0_icarus
export HIST_DTAG=${DTAG_PREAMBLE}_histstage1_icarus
export CAF_DTAG=${DTAG_PREAMBLE}_caf_icarus
export FLAT_DTAG=${DTAG_PREAMBLE}_flatcaf_icarus

if [[ ! -z ${stage0File} ]] ; then
    echo -e " \"Dataset.Tag\": \"${STAGE0_DTAG}\"," >> ${STAGE0_MD}
else
    echo -e " \"Dataset.Tag\": \"${LARCV_DTAG}\"," >> ${LARCV_MD}
    echo -e " \"Dataset.Tag\": \"${HIST_DTAG}\"," >> ${HIST_MD}
    echo -e " \"Dataset.Tag\": \"${CAF_DTAG}\"," >> ${CAF_MD}
    echo -e " \"Dataset.Tag\": \"${FLAT_DTAG}\"," >> ${FLAT_MD}
fi

# Common tags
for mdFile in "${MDFILES[@]}" ; do
    echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${mdFile}
    echo -e " \"file_type\": \"mc\"," >> ${mdFile}
    echo -e " \"group\": \"icarus\"," >> ${mdFile}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"icaruscode\",\n\t\"version\": \"${ICARUSCODE_VERSION}\"\n }," >> ${mdFile}
    echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${mdFile}
    echo -e " \"art.file_format_version\": 15," >> ${mdFile}
    echo -e " \"art.run_type\": \"physics\"," >> ${mdFile}
done
# Insert process names
if [[ ! -z ${stage0File} ]] ; then
    echo -e " \"art.process_name\": \"Stage0\"," >> ${STAGE0_MD}
else
    echo -e " \"art.process_name\": \"Stage1\"," >> ${LARCV_MD}
    echo -e " \"art.process_name\": \"Stage1\"," >> ${HIST_MD}
    echo -e " \"art.process_name\": \"caf\"," >> ${CAF_MD}
    echo -e " \"art.process_name\": \"caf\"," >> ${FLAT_MD}
fi

# Back to common tags
for mdFile in "${MDFILES[@]}" ; do
    echo -e " \"fcl.name\": \"${fcl_list}\"," >> ${mdFile}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${mdFile}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${mdFile}
    echo -e " \"mc.generated_event_count\": ${MT_EVENTS_PER_JOB}," >> ${mdFile}
    echo -e " \"data_stream\": \"out1\"," >> ${mdFile}
    echo -e " \"icarus_project.name\": \"${MT_PROJECTNAME}\"," >> ${mdFile}
    echo -e " \"icarus_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${mdFile}
    echo -e " \"icarus_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${mdFile}
    echo -e " \"icarus_project.version\": \"${ICARUSCODE_VERSION}\"," >> ${mdFile}
    echo -e " \"runs\": [" >> ${mdFile}
    echo -e "   [" >> ${mdFile}
    echo -e "     ${run_no}," >> ${mdFile}
    echo -e "     ${subrun_no}," >> ${mdFile}
    echo -e "     \"physics\"" >> ${mdFile}
    echo -e "   ]" >> ${mdFile}
    echo -e " ]," >> ${mdFile}
    echo -e " \"event_count\": ${event_count}," >> ${mdFile}
    echo -e " \"first_event\": ${first_event}," >> ${mdFile}
    echo -e " \"last_event\": ${last_event}," >> ${mdFile}
    echo -e " \"parents\": [" >> ${mdFile}
    echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }" >> ${mdFile}
    echo -e "  ]" >> ${mdFile}
    echo -e " }" >> ${mdFile}
done

if [[ ! -z ${stage0File} ]] ; then
    echo -e "Here is the stage0 json..."
    cat ${STAGE0_MD} | sed '/^$/d'
else
    echo -e "Here is the larcv json..."
    cat ${LARCV_MD} | sed '/^$/d'
    
    echo -e "Here is the hist json..."
    cat ${HIST_MD} | sed '/^$/d'
    
    echo -e "Here is the caf json..."
    cat ${CAF_MD} | sed '/^$/d'
    
    echo -e "Here is the flat json..."
    cat ${FLAT_MD} | sed '/^$/d'
fi

echo "Here are the contents of my workdir..."
ls -ltrh

# Retire any declared files before moving on.
if [[ ! -z ${stage0File} ]] ; then
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newStage0File))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newStage0File) ; fi
else
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newLarcvFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newLarcvFile) ; fi
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newHistFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newHistFile) ; fi
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newCafFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newCafFile) ; fi
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newFlatFile))
    if [[ $? == 0 ]] ; then
	samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newFlatFile) ; fi
fi

# now validate the metadata
echo "Validating metadata...."
if [[ ! -z ${stage0File} ]] ; then
    samweb -e ${SAM_EXPERIMENT} validate-metadata ${STAGE0_MD}
else
    samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD}
    samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD}
    samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD}
    samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD}
fi

# and finally, declare these!
# Set output directories based on stage
if [[ ! -z ${stage0File} ]] ; then
    FULL_STAGE0_OUTDIR=${IFDH_OUTPUT_DIR}/stage0/${MT_ICARUS_STREAM_NAME}/${used_stage0_prebit}/
else
    FULL_LARCV_OUTDIR=${IFDH_OUTPUT_DIR}/larcv/${MT_ICARUS_STREAM_NAME}/${used_larcv_prebit}/
    FULL_HIST_OUTDIR=${IFDH_OUTPUT_DIR}/calib/${MT_ICARUS_STREAM_NAME}/${used_hist_prebit}/
    FULL_CAF_OUTDIR=${IFDH_OUTPUT_DIR}/caf/${MT_ICARUS_STREAM_NAME}/${used_caf_prebit}/
    FULL_FLAT_OUTDIR=${IFDH_OUTPUT_DIR}/flatcaf/${MT_ICARUS_STREAM_NAME}/${used_flat_prebit}/
fi

if [[ ! -z ${stage0File} ]] ; then
    ###### STAGE0 DECLARATION ######
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${STAGE0_MD} ; then
	# copy this back
	ifdh cp -D ${newStage0File} ${FULL_STAGE0_OUTDIR} && echo "COPYING STAGE0 FILE $(basename ${newStage0File}) TO ${FULL_STAGE0_OUTDIR}..."
	samweb -e ${SAM_EXPERIMENT} declare-file ${STAGE0_MD}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newStage0File}) dcache:${FULL_STAGE0_OUTDIR}
	echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newStage0File}) dcache:${FULL_STAGE0_OUTDIR}"

	samweb -e ${SAM_EXPERIMENT} create-definition ${STAGE0_DTAG} "Dataset.Tag ${STAGE0_DTAG}"
    fi
else
    ###### LARCV DECLARATION ######
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD} ; then
	# copy this back
	ifdh cp -D ${newLarcvFile} ${FULL_LARCV_OUTDIR} && echo "COPYING LARCV FILE $(basename ${newLarcvFile}) TO ${FULL_LARCV_OUTDIR}..."
	samweb -e ${SAM_EXPERIMENT} declare-file ${LARCV_MD}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}
	echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}"

	samweb -e ${SAM_EXPERIMENT} create-definition ${LARCV_DTAG} "Dataset.Tag ${LARCV_DTAG}"
    fi
    ###### HISTSTAGE1 DECLARATION ######
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD} ; then
	# copy this back
	ifdh cp -D ${newHistFile} ${FULL_HIST_OUTDIR} && echo "COPYING HIST FILE $(basename ${newHistFile}) TO ${FULL_HIST_OUTDIR}..."
	samweb -e ${SAM_EXPERIMENT} declare-file ${HIST_MD}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newHistFile}) dcache:${FULL_HIST_OUTDIR}
	echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newHistFile}) dcache:${FULL_HIST_OUTDIR}"
	
	samweb -e ${SAM_EXPERIMENT} create-definition ${HIST_DTAG} "Dataset.Tag ${HIST_DTAG}"
    fi
    ###### CAF DECLARATION ######
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD} ; then
	# copy this back
	ifdh cp -D ${newCafFile} ${FULL_CAF_OUTDIR} && echo "COPYING CAF FILE $(basename ${newCafFile}) TO ${FULL_CAF_OUTDIR}..."
	samweb -e ${SAM_EXPERIMENT} declare-file ${CAF_MD}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newCafFile}) dcache:${FULL_CAF_OUTDIR}
	echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newCafFile}) dcache:${FULL_CAF_OUTDIR}"
	
	samweb -e ${SAM_EXPERIMENT} create-definition ${CAF_DTAG} "Dataset.Tag ${CAF_DTAG}"
    fi
    ###### FLATCAF DECLARATION ######
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD} ; then
	# copy this back
	ifdh cp -D ${newFlatFile} ${FULL_FLAT_OUTDIR} && echo "COPYING FLATCAF FILE $(basename ${newFlatFile}) TO ${FULL_FLAT_OUTDIR}..."
	samweb -e ${SAM_EXPERIMENT} declare-file ${FLAT_MD}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR}
	echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR}"

	samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_DTAG} "Dataset.Tag ${FLAT_DTAG}"
    fi
fi
    
echo -e "Done"

echo "$0 done"
