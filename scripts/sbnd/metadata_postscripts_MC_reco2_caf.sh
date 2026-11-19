#!/bin/bash

# =============================================================================
# metadata_postscripts_MC_reco2_caf.sh
#
# Metadata postscript for the MC reco2_caf POMS stage
# (SBND2026A-MC-reco2_caf.cfg).
#
# Runs AFTER all executables (reco2 + caf) finish.
#
# Adapted from:
#   metadata_postscripts_MC_scrub_detsim_reco1_reco2_caf.sh (hist/caf/flatcaf handling)
#   metadata_postscripts_MC_wiremod_reco2_caf.sh            (fixed dCache subdirectory)
#
# Replaces metadata_postscripts_MC_reco2-caf.sh for this workflow. That script
# writes ${ md5_caf:0:8} (space after the brace), which bash rejects as a bad
# substitution and exits on, so nothing would be declared.
#
# Key differences from metadata_postscripts_MC_scrub_detsim_reco1_reco2_caf.sh:
#   - PARENT_FILE_SAM is the reco1 artroot input (set by metadata_prescripts.sh)
#   - Only hist/caf/flatcaf are produced; reco1/larcv come from the previous stage
#   - dCache subdirectory uses MT_PROJECTSTAGE instead of MT_SBND_STREAM_NAME
#
# What this script does, in order:
#   1. Find output files (hist, caf, flatcaf)
#   2. Read run/subrun/event info from the messages log
#   3. Read event_count from the hist JSON sidecar
#   4. Rename files with unique hashes (avoids filename collisions in dCache)
#   5. Build a SAMWeb JSON metadata file for each output
#   6. Retire any previously declared file with the same name (safety)
#   7. Validate metadata with SAMWeb
#   8. Copy, declare, and add locations to SAMWeb
#   9. Create SAMWeb dataset definitions
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

# PARENT_FILE_SAM is set by metadata_prescripts.sh (run during job setup).
# It contains the SAM filename of the reco1 input file for this job.
# All outputs list this file as their parent.
initialFile=$(basename ${PARENT_FILE_SAM})

# Output file variables -- populated by find commands below
histFile=''    # Calib ntuples (hist_ from reco2 via -T)
cafFile=''     # CAF tree
flatFile=''    # Flat CAF tree

>&2 echo -e "\n\nUsing fcl list $1...\n\n"
>&2 echo -e "\n\nParent reco1 file: ${initialFile}\n\n"

# =============================================================================
# STEP 1: Find output files
#
# reco2.root is an intermediate -- left in the working directory and
# discarded on exit.
# =============================================================================

# hist file: produced by reco2 via the -T flag (TFileService output)
histFile=$(find ./ -iname 'hist*.root' | grep 'reco2' | head -n 1)

# CAF file: ends in caf.root but NOT flat.caf.root
cafFile=$(find ./ -iname '*caf.root' | grep -v 'flat' | grep -v 'hist' | grep -v 'reco')

# Flat CAF file: ends in flat.caf.root or .flat.caf.root
flatFile=$(find ./ -iname '*.caf.root' | grep 'flat')

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

echo -e "histFile  : ${histFile}"
echo -e "cafFile   : ${cafFile}"
echo -e "flatFile  : ${flatFile}"

# All three outputs are required -- stop before md5sum/mv run on empty names.
# 'return' because this file is sourced.
if [[ -z ${histFile} || -z ${cafFile} || -z ${flatFile} ]]; then
    >&2 echo -e "ERROR: missing hist/caf/flatcaf output, nothing will be declared."
    return 1
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
# STEP 3: Get event_count from the hist JSON sidecar
#
# sbnpoms_metadata_injector.sh (prescript_7) produces this JSON sidecar
# alongside the hist_ file from the reco2 step, named <histFile>.json.
# =============================================================================
json_file="${histFile}.json"
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

echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_caf=$(md5sum ${cafFile}  | awk -F " " '{print $1}')
echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

