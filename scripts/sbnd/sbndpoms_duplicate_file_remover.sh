#! /bin/bash
# Script to find, delete and retire duplicate files

#$1 The common part of the definition name up to the stage

defbasename=$1 # TODO: Check this is passed and is a valid dataset
#stages=( gen g4 detsim reco1 reco2 caf ) # TODO: make this a parameter to be passed, with these as the defaults
stages=( gen_g4_detsim_reco1 reco2 caf caf_flat_caf ) # TODO: make this a parameter to be passed, with these as the defaults

for stage in ${stages[@]}
do
  defname="${defbasename}_${stage}_sbnd"
  echo "On stage: $stage with defname: $defname"

  # Check the dataset exists 
  if [ ! $(samweb -e sbnd list-definitions | grep "$defname") ]
  then
    echo "Definition not found by SAM"
    exit 1
  else
    samweb -e sbnd list-definition-files --summary $defname
  fi

  fifeutils_run_duplicate_finder_descendants.sh $defname | tee "${defname}_dupes.txt"

  echo "Found $(grep $stage ${defname}_dupes.txt  | wc -l) $stage duplicate files with $(wc -l ${defname}_dupes.txt) files including ancestors"
  
  convert_filename_to_ifdh_path.sh "${defname}_dupes.txt" | tee "${defname}_ifdh.txt"

  echo 

  # TODO: get y/n confirmation to delete the files
  # This will ensure that we do not delete the whole dataset by accident

  # ifdh_delete_files.sh "${defname}_ifdh.txt"
  # sam_retire_files.sh "${defname}_dupes.txt"
done
