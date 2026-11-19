#!/bin/bash

# =============================================================================
# metadata_postscripts_MC_g4_detsim_reco1.sh
#
# Metadata postscript for the MC g4_detsim_reco1 POMS stage
# (SBND2026A-MC-g4_detsim_reco1.cfg).
#
# Runs AFTER all executables (g4 + detsim + reco1) finish.
#
# Adapted from:
#   metadata_postscripts_MC_scrub_detsim_reco1_reco2_caf.sh (reco1/larcv handling)
#   metadata_postscripts_MC_LArCV_wiremod.sh                (stage with no reco2/caf)
#
# Key differences from metadata_postscripts_MC_scrub_detsim_reco1_reco2_caf.sh:
#   - PARENT_FILE_SAM is the gen-tier artroot input (set by metadata_prescripts.sh)
#   - Only reco1 and larcv are produced; there is no hist/caf/flatcaf here
#   - reco1 is always saved: it is the input to the reco2_caf stage
#   - larcv saving is conditional on SAVE_LARCV (default: 1), and is skipped
#     with a warning if reco1 wrote no larcv file
#   - event_count is read from hist_<mdprojectstage>.root.json
#   - dCache subdirectory uses MT_PROJECTSTAGE instead of MT_SBND_STREAM_NAME
#
# What this script does, in order:
#   1. Find output files (reco1, larcv)
#   2. Read run/subrun/event info from the messages log
#   3. Read event_count from the JSON sidecar
#   4. Rename files with unique hashes (avoids filename collisions in dCache)
#   5. Build a SAMWeb JSON metadata file for each output
#   6. Retire any previously declared file with the same name (safety)
#   7. Validate metadata with SAMWeb
#   8. Copy, declare, and add locations to SAMWeb
#   9. Create SAMWeb dataset definitions
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

# PARENT_FILE_SAM is set by metadata_prescripts.sh (run during job setup).
# It contains the SAM filename of the gen-tier input file for this job.
# All outputs list this file as their parent.
initialFile=$(basename ${PARENT_FILE_SAM})

# On/off switch (read from env, default to 1 = save)
SAVE_LARCV=${SAVE_LARCV:-1}

# Output file variables -- populated by find commands below
reco1File=''   # Artroot reco1 file
larcvFile=''   # LarCV file (secondary stream from reco1 step)

>&2 echo -e "\n\nUsing fcl list $1...\n\n"
>&2 echo -e "\n\nParent gen-input file: ${initialFile}\n\n"
>&2 echo -e "\n\nSAVE_LARCV=${SAVE_LARCV}\n\n"

# =============================================================================
# STEP 1: Find output files
#
# g4 and detsim intermediates (g4.root, g4_detsim.root) are not handled
# here -- they are left in the working directory and discarded on exit.
# =============================================================================

# reco1 file: g4_detsim_reco1.root (contains 'reco1', excludes hist/larcv/reco2/caf)
reco1File=$(find ./ -iname '*.root' | grep 'reco1' | grep -v 'larcv' | grep -v 'hist' | grep -v 'reco2' | grep -v 'caf')

# larcv file: secondary output stream from reco1 step, named larcv*.root
larcvFile=$(find ./ -iname 'larcv*.root' | grep -v 'reco2')

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

echo -e "reco1File : ${reco1File}"
echo -e "larcvFile : ${larcvFile}"

# reco1 is the whole point of this stage -- stop here if it is missing,
# rather than declaring half-built metadata. 'return' because this file is sourced.
if [[ -z ${reco1File} ]]; then
    >&2 echo -e "ERROR: no reco1 file found, nothing will be declared."
    return 1
fi

# Don't let md5sum/mv run on an empty name if reco1 made no larcv stream
if [[ ${SAVE_LARCV} == 1 && -z ${larcvFile} ]]; then
    >&2 echo -e "WARNING: SAVE_LARCV=1 but no larcv*.root found; skipping larcv."
    SAVE_LARCV=0
fi

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
# STEP 3: Get event_count from the JSON sidecar
#
# sbnpoms_metadata_injector.sh (prescript_8, on the reco1 wrapper) produces
# this sidecar, named hist_<mdprojectstage>.root.json.
# =============================================================================
json_file="hist_${MT_PROJECTSTAGE}.root.json"
event_count=$(grep '"event_count":' "$json_file" | head -1 | sed 's/.*"event_count": *//' | sed 's/[^0-9].*//')
[[ -z ${event_count} ]] && >&2 echo -e "WARNING: no event_count read from ${json_file}; metadata validation will fail."

# The fcl list is passed as argument $1 from the cfg postscript line
fcl_list=$1

# =============================================================================
# STEP 4: Compute md5 hashes and build unique filenames
#
# Format: <base_name>-<UUID>.root   (UUID = 8-4-4-4-12 hex groups)
# First 2 hex chars of UUID are used as a dCache subdirectory prefix.
# =============================================================================

# --- reco1 (always) ---
echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_reco1=$(md5sum ${reco1File} | awk -F " " '{print $1}')

