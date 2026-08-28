#!/bin/bash

# =============================================================================
# metadata_postscripts_sbnnusyst.sh
#
# Metadata postscript for the AR23+ CAF reprocessing (sbnnusyst) POMS stage.
# Bespoke script following the pattern of
# metadata_postscripts_onestage_Data_reco2_caf.sh, but for a single non-art
# output with MANY parents:
#
#   UpdateReweight -c Ar23+_knobs.ParamHeader.fcl -i input.list -o output.root
#
#   input.list  : xrootd URIs of ALL input caf files (built by
#                 metadata_prescripts_sbnnusyst.sh + mix_sbnnusyst.sh)
#   output.root : ONE flatcaf covering all of them
#
# What this script does, in order:
#   1. Sanity-check that output.root exists (i.e. UpdateReweight succeeded);
#      if not, bail out WITHOUT declaring anything and WITHOUT marking inputs
#      consumed, so the files stay recoverable in SAM.
#   2. Build the parent list from input.list (URI -> SAM basename).
#   3. Rename output.root with a unique md5-based UUID (avoids filename
#      collisions in dCache/SAMWeb).
#   4. Build the SAMWeb JSON metadata: runs and event_count are aggregated
#      from the parents' SAM metadata; all inputs are listed as parents.
#   5. Retire any previously declared file with the same name (safety).
#   6. Validate metadata, copy to dCache, declare, add location, and create
#      the dataset definition.
#   7. Mark the drained input files 'consumed' in SAM (the FIRST file in
#      input.list is handled by fife_wrap itself).
#
# Arg $1: the fcl list (recorded as fcl.name in the metadata).
#
# Env needed (set by cfg prescripts / fife_wrap):
#   MT_PRODUCTIONNAME MT_PRODUCTIONTYPE MT_PROJECTNAME MT_PROJECTSTAGE
#   MT_PROJECTSOFTWARE MT_PRODUCTIONLABEL MT_PROJECTVERSION MT_FCLNAME
#   MT_SAMPLE IFDH_OUTPUT_DIR SAM_EXPERIMENT SAM_CONSUMER_ID my_cpurl
# =============================================================================

>&2 echo -e "\n\nSTARTING $0...\n\n"

# Make sure the ifdh used by THIS script is v2_8_0: the older v2_7_2 fails
# against the current token-auth dCache doors (seen Jul 2026). ifdhc is the
# UPS product that provides the ifdh CLI.
source /cvmfs/larsoft.opensciencegrid.org/products/setup
setup ifdhc v2_8_0 -q e26:p3915:prof
echo "ifdh in use: $(command -v ifdh) (IFDHC_VERSION=${IFDHC_VERSION:-unset})"

fcl_list=$1
flatFile=output.root

>&2 echo -e "\n\nUsing fcl list ${fcl_list}...\n\n"

echo -e "Here is the contents of the dir BEFORE renaming..."
ls -ltrh

# =============================================================================
# STEP 1: Sanity check the output
# =============================================================================
if [[ ! -s ${flatFile} ]]; then
    echo -e "ERROR: ${flatFile} is missing or empty -- UpdateReweight did not succeed."
    echo -e "Not declaring anything and not marking inputs consumed."
    echo "$0 done (nothing declared)"
    return 1 2>/dev/null || exit 1
fi

if [[ ! -s input.list ]]; then
    echo -e "ERROR: input.list is missing or empty -- cannot build parentage."
    echo "$0 done (nothing declared)"
    return 1 2>/dev/null || exit 1
fi

# =============================================================================
# STEP 2: Parent list (SAM file names) from input.list (xrootd URIs)
# =============================================================================
sed 's|.*/||' input.list > parents.list
echo -e "Parents ($(wc -l < parents.list)):"
cat parents.list

