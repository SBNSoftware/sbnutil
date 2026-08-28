#! /bin/bash -
#source /cvmfs/icarus.opensciencegrid.org/products/icarus/setup_icarus.sh;
#setup icaruscode v09_90_00 -q e26:prof;
#export X509_USER_PROXY=/opt/icaruspro/icaruspro.Production.proxy;
#setup fife_utils;

# The real SAM data file's path/URL is NOT passed as a CLI arg -- it's read
# from real_data_input.txt, written by stashDataFile.sh (executable0). That
# value may be a local path OR a root://... XROOTD URL (sam_consumer.schema
# = root), so it must be read verbatim and passed straight through to lar's
# -s, never mv/cp'd as a local file.
STASHFILE=real_data_input.txt
G4FILE=overwrite_me
NEVT=2
STREAMNAME=offbeambnbminbias
FCLFILE=overwrite_me
OUTPUTFILE=overwrite_me
# Get the options
while getopts :h:g:n:c:b:o: option;
do
   case $option in
      h) # display Help
         Help
         exit;;
      g) G4FILE=$OPTARG;;
      n) NEVT=$OPTARG;;
      c) FCLFILE=$OPTARG;;
      b) STREAMNAME=$OPTARG;;
      o) OUTPUTFILE=$OPTARG;;
      \?) echo "Error: Invalid option"
          valid=0
          ;;
       :) valid=0
          echo "The additional argument for option $OPTARG was omitted."
          ;;
   esac
done

INPUTFILE=$(cat ${STASHFILE})

cp ${G4FILE} genfile.root.local

lar -c ${FCLFILE} -T hist_${OUTPUTFILE} -n ${NEVT} --sam-stream-name ${STREAMNAME} -o ${OUTPUTFILE} -s ${INPUTFILE}
echo "Output file is: ${OUTPUTFILE} ; rootstat.py results are:"
rootstat.py ${OUTPUTFILE}
rm -f ${STASHFILE} genfile.root.local
