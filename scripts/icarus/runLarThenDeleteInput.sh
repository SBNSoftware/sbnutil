#! /bin/bash -
#source /cvmfs/icarus.opensciencegrid.org/products/icarus/setup_icarus.sh; 
#setup icaruscode v09_90_00 -q e26:prof; 
#export X509_USER_PROXY=/opt/icaruspro/icaruspro.Production.proxy; 
#setup fife_utils;

INPUTFILE=overwrite_me
NEVT=2
STREAMNAME=offbeambnbminbias
FCLFILE=overwrite_me
BASENAME=overwrite_me
OUTPUTFILE=overwrite_me
# Get the options
while getopts :h:s:n:c:b:o: option; 
do
   case $option in
      h) # display Help
         Help
         exit;;
      s) INPUTFILE=$OPTARG;;
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

lar -c ${FCLFILE} -T hist_${OUTPUTFILE} -n ${NEVT} --sam-stream-name ${STREAMNAME} -o ${OUTPUTFILE} -s ${INPUTFILE}
echo "Output file is: ${OUTPUTFILE} ; rootstat.py results are:"
rootstat.py ${OUTPUTFILE}
rm -rf ${INPUTFILE}
