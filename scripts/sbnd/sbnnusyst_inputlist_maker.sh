#!/bin/bash

echo "sbnnusyst_inputlist_maker.sh running"

URI_FILE=""
process_args() {

    PRINTUSAGE=0
    
    TEMP=$(getopt -n $0 -s bash -a \
     --longoptions="help" \
     -o hc: -- "$@") || exit 1

    eval set -- "${TEMP}"
    unset TEMP

    let iarg=0
    set -u
    while [ $# -gt 0 ]; do
	let iarg=${iarg}+1
	case "$1" in
	    "--"             ) shift                       ; break ;;
	    -h | --help      ) PRINTUSAGE=1                        ;;
	    -c               ) export URI_FILE="$2"        ; shift ;;
	    -*               ) echo "unknown flag $opt ($1)" ; PRINTUSAGE=1 ;;
	esac
	shift # eat up the arg we just used
    done
    set +u

    if [[ ${PRINTUSAGE} -eq 1 ]] ; then
	usage
    fi

}

process_args "$@"

# With get_config = True or multifile = True, the postscript (UpdateReweight) will run
# multiple times as well. So we'll overwrite input_list, and only end up processing one-by-one.
echo ${URI_FILE} > input.list
echo "Added file to input list: ${URI_FILE}"
