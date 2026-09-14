#!/bin/bash

# =============================================================================
# metadata_postscripts_MC_LArCV_wiremod.sh
#
# Metadata postscript for the MC wiremod->larcv-only POMS stage.
#
# Runs AFTER the wiremod executable finishes.
#
# Adapted from:
#   metadata_postscripts_MC_LArCV_wiremod_reco2_caf.sh (full wiremod+reco2+caf pipeline)
#
# Key differences from metadata_postscripts_MC_LArCV_wiremod_reco2_caf.sh:
#   - PARENT_FILE_SAM is the reco1-input artroot file (set by metadata_prescripts.sh)
#   - Only larcv is saved (declared to SAMWeb, copied to dCache)
#   - wiremod.root is an intermediate and is discarded, like scrub/detsim
#   - reco2/caf/flatcaf are not produced by this stage and are not handled here
#   - event_count is read from hist_<mdprojectstage>.root.json
#
# What this script does, in order:
#   1. Find the larcv output file
#   2. Read run/subrun/event info from the messages log
#   3. Read event_count from the hist JSON sidecar
#   4. Rename the file with a unique hash (avoids filename collisions in dCache)
#   5. Build a SAMWeb JSON metadata file
#   6. Retire any previously declared file with the same name (safety)
#   7. Validate metadata with SAMWeb
#   8. Copy, declare, and add location to SAMWeb
#   9. Create a SAMWeb dataset definition
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

# PARENT_FILE_SAM is set by metadata_prescripts.sh (run during job setup).
# It contains the SAM filename of the reco1-input artroot file for this job.
# The larcv output lists this file as its parent.
initialFile=$(basename ${PARENT_FILE_SAM})

# Output file variable -- populated by find command below
larcvFile=''   # LArCV file

>&2 echo -e "\n\nUsing fcl list $1...\n\n"
>&2 echo -e "\n\nParent reco1-input file: ${initialFile}\n\n"

# =============================================================================
# STEP 1: Find output file
#
# wiremod.root is not handled here -- it is simply left in the working
# directory and discarded when the job exits, like the scrub/detsim
# intermediates in the full pipeline.
# =============================================================================

# larcv files
larcvFile=$(find ./ -iname 'larcv*.root' | grep -v 'reco2')

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

echo -e "larcvFile: ${larcvFile}"

# =============================================================================
# STEP 2: Get run/subrun/event info from the messages log
# =============================================================================
source_log=messages.log

first_token=$(cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5n  | head -n 1)
last_token=$( cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5nr | head -n 1)

run_no=$(    echo ${first_token} | awk -F " " '{print $1}')
subrun_no=$( echo ${first_token} | awk -F " " '{print $3}')
first_event=$(echo ${first_token} | awk -F " " '{print $5}')
last_event=$( echo ${last_token}  | awk -F " " '{print $5}')

# =============================================================================
# STEP 3: Get event_count from the hist JSON sidecar
#
# sbnpoms_metadata_injector.sh (prescript_8) produces this JSON sidecar,
# named hist_<mdprojectstage>.root.json, alongside the -T histogram output.
# =============================================================================
json_file="hist_${MT_PROJECTSTAGE}.root.json"
event_count=$(grep '"event_count":' "$json_file" | head -1 | sed 's/.*"event_count": *//' | sed 's/[^0-9].*//')

# The fcl list is passed as argument $1 from the cfg postscript line
fcl_list=$1

# =============================================================================
# STEP 4: Compute md5 hash and build a unique filename
#
# The file is renamed to include an md5-based UUID to guarantee a globally
# unique filename in dCache and SAMWeb. The hash is derived from the file
# content plus some $RANDOM salt.
#
# Format: <base_name>-<UUID>.root   (UUID = 8-4-4-4-12 hex groups)
# First 2 hex chars of UUID are used as a dCache subdirectory prefix.
# =============================================================================

echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_larcv=$(md5sum ${larcvFile} | awk -F " " '{print $1}')

