#!/bin/bash

FCL={gen-fcl-name}.fcl
FCLNAME={gen-fcl-name}
NFILES={number-of-files-with-50-events-per-file}
MDPRODNAME={production-name}
OUTDIR=/pnfs/sbnd/persistent/sbndpro/initialfcl
WORKDIR=/sbnd/app/users/sbndpro/fcl_gen/$MDPRODNAME/$FCLNAME/
MDPROJVER={version}
MDPRODTYPE=official
MDSTAGENAME=gen

fclout=debug_config.txt
lar -c $FCL --debug-config $fclout

if [[ $? -ne "0" ]]; then
    echo -e "\nERROR: cannot find / parse fcl file"
    echo -e "\t$FCL"
    echo -e "Exiting without producing initialfcl set...\n"
    return
fi

sbndpoms_genfclwithrunnumber_maker.sh --fcl $FCL --outdir $OUTDIR --nfiles $NFILES --workdir $WORKDIR --mdprojver $MDPROJVER --mdprodname $MDPRODNAME --mdprodtype $MDPRODTYPE --mdstagename $MDSTAGENAME --samdeclare