# =============================================================================
# STEP 3: Compute md5 hash and build the unique output filename
#
# Format: <base_name>-<UUID>.flat.caf.root   (UUID = 8-4-4-4-12 hex groups)
# First 2 hex chars of the UUID are used as a dCache subdirectory prefix.
# =============================================================================
md5_flat=$(md5sum ${flatFile} | awk -F " " '{print $1}')
used_flat_hash=${md5_flat:0:8}-${md5_flat:8:4}-${md5_flat:12:4}-${md5_flat:16:4}-${md5_flat:20:12}
used_flat_prebit=${used_flat_hash:0:2}

flat_base=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${MT_PROJECTVERSION}_${MT_PROJECTSTAGE}
newFlatFile=${flat_base}-${used_flat_hash}.flat.caf.root

# remove previous flat files
find $(pwd) -iname '*.flat.caf.root' -delete
mv ${flatFile} ${newFlatFile}
echo -e "Definitive flatcaf name : ${newFlatFile}"

# =============================================================================
# STEP 4: Build the SAMWeb JSON metadata
#
# runs and event_count are aggregated from the parents' SAM metadata; the
# parent list can be hundreds of files, so the JSON is built in python.
# =============================================================================
export NEW_FLAT_FILE=${newFlatFile}
export FCL_LIST=${fcl_list}
export FLAT_DTAG=${MT_PRODUCTIONTYPE}_${MT_PRODUCTIONLABEL}_${MT_FCLNAME}_${MT_SAMPLE}_${MT_PROJECTVERSION}_flatcaf_sbnd

FLAT_MD=md_flat.json

PYTHON=$(command -v python3 || command -v python)
${PYTHON} <<'EOF'
import json
import os
import subprocess
import sys

def samweb(*args):
    cmd = ["samweb", "-e", os.environ.get("SAM_EXPERIMENT", "sbnd")] + list(args)
    out = subprocess.check_output(cmd)
    if not isinstance(out, str):
        out = out.decode()
    return out

parents = [l.strip() for l in open("parents.list") if l.strip()]

# Aggregate runs and event_count from the parents' SAM metadata
runs = []
seen = set()
event_count = 0
have_events = True
for p in parents:
    try:
        pmd = json.loads(samweb("get-metadata", "--json", p))
    except Exception as e:
        sys.stderr.write("WARNING: could not get metadata for %s: %s\n" % (p, e))
        have_events = False
        continue
    for r in pmd.get("runs", []):
        key = (r[0], r[1])
        if key not in seen:
            seen.add(key)
            runs.append(r)
    if "event_count" in pmd:
        event_count += pmd["event_count"]
    else:
        have_events = False

newfile = os.environ["NEW_FLAT_FILE"]

# checksum in samweb declare format, e.g. ["enstore:...", "adler32:...", "md5:..."]
ck = samweb("file-checksum", "--type=enstore,adler32,md5", newfile).strip()
try:
    checksums = json.loads(ck)
except ValueError:
    import ast
    checksums = ast.literal_eval(ck)

md = {
    "file_name": os.path.basename(newfile),
    "file_size": os.path.getsize(newfile),
    "data_tier": "flat_caf",
    "file_format": "flat_caf",
    "checksum": checksums,
    "Dataset.Tag": os.environ["FLAT_DTAG"],
    "file_type": "mc",
    "group": "sbnd",
    "application": {
        "family": "art",
        "name": os.environ.get("MT_PROJECTSOFTWARE", "sbnnusyst"),
        "version": os.environ.get("MT_PROJECTVERSION", ""),
    },
    "art.run_type": "physics",
    "art.process_name": "UpdateReweight",
    "fcl.name": os.environ.get("FCL_LIST", ""),
    "production.name": os.environ.get("MT_PRODUCTIONNAME", ""),
    "production.type": os.environ.get("MT_PRODUCTIONTYPE", ""),
    "data_stream": "out1",
    "sbnd_project.name": os.environ.get("MT_PROJECTNAME", ""),
    "sbnd_project.software": os.environ.get("MT_PROJECTSOFTWARE", ""),
    "sbnd_project.stage": os.environ.get("MT_PROJECTSTAGE", ""),
    "sbnd_project.version": os.environ.get("MT_PROJECTVERSION", ""),
    "runs": runs,
    "parents": [{"file_name": p} for p in parents],
}
if os.environ.get("SAM_CONSUMER_ID"):
    md["process_id"] = int(os.environ["SAM_CONSUMER_ID"])