# --- Strip any existing UUID hash from filename (in case of reprocessing) ---
old_larcv_hash=$(echo ${larcvFile}  | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_larcvFile=${larcvFile%-${old_larcv_hash}*}

# --- Format md5 as UUID (8-4-4-4-12) ---
used_larcv_hash=${md5_larcv:0:8}-${md5_larcv:8:4}-${md5_larcv:12:4}-${md5_larcv:16:4}-${md5_larcv:20:12}
used_larcv_prebit=${used_larcv_hash:0:2}

# --- Build definitive filename ---
newLarcvFile=${excised_larcvFile%.root}-${used_larcv_hash}.root

# --- Rename on disk ---
mv ${larcvFile}  ${newLarcvFile}

echo -e "Definitive larcv name   : ${newLarcvFile}"

# =============================================================================
# STEP 5: Build SAMWeb JSON metadata file
# =============================================================================

LARCV_MD=md_larcv.json

touch ${LARCV_MD}

# --- Dataset tag preamble ---
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${SBNDCODE_VERSION}
export LARCV_DTAG=${DTAG_PREAMBLE}_larcv_sbnd

# Helper: build a single JSON file for one output
# Args: $1=md_file $2=filename $3=filesize $4=data_tier $5=file_format
#       $6=dataset_tag $7=process_name
build_json() {
    local mdFile=$1
    local fname=$2
    local fsize=$3
    local dtier=$4
    local ffmt=$5
    local dtag=$6
    local pname=$7

    echo -e "{"                                                                            >> ${mdFile}
    echo -e " \"file_name\": \"${fname}\","                                               >> ${mdFile}
    echo -e " \"file_size\": ${fsize},"                                                   >> ${mdFile}
    echo -e " \"data_tier\": \"${dtier}\","                                               >> ${mdFile}
    echo -e " \"file_format\": \"${ffmt}\","                                              >> ${mdFile}
    echo -e " \"checksum\": ["                                                            >> ${mdFile}
    echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${fname} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${mdFile}
    echo -e " ],"                                                                         >> ${mdFile}
    echo -e " \"Dataset.Tag\": \"${dtag}\","                                              >> ${mdFile}
    echo -e " \"process_id\": ${SAM_CONSUMER_ID},"                                       >> ${mdFile}
    echo -e " \"file_type\": \"mc\","                                                     >> ${mdFile}
    echo -e " \"group\": \"sbnd\","                                                       >> ${mdFile}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${mdFile}
    echo -e " \"art.file_format_era\": \"ART_2011a\","                                   >> ${mdFile}
    echo -e " \"art.file_format_version\": 15,"                                          >> ${mdFile}
    echo -e " \"art.run_type\": \"physics\","                                             >> ${mdFile}
    echo -e " \"art.process_name\": \"${pname}\","                                       >> ${mdFile}
    echo -e " \"fcl.name\": \"${fcl_list}\","                                            >> ${mdFile}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\","                            >> ${mdFile}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\","                            >> ${mdFile}
    echo -e " \"mc.generated_event_count\": ${MT_EVENTS_PER_JOB},"                      >> ${mdFile}
    echo -e " \"data_stream\": \"out1\","                                                 >> ${mdFile}
    echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\","                             >> ${mdFile}
    echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\","                     >> ${mdFile}
    echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\","                           >> ${mdFile}
    echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\","                        >> ${mdFile}
    echo -e " \"runs\": ["                                                                >> ${mdFile}
    echo -e "   ["                                                                        >> ${mdFile}
    echo -e "     ${run_no},"                                                             >> ${mdFile}
    echo -e "     ${subrun_no},"                                                          >> ${mdFile}
    echo -e "     \"physics\""                                                            >> ${mdFile}
    echo -e "   ]"                                                                        >> ${mdFile}
    echo -e " ],"                                                                         >> ${mdFile}
    echo -e " \"event_count\": ${event_count},"                                          >> ${mdFile}
    echo -e " \"first_event\": ${first_event},"                                          >> ${mdFile}
    echo -e " \"last_event\": ${last_event},"                                            >> ${mdFile}
    echo -e " \"parents\": ["                                                             >> ${mdFile}
    echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }"                                >> ${mdFile}
    echo -e "  ]"                                                                         >> ${mdFile}
    echo -e " }"                                                                          >> ${mdFile}
}

build_json ${LARCV_MD} "$(basename ${newLarcvFile})" "$(stat -c %s ${newLarcvFile})" "root-tuple"  "root"     "${LARCV_DTAG}" "Reco2"

# --- Print JSON to log for inspection ---
echo -e "Here is the larcv json...";  cat ${LARCV_MD}  | sed '/^$/d'

echo "Here are the contents of my workdir..."
ls -ltrh

# =============================================================================
# STEP 6: Retire any previously declared file with the same name (safety)
# =============================================================================
retire_if_exists() {
    local fname=$1
    local bname=$(basename ${fname})
    local checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata ${bname} 2>/dev/null)
    if [[ $? == 0 ]] ; then
        samweb -e ${SAM_EXPERIMENT} retire-file ${bname}
    fi
}

retire_if_exists ${newLarcvFile}

# =============================================================================
# STEP 7: Validate metadata
# =============================================================================
echo "Validating metadata..."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD}

# =============================================================================
# STEP 8 & 9: Copy, declare, and create dataset definition
#
# Output directory structure under IFDH_OUTPUT_DIR:
#   larcv/   <stream>/<hash_prefix>/   -- larcv file
# =============================================================================

# MT_SBND_STREAM_NAME comes from metadata_prescripts and pulls name from SAM PARENT FILE.
# Currently returns gen_g4_detsim, but for this stage we want it to say wiremod_larcv, so we hardcode it in
MT_SBND_STREAM_NAME_HARDCODED=wiremod_larcv
FULL_LARCV_OUTDIR=${IFDH_OUTPUT_DIR}/larcv/${MT_SBND_STREAM_NAME_HARDCODED}/${used_larcv_prebit}/

###### LARCV DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD} ; then
    ifdh cp -D ${newLarcvFile} ${FULL_LARCV_OUTDIR} && echo "COPIED larcv file to ${FULL_LARCV_OUTDIR}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${LARCV_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}
    samweb -e ${SAM_EXPERIMENT} create-definition ${LARCV_DTAG} "Dataset.Tag ${LARCV_DTAG}"
fi


echo -e "Done"
echo "$0 done"
