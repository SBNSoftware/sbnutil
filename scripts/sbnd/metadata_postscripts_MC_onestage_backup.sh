#!/bin/bash

# Adapted from metadata_postscripts_onestage.sh (DATA) for use on MC
# Essentially, build the metadata for the file manually while ignoring artroot.
# Most of this stuff is already exported as env variables, from the prescripts stage.

>&2 echo -e "\n\nSTARTING $0...\n\n"

initialFile=$(basename ${PARENT_FILE_SAM}) # Initial fcl (parent) file
detsimFile=''  # Detsim files
reco1File=''   # Artroot reco1 files
larcvFile=''   # LarCV files
histFile=''    # Calib ntuples
cafFile=''     # CAF trees
flatFile=''    # FlatCAF trees

>&2 echo -e "\n\nUsing fcl list $1...\n\n"

detsimFile=$(find ./ -iname '*.root' | grep 'detsim' | grep -v 'larcv' | grep -v 'reco1' | grep -v 'hist' | grep -v 'reco2' | grep -v 'caf')
reco1File=$(find ./ -iname '*.root' | grep 'reco1' | grep -v 'larcv' | grep -v 'hist' | grep -v 'reco2' | grep -v 'caf')
larcvFile=$(find ./ -iname 'larcv*.root' | grep -v 'reco2')
histFile=$(find ./ -iname 'hist*.root' | grep 'reco2' | head -n 1)
cafFile=$(find ./ -iname '*caf.root' | grep -v 'flat') # looks like it was literally 'caf.root'..
flatFile=$(find ./ -iname '*.caf.root' | grep 'flat')

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

echo -e "detsimFile: ${detsimFile}"
echo -e "reco1File: ${reco1File}"
echo -e "larcvFile: ${larcvFile}"
echo -e "histFile: ${histFile}"
echo -e "cafFile: ${cafFile}"
echo -e "flatFile: ${flatFile}"

# Initial fcl is the parent
>&2 echo -e "\n\nFrom initial fcl file ${initialFile} I get metadata..."
samweb -e ${SAM_EXPERIMENT} get-metadata --json ${initialFile} > old_par_md.json
par_name=${initialFile/.root/}

# Get the first and last event as well as the run and subrun
# There could be a more elegant way to do this. Or, we could invoke the wrath of Bash.
# Scour the message logs, find any lines with timesamps and run/subrun/event, remove away any code,
# these are in tokens 'run: X subRun: Y event: Z', extract uniques, and sort for first/last based on Z
source_log=messages.log
first_token=$(cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5n | head -n 1)
last_token=$(cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5nr | head -n 1)
run_no=$(echo ${first_token} | awk -F " " '{print $1}')
subrun_no=$(echo ${first_token} | awk -F " " '{print $3}')
first_event=$(echo ${first_token} | awk -F " " '{print $5}')
last_event=$(echo ${last_token} | awk -F " " '{print $5}')

# Get event_count from specific JSON file
json_file="hist_gen_g4_detsim_reco1_reco2_caf.root.json"
event_count=$(grep '"event_count":' "$json_file" | head -1 | sed 's/.*"event_count": *//' | sed 's/[^0-9].*//')

#########################

# We'll pass the fcl-file-list here, under fcl.name
fcl_list=$1

# Rename files uniquely, based on their own md5sum.
# This ensures that we have unique file names
md5_detsim=$(md5sum ${detsimFile} | awk -F " " '{print $1}')
md5_reco1=$(md5sum ${reco1File} | awk -F " " '{print $1}')
md5_larcv=$(md5sum ${larcvFile} | awk -F " " '{print $1}')
md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
md5_caf=$(md5sum ${cafFile} | awk -F " " '{print $1}')
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

# To make things a bit more unique, I will pipe this to a file, append some random numbers, and md5sum
echo $md5_detsim > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_detsim=$(md5sum ${detsimFile} | awk -F " " '{print $1}')
echo $md5_reco1 > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_reco1=$(md5sum ${reco1File} | awk -F " " '{print $1}')
echo $md5_larcv > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_larcv=$(md5sum ${larcvFile} | awk -F " " '{print $1}')
echo $md5_hist > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
echo $md5_caf > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_caf=$(md5sum ${cafFile} | awk -F " " '{print $1}')
echo $md5_flat > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

