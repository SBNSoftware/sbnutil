#!/bin/bash

# =============================================================================
# metadata_postscripts_MC_reco2-caf.sh
#
# Metadata postscript for the MC reco2_caf single POMS stage.
#
# Runs AFTER all executables (reco2 + caf) finish on the worker node.
#
# Adapted from: metadata_postscripts_MC_onestage.sh
# Key differences from the original:
#   - Input is a reco1 artroot file, not a gen FCL
#     so PARENT_FILE_SAM (set by metadata_prescripts.sh) already points to
#     the reco1 file -- we just use it directly as parent for all outputs
#   - We only handle 3 output types: hist_ (calib ntuples), caf, flatcaf
#   - Removed: detsim, reco1, larcv (not produced in this stage)
#   - event_count is read from hist_reco2_caf.root.json (not gen JSON)
#
# What this script does, in order:
#   1. Find the 3 output files
#   2. Read run/subrun/event info from the messages log
#   3. Rename files with unique hashes (avoids filename collisions in dCache)
#   4. Build a SAMWeb JSON metadata file for each output
#   5. Validate metadata with SAMWeb
#   6. Retire any previously declared file with the same name (safety)
#   7. Copy files to permanent dCache storage with ifdh
#   8. Declare files to SAMWeb and add their dCache locations
#   9. Create SAMWeb dataset definitions
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

# PARENT_FILE_SAM is set by metadata_prescripts.sh (run during job setup).
# It contains the SAM filename of the reco1 input file for this job.
# All three outputs (hist_, caf, flatcaf) will list this as their parent.
initialFile=$(basename ${PARENT_FILE_SAM})

# Output file variables -- will be populated by find commands below
histFile=''   # Calib ntuples (hist_ from reco2)
cafFile=''    # CAF tree
flatFile=''   # Flat CAF tree

>&2 echo -e "\n\nUsing fcl list $1...\n\n"
>&2 echo -e "\n\nParent reco1 file: ${initialFile}\n\n"

# =============================================================================
# STEP 1: Find output files
# We use find + grep to locate each file type by naming convention.
# The grep -v flags exclude files that match other types to avoid ambiguity.
# =============================================================================

# hist_ file: produced by reco2 via the -T flag (TFileService histogram output)
# grep 'reco2' ensures we get the reco2 hist, not any stray hist files
histFile=$(find ./ -iname 'hist*.root' | grep 'reco2' | head -n 1)

# CAF file: ends in caf.root but NOT flat.caf.root
cafFile=$(find ./ -iname '*caf.root' | grep -v 'flat')

# Flat CAF file: ends in flat.caf.root or .flat.caf.root
flatFile=$(find ./ -iname '*.caf.root' | grep 'flat')

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

echo -e "histFile : ${histFile}"
echo -e "cafFile  : ${cafFile}"
echo -e "flatFile : ${flatFile}"

# =============================================================================
# STEP 2: Get run/subrun/event info from the messages log
#
# art writes lines like: " run: 1 subRun: 0 event: 42" to messages.log
# We parse these to find the first and last event processed.
# This is admittedly a bit brutal but it works reliably across art versions.
# =============================================================================
source_log=messages.log

# Find all unique run/subrun/event tokens, sort by event number, take first/last
first_token=$(cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5n  | head -n 1)
last_token=$( cat ${source_log} | grep -e 'run:' | grep -e 'event:' | grep -v '.cc' | awk -F " run: " '{print $2}' | sed -e 's/^ //' | sort -u | grep -e 'event' | sort -k5,5nr | head -n 1)

run_no=$(    echo ${first_token} | awk -F " " '{print $1}')
subrun_no=$( echo ${first_token} | awk -F " " '{print $3}')
first_event=$(echo ${first_token} | awk -F " " '{print $5}')
last_event=$( echo ${last_token}  | awk -F " " '{print $5}')

# =============================================================================
# STEP 3: Get event_count from the hist JSON sidecar
#
# sbnpoms_metadata_injector.sh (run during prescripts) produces a JSON file
# alongside the hist_ root file. We extract event_count from it.
# Note: unlike the full pipeline which reads from hist_gen_g4_...json,
# here we read from hist_reco2_caf.root.json
# =============================================================================
json_file="hist_reco2_caf.root.json"
event_count=$(grep '"event_count":' "$json_file" | head -1 | sed 's/.*"event_count": *//' | sed 's/[^0-9].*//')