if have_events:
    md["event_count"] = event_count

with open("md_flat.json", "w") as f:
    json.dump(md, f, indent=1)
print("Wrote md_flat.json")
EOF

if [[ ! -s ${FLAT_MD} ]]; then
    echo -e "ERROR: failed to build ${FLAT_MD}; not declaring."
    echo "$0 done (nothing declared)"
    return 1 2>/dev/null || exit 1
fi

echo -e "Here is the flatcaf json..."
cat ${FLAT_MD}
echo

# =============================================================================
# STEP 5: Retire any previously declared file with the same name (safety)
# =============================================================================
checkMeta=$(samweb -e ${SAM_EXPERIMENT} get-metadata $(basename ${newFlatFile}) 2>/dev/null)
if [[ $? == 0 ]] ; then
    samweb -e ${SAM_EXPERIMENT} retire-file $(basename ${newFlatFile})
fi

# =============================================================================
# STEP 6: Validate, copy, declare, add location, create dataset definition
# =============================================================================
FULL_FLAT_OUTDIR=${IFDH_OUTPUT_DIR}/flatcaf/${used_flat_prebit}/
# collapse any '//' in plain pnfs paths -- the token-auth dCache doors can be
# picky about them (skip URLs, where '//' after the scheme is meaningful)
if [[ ${FULL_FLAT_OUTDIR} == /* ]]; then
    FULL_FLAT_OUTDIR=$(echo ${FULL_FLAT_OUTDIR} | tr -s '/')
fi

# ifdh cp -D does NOT create missing destination directories; the prelaunch
# mkdir only creates outbase, not the flatcaf/<prebit>/ subdirectory.
echo "Ensuring output directory exists: ${FULL_FLAT_OUTDIR}"
ifdh mkdir_p ${FULL_FLAT_OUTDIR} || echo "WARNING: ifdh mkdir_p ${FULL_FLAT_OUTDIR} returned non-zero (may already exist)"

declared=0
if samweb -e ${SAM_EXPERIMENT} validate-metadata ${FLAT_MD} ; then
    if ifdh cp -D ${newFlatFile} ${FULL_FLAT_OUTDIR} ; then
        echo "COPIED flatcaf file to ${FULL_FLAT_OUTDIR}"
        if samweb -e ${SAM_EXPERIMENT} declare-file ${FLAT_MD} \
            && samweb -e ${SAM_EXPERIMENT} add-file-location $(basename ${newFlatFile}) dcache:${FULL_FLAT_OUTDIR} \
            && samweb -e ${SAM_EXPERIMENT} create-definition ${FLAT_DTAG} "Dataset.Tag ${FLAT_DTAG}" ; then
            declared=1
        else
            echo -e "ERROR: declare/add-location/create-definition failed."
        fi
    else
        echo -e "ERROR: ifdh cp of ${newFlatFile} failed; not declaring."
    fi
else
    echo -e "ERROR: metadata validation failed; not copying/declaring."
fi

# =============================================================================
# STEP 7: Mark the drained inputs 'consumed' in SAM
#
# The FIRST file in input.list is the one fife_wrap fetched itself; fife_wrap
# sets its final status (consumed/skipped) at the end of its file loop
# iteration, so we must NOT touch it here. Files 2..N were drained by
# mix_sbnnusyst.sh (status 'transferred') and are completed here.
# =============================================================================
if [[ ${declared} == 1 ]]; then
    tail -n +2 input.list | while read furi ; do
        ifdh updateFileStatus ${my_cpurl} ${SAM_CONSUMER_ID} $(basename ${furi}) consumed
    done
    echo -e "Marked $(( $(wc -l < input.list) - 1 )) drained input files consumed."
else
    echo -e "Declaration did not complete; leaving drained inputs 'transferred' for recovery."
fi

echo -e "Done"
echo "$0 done"