# In case there is a hash in the filenames, remove it
old_detsim_hash=$(echo ${detsimFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_detsimFile=${detsimFile%-${old_detsim_hash}*}
old_reco1_hash=$(echo ${reco1File} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_reco1File=${reco1File%-${old_reco1_hash}*}
old_larcv_hash=$(echo ${larcvFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_larcvFile=${larcvFile%-${old_larcv_hash}*}
old_hist_hash=$(echo ${histFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_histFile=${histFile%-${old_hist_hash}*}
old_caf_hash=$(echo ${cafFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_cafFile=${cafFile%-${old_caf_hash}*}
old_flat_hash=$(echo ${flatFile} | sed 's/.*run\([^.]*\)\.root/\1/' | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_flatFile=${flatFile%-${old_flat_hash}*}

used_detsim_hash=${md5_detsim:0:8}-${md5_detsim:8:4}-${md5_detsim:12:4}-${md5_detsim:16:4}-${md5_detsim:20:12}
used_reco1_hash=${md5_reco1:0:8}-${md5_reco1:8:4}-${md5_reco1:12:4}-${md5_reco1:16:4}-${md5_reco1:20:12}
used_larcv_hash=${md5_larcv:0:8}-${md5_larcv:8:4}-${md5_larcv:12:4}-${md5_larcv:16:4}-${md5_larcv:20:12}
used_hist_hash=${md5_hist:0:8}-${md5_hist:8:4}-${md5_hist:12:4}-${md5_hist:16:4}-${md5_hist:20:12}
used_caf_hash=${md5_caf:0:8}-${md5_caf:8:4}-${md5_caf:12:4}-${md5_caf:16:4}-${md5_caf:20:12}
used_flat_hash=${md5_flat:0:8}-${md5_flat:8:4}-${md5_flat:12:4}-${md5_flat:16:4}-${md5_flat:20:12}

used_detsim_prebit=${used_detsim_hash:0:2}
used_reco1_prebit=${used_reco1_hash:0:2}
used_larcv_prebit=${used_larcv_hash:0:2}
used_hist_prebit=${used_hist_hash:0:2}
used_caf_prebit=${used_caf_hash:0:2}
used_flat_prebit=${used_flat_hash:0:2}

# Definitive names for the outputs
newDetsimFile=${excised_detsimFile%.root}-${used_detsim_hash}.root
newReco1File=${excised_reco1File%.root}-${used_reco1_hash}.root
newLarcvFile=${excised_larcvFile%.root}-${used_larcv_hash}.root
newHistFile=${excised_histFile%.root}-${used_hist_hash}.root
newCafFile=${excised_cafFile%.root}-${used_caf_hash}.caf.root
newFlatFile=${excised_flatFile%.root}-${used_flat_hash}.flat.caf.root

mv ${detsimFile} ${newDetsimFile}
mv ${reco1File} ${newReco1File}
mv ${larcvFile} ${newLarcvFile}
mv ${histFile} ${newHistFile}
mv ${cafFile} ${newCafFile}
mv ${flatFile} ${newFlatFile}

echo -e "Definitive detsim name: ${newDetsimFile}"
echo -e "Definitive reco1 name: ${newReco1File}"
echo -e "Definitive larcv name: ${newLarcvFile}"
echo -e "Definitive hist name: ${newHistFile}"
echo -e "Definitive caf name: ${newCafFile}"
echo -e "Definitive flat name: ${newFlatFile}"

# Construct json files.
DETSIM_MD=md_detsim.json
RECO1_MD=md_reco1.json
LARCV_MD=md_larcv.json
HIST_MD=md_hist.json
CAF_MD=md_caf.json
FLAT_MD=md_flat.json

touch ${DETSIM_MD}; touch ${RECO1_MD}; touch ${LARCV_MD}; touch ${HIST_MD}; touch ${CAF_MD}; touch ${FLAT_MD}

for mdFile in ${DETSIM_MD} ${RECO1_MD} ${LARCV_MD} ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e "{" >> ${mdFile}
done

# file names
echo -e " \"file_name\": \"$(basename ${newDetsimFile})\"," >> ${DETSIM_MD}
echo -e " \"file_name\": \"$(basename ${newReco1File})\"," >> ${RECO1_MD}
echo -e " \"file_name\": \"$(basename ${newLarcvFile})\"," >> ${LARCV_MD}
echo -e " \"file_name\": \"$(basename ${newHistFile})\"," >> ${HIST_MD}
echo -e " \"file_name\": \"$(basename ${newCafFile})\"," >> ${CAF_MD}
echo -e " \"file_name\": \"$(basename ${newFlatFile})\"," >> ${FLAT_MD}

# file sizes
echo -e " \"file_size\": $(stat -c %s ${newDetsimFile} | awk -F " " '{print $1}')," >> ${DETSIM_MD}
echo -e " \"file_size\": $(stat -c %s ${newReco1File} | awk -F " " '{print $1}')," >> ${RECO1_MD}
echo -e " \"file_size\": $(stat -c %s ${newLarcvFile} | awk -F " " '{print $1}')," >> ${LARCV_MD}
echo -e " \"file_size\": $(stat -c %s ${newHistFile} | awk -F " " '{print $1}')," >> ${HIST_MD}
echo -e " \"file_size\": $(stat -c %s ${newCafFile} | awk -F " " '{print $1}')," >> ${CAF_MD}
echo -e " \"file_size\": $(stat -c %s ${newFlatFile} | awk -F " " '{print $1}')," >> ${FLAT_MD}

# Specific data tiers for outputs
echo -e " \"data_tier\": \"detector-simulated\"," >> ${DETSIM_MD}
echo -e " \"data_tier\": \"reconstructed\"," >> ${RECO1_MD}
echo -e " \"data_tier\": \"larcv\"," >> ${LARCV_MD}
echo -e " \"data_tier\": \"root-tuple\"," >> ${HIST_MD}
echo -e " \"data_tier\": \"caf\"," >> ${CAF_MD}
echo -e " \"data_tier\": \"flat_caf\"," >> ${FLAT_MD}

# file formats
echo -e " \"file_format\": \"artroot\"," >> ${DETSIM_MD}
echo -e " \"file_format\": \"artroot\"," >> ${RECO1_MD}
echo -e " \"file_format\": \"larcv\"," >> ${LARCV_MD}
echo -e " \"file_format\": \"root\"," >> ${HIST_MD}
echo -e " \"file_format\": \"caf\"," >> ${CAF_MD}
echo -e " \"file_format\": \"flat_caf\"," >> ${FLAT_MD}

# Checksums
for mdFile in ${DETSIM_MD} ${RECO1_MD} ${LARCV_MD} ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"checksum\": [" >> ${mdFile}
done
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newDetsimFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${DETSIM_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newReco1File} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${RECO1_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newLarcvFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${LARCV_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newHistFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${HIST_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newCafFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${CAF_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newFlatFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${FLAT_MD}
for mdFile in ${DETSIM_MD} ${RECO1_MD} ${LARCV_MD} ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " ]," >> ${mdFile}
done

# Dataset tags
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${SBNDCODE_VERSION}
export DETSIM_DTAG=${DTAG_PREAMBLE}_detsim_sbnd
export RECO1_DTAG=${DTAG_PREAMBLE}_reco1_sbnd
export LARCV_DTAG=${DTAG_PREAMBLE}_larcvreco1_sbnd
export HIST_DTAG=${DTAG_PREAMBLE}_histreco2_sbnd
export CAF_DTAG=${DTAG_PREAMBLE}_caf_sbnd
export FLAT_DTAG=${DTAG_PREAMBLE}_flatcaf_sbnd

echo -e " \"Dataset.Tag\": \"${DETSIM_DTAG}\"," >> ${DETSIM_MD}
echo -e " \"Dataset.Tag\": \"${RECO1_DTAG}\"," >> ${RECO1_MD}
echo -e " \"Dataset.Tag\": \"${LARCV_DTAG}\"," >> ${LARCV_MD}
echo -e " \"Dataset.Tag\": \"${HIST_DTAG}\"," >> ${HIST_MD}
echo -e " \"Dataset.Tag\": \"${CAF_DTAG}\"," >> ${CAF_MD}
echo -e " \"Dataset.Tag\": \"${FLAT_DTAG}\"," >> ${FLAT_MD}

# Common tags
for mdFile in ${DETSIM_MD} ${RECO1_MD} ${LARCV_MD} ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"process_id\": ${SAM_CONSUMER_ID}," >> ${mdFile}
    echo -e " \"file_type\": \"mc\"," >> ${mdFile}
    echo -e " \"group\": \"sbnd\"," >> ${mdFile}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${mdFile}
    echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${mdFile}
    echo -e " \"art.file_format_version\": 15," >> ${mdFile}
    echo -e " \"art.run_type\": \"physics\"," >> ${mdFile}
done
# Insert process names
echo -e " \"art.process_name\": \"DetSim\"," >> ${DETSIM_MD}
echo -e " \"art.process_name\": \"Reco1\"," >> ${RECO1_MD}
echo -e " \"art.process_name\": \"Reco1\"," >> ${LARCV_MD}
echo -e " \"art.process_name\": \"Reco2\"," >> ${HIST_MD}
echo -e " \"art.process_name\": \"caf\"," >> ${CAF_MD}
echo -e " \"art.process_name\": \"caf\"," >> ${FLAT_MD}

# Back to common tags
for mdFile in ${DETSIM_MD} ${RECO1_MD} ${LARCV_MD} ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"fcl.name\": \"${fcl_list}\"," >> ${mdFile}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\"," >> ${mdFile}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\"," >> ${mdFile}
    echo -e " \"mc.generated_event_count\": ${MT_EVENTS_PER_JOB}," >> ${mdFile}
    echo -e " \"data_stream\": \"out1\"," >> ${mdFile}
    echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\"," >> ${mdFile}
    echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${mdFile}
    echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\"," >> ${mdFile}
    echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\"," >> ${mdFile}
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

echo -e "Here is the detsim json..."
cat ${DETSIM_MD} | sed '/^$/d'

echo -e "Here is the reco1 json..."
cat ${RECO1_MD} | sed '/^$/d'

echo -e "Here is the larcv json..."
cat ${LARCV_MD} | sed '/^$/d'

echo -e "Here is the hist json..."
cat ${HIST_MD} | sed '/^$/d'

echo -e "Here is the caf json..."
cat ${CAF_MD} | sed '/^$/d'

echo -e "Here is the flat json..."
cat ${FLAT_MD} | sed '/^$/d'

echo "Here are the contents of my workdir..."
ls -ltrh

# Retire any declared files before moving on.
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newDetsimFile))
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newDetsimFile) ; fi
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename $newReco1File))
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename $newReco1File) ; fi
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

# now validate the metadata
echo "Validating metadata...."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${DETSIM_MD}
samweb -e sbn validate-metadata ${DETSIM_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${RECO1_MD}
samweb -e sbn validate-metadata ${RECO1_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD}
samweb -e sbn validate-metadata ${LARCV_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD}
samweb -e sbn validate-metadata ${HIST_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD}
samweb -e sbn validate-metadata ${CAF_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD}
samweb -e sbn validate-metadata ${FLAT_MD}

# and finally, declare these!
# Set output directories based on stage
FULL_DETSIM_OUTDIR=${IFDH_OUTPUT_DIR}/detsim/${MT_SBND_STREAM_NAME}/${used_detsim_prebit}/
FULL_RECO1_OUTDIR=${IFDH_OUTPUT_DIR}/reco1/${MT_SBND_STREAM_NAME}/${used_reco1_prebit}/
FULL_LARCV_OUTDIR=${IFDH_OUTPUT_DIR}/larcv/${MT_SBND_STREAM_NAME}/${used_larcv_prebit}/
FULL_HIST_OUTDIR=${IFDH_OUTPUT_DIR}/calib/${MT_SBND_STREAM_NAME}/${used_hist_prebit}/
FULL_CAF_OUTDIR=${IFDH_OUTPUT_DIR}/caf/${MT_SBND_STREAM_NAME}/${used_caf_prebit}/
FULL_FLAT_OUTDIR=${IFDH_OUTPUT_DIR}/flatcaf/${MT_SBND_STREAM_NAME}/${used_flat_prebit}/

# Override for detsim: this will put our disk space in trouble
COPY_BACK_DETSIM=0
if [[ ${COPY_BACK_DETSIM} == 1 ]] ; then
    ###### DETSIM DECLARATION ######
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${DETSIM_MD} ; then
	# copy this back
	ifdh cp -D ${newDetsimFile} ${FULL_DETSIM_OUTDIR} && echo "COPYING DETSIM FILE $(basename ${newDetsimFile}) TO ${FULL_DETSIM_OUTDIR}..."
	echo "DECLARING DETSIM ARTROOT FILE to both SBND and SBN ${newDetsimFile}"
	samweb -e ${SAM_EXPERIMENT} declare-file ${DETSIM_MD}
 samweb -e sbn declare-file ${DETSIM_MD}
	samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newDetsimFile}) dcache:${FULL_DETSIM_OUTDIR}
 samweb -e sbn add-file-location $(basename ${newDetsimFile}) dcache:${FULL_DETSIM_OUTDIR}
	echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newDetsimFile}) dcache:${FULL_DETSIM_OUTDIR}"
	
	echo -e "Creating definition for both SBND and SBN ${DETSIM_DTAG}..."
	samweb -e ${SAM_EXPERIMENT} create-definition ${DETSIM_DTAG} "Dataset.Tag ${DETSIM_DTAG}"
	samweb -e sbn create-definition ${DETSIM_DTAG} "Dataset.Tag ${DETSIM_DTAG}"
    fi
fi # copy back detsim?
###### RECO1 DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${RECO1_MD} ; then
    # copy this back
    ifdh cp -D ${newReco1File} ${FULL_RECO1_OUTDIR} && echo "COPYING RECO1 FILE $(basename ${newReco1File}) TO ${FULL_RECO1_OUTDIR}..."
    echo "DECLARING RECO1 ARTROOT FILE to both SBND and SBN${newReco1File}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${RECO1_MD}
    samweb -e sbn declare-file ${RECO1_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newReco1File}) dcache:${FULL_RECO1_OUTDIR}
    samweb -e sbn add-file-location $(basename ${newReco1File}) dcache:${FULL_RECO1_OUTDIR}
    echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newReco1File}) dcache:${FULL_RECO1_OUTDIR}"

    echo -e "Creating definition for both SBND and SBN ${RECO1_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${RECO1_DTAG} "Dataset.Tag ${RECO1_DTAG}"
    samweb -e sbn create-definition ${RECO1_DTAG} "Dataset.Tag ${RECO1_DTAG}"
fi
###### LARCV DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD} ; then
    # copy this back
    ifdh cp -D ${newLarcvFile} ${FULL_LARCV_OUTDIR} && echo "COPYING LARCV FILE $(basename ${newLarcvFile}) TO ${FULL_LARCV_OUTDIR}..."
    echo "DECLARING LARCV FILE to both SBND and SBN ${newLarcvFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${LARCV_MD}
    samweb -e sbn declare-file ${LARCV_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}
    samweb -e sbn add-file-location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}
    echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}"

    echo -e "Creating definition for both SBND and SBN ${LARCV_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${LARCV_DTAG} "Dataset.Tag ${LARCV_DTAG}"
    samweb -e sbn create-definition ${LARCV_DTAG} "Dataset.Tag ${LARCV_DTAG}"