# The fcl list is passed as argument $1 from the cfg postscript line
fcl_list=$1

# =============================================================================
# STEP 4: Rename files with unique hashes
#
# Files are renamed to include an md5-based UUID so that filenames are
# globally unique in dCache and SAMWeb. Without this, reprocessing the same
# input could produce filename collisions.
#
# Process:
#   a) compute md5sum of the file
#   b) mix in some $RANDOM values for extra uniqueness
#   c) format the hash as a UUID (8-4-4-4-12 hex groups)
#   d) strip any existing hash suffix from the filename
#   e) append the new hash to get the definitive filename
# =============================================================================

# --- Compute md5 hashes ---
echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_hist=$(md5sum ${histFile} | awk -F " " '{print $1}')
echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_caf=$( md5sum ${cafFile}  | awk -F " " '{print $1}')
echo $RANDOM > hmd.log ; echo $RANDOM >> hmd.log ; echo $RANDOM >> hmd.log
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')

# --- Strip any existing UUID hash from filename (in case of reprocessing) ---
old_hist_hash=$(echo ${histFile} | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_histFile=${histFile%-${old_hist_hash}*}

old_caf_hash=$(echo ${cafFile} | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_cafFile=${cafFile%-${old_caf_hash}*}

old_flat_hash=$(echo ${flatFile} | sed -E 's/.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/\1/')
excised_flatFile=${flatFile%-${old_flat_hash}*}

# --- Format md5 as UUID (8-4-4-4-12) ---
used_hist_hash=${md5_hist:0:8}-${md5_hist:8:4}-${md5_hist:12:4}-${md5_hist:16:4}-${md5_hist:20:12}
used_caf_hash=${ md5_caf:0:8}-${ md5_caf:8:4}-${ md5_caf:12:4}-${ md5_caf:16:4}-${ md5_caf:20:12}
used_flat_hash=${md5_flat:0:8}-${md5_flat:8:4}-${md5_flat:12:4}-${md5_flat:16:4}-${md5_flat:20:12}

# First 2 hex chars of hash used as a subdirectory prefix in dCache
# (standard practice to avoid too many files in one directory)
used_hist_prebit=${used_hist_hash:0:2}
used_caf_prebit=${ used_caf_hash:0:2}
used_flat_prebit=${used_flat_hash:0:2}

# --- Build definitive filenames ---
newHistFile=${excised_histFile%.root}-${used_hist_hash}.root
newCafFile=${excised_cafFile%.root}-${used_caf_hash}.caf.root
newFlatFile=${excised_flatFile%.root}-${used_flat_hash}.flat.caf.root

# --- Rename on disk ---
mv ${histFile} ${newHistFile}
mv ${cafFile}  ${newCafFile}
mv ${flatFile} ${newFlatFile}

echo -e "Definitive hist name : ${newHistFile}"
echo -e "Definitive caf name  : ${newCafFile}"
echo -e "Definitive flat name : ${newFlatFile}"

# =============================================================================
# STEP 5: Build SAMWeb JSON metadata files
#
# SAMWeb requires a JSON file describing each output file before it can be
# declared. We build these manually because we need fine-grained control
# over fields like data_tier, parents, and dataset tags.
#
# Each JSON file covers: file_name, file_size, data_tier, file_format,
# checksum, Dataset.Tag, process_id, file_type, application, run info,
# event counts, fcl list, production metadata, and parent file.
# =============================================================================

HIST_MD=md_hist.json
CAF_MD=md_caf.json
FLAT_MD=md_flat.json

touch ${HIST_MD}; touch ${CAF_MD}; touch ${FLAT_MD}

# Open JSON objects
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e "{" >> ${mdFile}
done

# --- File names ---
echo -e " \"file_name\": \"$(basename ${newHistFile})\"," >> ${HIST_MD}
echo -e " \"file_name\": \"$(basename ${newCafFile})\","  >> ${CAF_MD}
echo -e " \"file_name\": \"$(basename ${newFlatFile})\"," >> ${FLAT_MD}

# --- File sizes (bytes) ---
echo -e " \"file_size\": $(stat -c %s ${newHistFile})," >> ${HIST_MD}
echo -e " \"file_size\": $(stat -c %s ${newCafFile}),"  >> ${CAF_MD}
echo -e " \"file_size\": $(stat -c %s ${newFlatFile})," >> ${FLAT_MD}

# --- Data tiers ---
# root-tuple: histogram/ntuple files (not full artroot event records)
# caf / flat_caf: Common Analysis Format files
echo -e " \"data_tier\": \"root-tuple\"," >> ${HIST_MD}
echo -e " \"data_tier\": \"caf\","        >> ${CAF_MD}
echo -e " \"data_tier\": \"flat_caf\","   >> ${FLAT_MD}

# --- File formats ---
echo -e " \"file_format\": \"root\","     >> ${HIST_MD}
echo -e " \"file_format\": \"caf\","      >> ${CAF_MD}
echo -e " \"file_format\": \"flat_caf\"," >> ${FLAT_MD}

# --- Checksums ---
# SAMWeb stores multiple checksum types for integrity verification
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"checksum\": [" >> ${mdFile}
done
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newHistFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${HIST_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newCafFile}  | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${CAF_MD}
echo -e "$(samweb -e ${SAM_EXPERIMENT} file-checksum --type=enstore,adler32,md5 ${newFlatFile} | tr -d '[' | tr -d ']' | tr ' ' '\n')" >> ${FLAT_MD}
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " ]," >> ${mdFile}
done

# --- Dataset tags ---
# DTAG_PREAMBLE: shared prefix for all dataset tags in this job
# These tags are used to create SAMWeb dataset definitions at the end
export DTAG_PREAMBLE=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${SBNDCODE_VERSION}
export HIST_DTAG=${DTAG_PREAMBLE}_histreco2_sbnd
export CAF_DTAG=${DTAG_PREAMBLE}_caf_sbnd
export FLAT_DTAG=${DTAG_PREAMBLE}_flatcaf_sbnd

echo -e " \"Dataset.Tag\": \"${HIST_DTAG}\"," >> ${HIST_MD}
echo -e " \"Dataset.Tag\": \"${CAF_DTAG}\","  >> ${CAF_MD}
echo -e " \"Dataset.Tag\": \"${FLAT_DTAG}\"," >> ${FLAT_MD}

# --- Common fields for all three files ---
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"process_id\": ${SAM_CONSUMER_ID},"   >> ${mdFile}
    echo -e " \"file_type\": \"mc\","                 >> ${mdFile}
    echo -e " \"group\": \"sbnd\","                   >> ${mdFile}
    echo -e " \"application\": {\n\t\"family\": \"art\",\n\t\"name\": \"sbndcode\",\n\t\"version\": \"${SBNDCODE_VERSION}\"\n }," >> ${mdFile}
    echo -e " \"art.file_format_era\": \"ART_2011a\"," >> ${mdFile}
    echo -e " \"art.file_format_version\": 15,"        >> ${mdFile}
    echo -e " \"art.run_type\": \"physics\","           >> ${mdFile}
done

# --- Process names (stage that produced each file) ---
echo -e " \"art.process_name\": \"Reco2\"," >> ${HIST_MD}
echo -e " \"art.process_name\": \"CAF\","   >> ${CAF_MD}
echo -e " \"art.process_name\": \"CAF\","   >> ${FLAT_MD}

# --- Remaining common fields ---
for mdFile in ${HIST_MD} ${CAF_MD} ${FLAT_MD} ; do
    echo -e " \"fcl.name\": \"${fcl_list}\","                       >> ${mdFile}
    echo -e " \"production.name\": \"${MT_PRODUCTIONNAME}\","        >> ${mdFile}
    echo -e " \"production.type\": \"${MT_PRODUCTIONTYPE}\","        >> ${mdFile}
    echo -e " \"mc.generated_event_count\": ${MT_EVENTS_PER_JOB},"  >> ${mdFile}
    echo -e " \"data_stream\": \"out1\","                            >> ${mdFile}
    echo -e " \"sbnd_project.name\": \"${MT_PROJECTNAME}\","         >> ${mdFile}
    echo -e " \"sbnd_project.software\": \"${MT_PROJECTSOFTWARE}\"," >> ${mdFile}
    echo -e " \"sbnd_project.stage\": \"${MT_PROJECTSTAGE}\","       >> ${mdFile}
    echo -e " \"sbnd_project.version\": \"${SBNDCODE_VERSION}\","    >> ${mdFile}
    echo -e " \"runs\": ["       >> ${mdFile}
    echo -e "   ["               >> ${mdFile}
    echo -e "     ${run_no},"    >> ${mdFile}
    echo -e "     ${subrun_no}," >> ${mdFile}
    echo -e "     \"physics\""   >> ${mdFile}
    echo -e "   ]"               >> ${mdFile}
    echo -e " ],"                >> ${mdFile}
    echo -e " \"event_count\": ${event_count},"   >> ${mdFile}
    echo -e " \"first_event\": ${first_event},"   >> ${mdFile}
    echo -e " \"last_event\": ${last_event},"     >> ${mdFile}
    # Parent: the reco1 input file that SAM delivered to this job.
    # PARENT_FILE_SAM was set by metadata_prescripts.sh during job setup.
    # This is the key difference from the full MC pipeline: instead of the
    # gen FCL being the parent, the actual reco1 artroot file is the parent.
    echo -e " \"parents\": ["                                         >> ${mdFile}
    echo -e "\t{ \"file_name\": \"${PARENT_FILE_SAM}\" }"            >> ${mdFile}
    echo -e "  ]"                                                     >> ${mdFile}
    echo -e " }"                                                      >> ${mdFile}
done

# --- Print JSONs to log for inspection ---
echo -e "Here is the hist json...";  cat ${HIST_MD} | sed '/^$/d'
echo -e "Here is the caf json...";   cat ${CAF_MD}  | sed '/^$/d'
echo -e "Here is the flat json...";  cat ${FLAT_MD} | sed '/^$/d'

echo "Here are the contents of my workdir..."
ls -ltrh

# =============================================================================
# STEP 6: Retire any previously declared files with the same name (safety)
# If a file with this name was declared to SAMWeb before (e.g. from a failed
# prior job), retire it first to avoid declaration conflicts.
# =============================================================================
for fname in $(basename $newHistFile) $(basename $newCafFile) $(basename $newFlatFile) ; do
    checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata ${fname} 2>/dev/null)
    if [[ $? == 0 ]] ; then
        samweb -e ${SAM_EXPERIMENT} retire-file ${fname}
    fi
done

# =============================================================================
# STEP 7: Validate metadata
# SAMWeb checks that all required fields are present and correctly formatted.
# If validation fails, we do not attempt to copy or declare the file.
# =============================================================================
echo "Validating metadata..."
samweb -e ${SAM_EXPERIMENT} validate-metadata ${HIST_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${CAF_MD}
samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD}

# =============================================================================
# STEP 8 & 9: Copy, declare, and create dataset definitions
#
# Output directory structure under IFDH_OUTPUT_DIR:
#   calib/  <stream>/<hash_prefix>/   <-- hist_ files
#   caf/    <stream>/<hash_prefix>/   <-- caf files
#   flatcaf/<stream>/<hash_prefix>/   <-- flat caf files
#
# MT_SBND_STREAM_NAME is set by metadata_prescripts.sh
# hash prefix (first 2 chars of UUID) keeps directory sizes manageable
# =============================================================================

FULL_HIST_OUTDIR=${IFDH_OUTPUT_DIR}/calib/${MT_SBND_STREAM_NAME}/${used_hist_prebit}/
FULL_CAF_OUTDIR=${IFDH_OUTPUT_DIR}/caf/${MT_SBND_STREAM_NAME}/${used_caf_prebit}/
FULL_FLAT_OUTDIR=${IFDH_OUTPUT_DIR}/flatcaf/${MT_SBND_STREAM_NAME}/${used_flat_prebit}/

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