# --- Strip any existing UUID hash from filename (in case of reprocessing) ---
old_hist_hash=$(echo ${histFile}  | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_histFile=${histFile%-${old_hist_hash}*}
old_caf_hash=$(echo ${cafFile}    | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_cafFile=${cafFile%-${old_caf_hash}*}
old_flat_hash=$(echo ${flatFile}  | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_flatFile=${flatFile%-${old_flat_hash}*}

# --- Format md5 as UUID (8-4-4-4-12) ---
used_hist_hash=${md5_hist:0:8}-${md5_hist:8:4}-${md5_hist:12:4}-${md5_hist:16:4}-${md5_hist:20:12}
used_caf_hash=${md5_caf:0:8}-${md5_caf:8:4}-${md5_caf:12:4}-${md5_caf:16:4}-${md5_caf:20:12}
used_flat_hash=${md5_flat:0:8}-${md5_flat:8:4}-${md5_flat:12:4}-${md5_flat:16:4}-${md5_flat:20:12}

used_hist_prebit=${used_hist_hash:0:2}
used_caf_prebit=${used_caf_hash:0:2}
used_flat_prebit=${used_flat_hash:0:2}

# --- Build definitive filenames ---
newHistFile=${excised_histFile%.root}-${used_hist_hash}.root
newCafFile=${excised_cafFile%.root}-${used_caf_hash}.caf.root
newFlatFile=${excised_flatFile%.root}-${used_flat_hash}.flat.caf.root

# --- Rename on disk ---
mv ${histFile}  ${newHistFile}
mv ${cafFile}   ${newCafFile}
mv ${flatFile}  ${newFlatFile}

echo -e "Definitive hist name  : ${newHistFile}"
echo -e "Definitive caf name   : ${newCafFile}"
echo -e "Definitive flat name  : ${newFlatFile}"

# =============================================================================
# STEP 5: Build SAMWeb JSON metadata files
# =============================================================================

HIST_MD=md_hist.json
CAF_MD=md_caf.json
FLAT_MD=md_flat.json

touch ${HIST_MD}; touch ${CAF_MD}; touch ${FLAT_MD}

# --- Dataset tag preamble ---
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${SBNDCODE_VERSION}
export HIST_DTAG=${DTAG_PREAMBLE}_histreco2_sbnd
export CAF_DTAG=${DTAG_PREAMBLE}_caf_sbnd
export FLAT_DTAG=${DTAG_PREAMBLE}_flatcaf_sbnd

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

build_json ${HIST_MD} "$(basename ${newHistFile})" "$(stat -c %s ${newHistFile})" "root-tuple"  "root"     "${HIST_DTAG}" "Reco2"
build_json ${CAF_MD}  "$(basename ${newCafFile})"  "$(stat -c %s ${newCafFile})"  "caf"         "caf"      "${CAF_DTAG}"  "CAF"
build_json ${FLAT_MD} "$(basename ${newFlatFile})" "$(stat -c %s ${newFlatFile})" "flat_caf"    "flat_caf" "${FLAT_DTAG}" "CAF"

# --- Print JSONs to log for inspection ---
echo -e "Here is the hist json...";  cat ${HIST_MD}  | sed '/^$/d'
echo -e "Here is the caf json...";   cat ${CAF_MD}   | sed '/^$/d'
echo -e "Here is the flat json...";  cat ${FLAT_MD}  | sed '/^$/d'

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

retire_if_exists ${newHistFile}
retire_if_exists ${newCafFile}
retire_if_exists ${newFlatFile}

# =============================================================================
# STEP 7: Validate metadata
# =============================================================================
echo "Validating metadata..."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD}

# =============================================================================
# STEP 8 & 9: Copy, declare, and create dataset definitions
#
# Output directory structure under IFDH_OUTPUT_DIR:
#   calib/   <stage>/<hash_prefix>/   -- hist_ files
#   caf/     <stage>/<hash_prefix>/   -- caf files
#   flatcaf/ <stage>/<hash_prefix>/   -- flat caf files
#
# <stage> is MT_PROJECTSTAGE (reco2_caf). MT_SBND_STREAM_NAME is not used:
# metadata_prescripts.sh builds it from a '_strm' token in the parent filename,
# which MC inputs don't have (same reason the wiremod postscripts hardcode it).
# =============================================================================

FULL_HIST_OUTDIR=${IFDH_OUTPUT_DIR}/calib/${MT_PROJECTSTAGE}/${used_hist_prebit}/
FULL_CAF_OUTDIR=${IFDH_OUTPUT_DIR}/caf/${MT_PROJECTSTAGE}/${used_caf_prebit}/
FULL_FLAT_OUTDIR=${IFDH_OUTPUT_DIR}/flatcaf/${MT_PROJECTSTAGE}/${used_flat_prebit}/

###### HIST (calib ntuple) DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD} ; then
    ifdh cp -D ${newHistFile} ${FULL_HIST_OUTDIR} && echo "COPIED hist file to ${FULL_HIST_OUTDIR}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${HIST_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newHistFile}) dcache:${FULL_HIST_OUTDIR}
    samweb -e ${SAM_EXPERIMENT} create-definition ${HIST_DTAG} "Dataset.Tag ${HIST_DTAG}"
fi

###### CAF DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD} ; then
    ifdh cp -D ${newCafFile} ${FULL_CAF_OUTDIR} && echo "COPIED caf file to ${FULL_CAF_OUTDIR}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${CAF_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newCafFile}) dcache:${FULL_CAF_OUTDIR}
    samweb -e ${SAM_EXPERIMENT} create-definition ${CAF_DTAG} "Dataset.Tag ${CAF_DTAG}"
fi

###### FLAT CAF DECLARATION ######
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD} ; then
    ifdh cp -D ${newFlatFile} ${FULL_FLAT_OUTDIR} && echo "COPIED flatcaf file to ${FULL_FLAT_OUTDIR}"
    samweb -e ${SAM_EXPERIMENT} declare-file ${FLAT_MD}
    samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR}
    samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_DTAG} "Dataset.Tag ${FLAT_DTAG}"
fi

echo -e "Done"
echo "$0 done"