fi
###### HISTRECO2 DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD} ; then
    # copy this back
    ifdh cp -D ${newHistFile} ${FULL_HIST_OUTDIR} && echo "COPYING HIST FILE $(basename ${newHistFile}) TO ${FULL_HIST_OUTDIR}..."
    echo "DECLARING HISTOGRAM FILE to both SBND and SBN ${newHistFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${HIST_MD}
    samweb -e sbn declare-file ${HIST_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newHistFile}) dcache:${FULL_HIST_OUTDIR}
    samweb -e sbn add-file-location $(basename ${newHistFile}) dcache:${FULL_HIST_OUTDIR}
    echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newHistFile}) dcache:${FULL_HIST_OUTDIR}"

    echo -e "Creating definition for both SBND and SBN ${HIST_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${HIST_DTAG} "Dataset.Tag ${HIST_DTAG}"
    samweb -e sbn create-definition ${HIST_DTAG} "Dataset.Tag ${HIST_DTAG}"
fi
###### CAF DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD} ; then
    # copy this back
    ifdh cp -D ${newCafFile} ${FULL_CAF_OUTDIR} && echo "COPYING CAF FILE $(basename ${newCafFile}) TO ${FULL_CAF_OUTDIR}..."
    echo "DECLARING CAF FILE to both SBND and SBN ${newCafFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${CAF_MD}
    samweb -e sbn declare-file ${CAF_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newCafFile}) dcache:${FULL_CAF_OUTDIR}
    samweb -e sbn add-file-location $(basename ${newCafFile}) dcache:${FULL_CAF_OUTDIR}
    echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newCafFile}) dcache:${FULL_CAF_OUTDIR}"

    echo -e "Creating definition for both SBND and SBN ${CAF_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${CAF_DTAG} "Dataset.Tag ${CAF_DTAG}"
    samweb -e sbn create-definition ${CAF_DTAG} "Dataset.Tag ${CAF_DTAG}"
fi
###### FLATCAF DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD} ; then
    # copy this back
    ifdh cp -D ${newFlatFile} ${FULL_FLAT_OUTDIR} && echo "COPYING FLATCAF FILE $(basename ${newFlatFile}) TO ${FULL_FLAT_OUTDIR}..."
    echo "DECLARING FLAT FILE to both SBND and SBN ${newFlatFile}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${FLAT_MD}
    samweb -e sbn declare-file ${FLAT_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR}
    samweb -e sbn add-file-location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR}
    echo -e "samweb -e ${SAM_EXPERIMENT} add_file_location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR}"

    echo -e "Creating definition for both SBND and SBN ${FLAT_DTAG}..."
    samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_DTAG} "Dataset.Tag ${FLAT_DTAG}"
    samweb -e sbn create-definition ${FLAT_DTAG} "Dataset.Tag ${FLAT_DTAG}"
fi

echo -e "Done"

echo "$0 done"