old_reco1_hash=$(echo ${reco1File} | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_reco1File=${reco1File%-${old_reco1_hash}*}

used_reco1_hash=${md5_reco1:0:8}-${md5_reco1:8:4}-${md5_reco1:12:4}-${md5_reco1:16:4}-${md5_reco1:20:12}
used_reco1_prebit=${used_reco1_hash:0:2}

newReco1File=${excised_reco1File%.root}-${used_reco1_hash}.root
mv ${reco1File} ${newReco1File}
echo -e "Definitive reco1 name : ${newReco1File}"

# --- larcv (conditional) ---
if [[ ${SAVE_LARCV} == 1 ]]; then
    echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
    md5_larcv=$(md5sum ${larcvFile} | awk -F " " '{print $1}')

    old_larcv_hash=$(echo ${larcvFile} | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
    excised_larcvFile=${larcvFile%-${old_larcv_hash}*}

    used_larcv_hash=${md5_larcv:0:8}-${md5_larcv:8:4}-${md5_larcv:12:4}-${md5_larcv:16:4}-${md5_larcv:20:12}
    used_larcv_prebit=${used_larcv_hash:0:2}

    newLarcvFile=${excised_larcvFile%.root}-${used_larcv_hash}.root
    mv ${larcvFile} ${newLarcvFile}
    echo -e "Definitive larcv name : ${newLarcvFile}"
else
    echo -e "larcv: SAVE_LARCV=0, skipping"
fi

# =============================================================================
# STEP 5: Build SAMWeb JSON metadata files
# =============================================================================

RECO1_MD=md_reco1.json ; touch ${RECO1_MD}
if [[ ${SAVE_LARCV} == 1 ]]; then LARCV_MD=md_larcv.json ; touch ${LARCV_MD} ; fi

# --- Dataset tags ---
# The reco1 tag is what the reco2_caf stage uses as its input dataset.
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${SBNDCODE_VERSION}
export RECO1_DTAG=${DTAG_PREAMBLE}_reco1_sbnd
export LARCV_DTAG=${DTAG_PREAMBLE}_larcvreco1_sbnd

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

build_json ${RECO1_MD} "$(basename ${newReco1File})" "$(stat -c %s ${newReco1File})" "reconstructed" "artroot" "${RECO1_DTAG}" "Reco1"

if [[ ${SAVE_LARCV} == 1 ]]; then
    build_json ${LARCV_MD} "$(basename ${newLarcvFile})" "$(stat -c %s ${newLarcvFile})" "larcv" "larcv" "${LARCV_DTAG}" "Reco1"
fi

# --- Print JSONs to log for inspection ---
echo -e "Here is the reco1 json..."; cat ${RECO1_MD} | sed '/^$/d'
[[ ${SAVE_LARCV} == 1 ]] && { echo -e "Here is the larcv json..."; cat ${LARCV_MD} | sed '/^$/d'; }

echo "Here are the contents of my workdir..."
ls -ltrh

# =============================================================================
# STEP 6: Retire any previously declared files with the same name (safety)
# =============================================================================
retire_if_exists() {
    local fname=$1
    local bname=$(basename ${fname})
    local checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata ${bname} 2>/dev/null)
    if [[ $? == 0 ]] ; then
        samweb -e ${SAM_EXPERIMENT} retire-file ${bname}
    fi
}

retire_if_exists ${newReco1File}
[[ ${SAVE_LARCV} == 1 ]] && retire_if_exists ${newLarcvFile}

# =============================================================================
# STEP 7: Validate metadata
# =============================================================================
echo "Validating metadata..."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${RECO1_MD}
[[ ${SAVE_LARCV} == 1 ]] && samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD}

# =============================================================================
# STEP 8 & 9: Copy, declare, and create dataset definitions
#
# Output directory structure under IFDH_OUTPUT_DIR:
#   reco1/ <stage>/<hash_prefix>/   -- reco1 files
#   larcv/ <stage>/<hash_prefix>/   -- larcv files (if SAVE_LARCV=1)
#
# <stage> is MT_PROJECTSTAGE (g4_detsim_reco1). MT_SBND_STREAM_NAME is not
# used: metadata_prescripts.sh builds it from a '_strm' token in the parent
# filename, which MC inputs don't have (same reason the wiremod postscripts
# hardcode it).
# =============================================================================

FULL_RECO1_OUTDIR=${IFDH_OUTPUT_DIR}/reco1/${MT_PROJECTSTAGE}/${used_reco1_prebit}/

###### RECO1 DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${RECO1_MD} ; then
    ifdh cp -D ${newReco1File} ${FULL_RECO1_OUTDIR} && echo "COPIED reco1 file to ${FULL_RECO1_OUTDIR}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${RECO1_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newReco1File}) dcache:${FULL_RECO1_OUTDIR}
    samweb -e ${SAM_EXPERIMENT} create-definition ${RECO1_DTAG} "Dataset.Tag ${RECO1_DTAG}"
fi

###### LARCV DECLARATION (conditional) ######
if [[ ${SAVE_LARCV} == 1 ]]; then
    FULL_LARCV_OUTDIR=${IFDH_OUTPUT_DIR}/larcv/${MT_PROJECTSTAGE}/${used_larcv_prebit}/
    if samweb -e ${SAM_EXPERIMENT} validate-metadata ${LARCV_MD} ; then
        ifdh cp -D ${newLarcvFile} ${FULL_LARCV_OUTDIR} && echo "COPIED larcv file to ${FULL_LARCV_OUTDIR}"
        samweb -e ${SAM_EXPERIMENT} declare-file ${LARCV_MD}
        samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newLarcvFile}) dcache:${FULL_LARCV_OUTDIR}
        samweb -e ${SAM_EXPERIMENT} create-definition ${LARCV_DTAG} "Dataset.Tag ${LARCV_DTAG}"
    fi
else
    echo "SAVE_LARCV=0: skipping larcv copy/declare"
fi

echo -e "Done"
echo "$0 done"
