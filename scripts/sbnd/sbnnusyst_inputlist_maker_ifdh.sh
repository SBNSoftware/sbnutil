#!/bin/bash

echo "sbnnusyst_inputlist_maker_ifdh.sh running"

source /cvmfs/larsoft.opensciencegrid.org/products/setup
setup ifdhc v2_8_0 -q e26:p3915:prof
echo "ifdh in use: $(command -v ifdh) (IFDHC_VERSION=${IFDHC_VERSION:-unset})"

URI_FILE=""
SAM_PROCESS=""
SAM_WEB_URI=""
process_args() {

    PRINTUSAGE=0
    
    TEMP=$(getopt -n $0 -s bash -a \
		  --longoptions="help" \
		  --long sam-web-uri:,sam-process-id: \
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
	    --sam-web-uri    ) export SAM_WEB_URI="$2"     ; shift ;;
	    --sam-process-id ) export SAM_PROCESS="$2"     ; shift ;;
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

# Single run using ifdh_art, and we inhale the inputs

echo "using SAM_WEB_URI = ${SAM_WEB_URI}"
echo "using SAM_PROCESS = ${SAM_PROCESS}"

nextf=""
lastf=""
while : ; do
    nextf=$(ifdh getNextFile ${SAM_WEB_URI} ${SAM_PROCESS})
    if [[ -z "${nextf}" || "${nextf}" == "${lastf}" ]]; then
        break
    fi
    ifdh updateFileStatus ${SAM_WEB_URI} ${SAM_PROCESS} $(basename ${nextf}) transferred
    echo "${nextf}" >> input.list
    echo "Adding $(basename ${nextf}) to input.list"
    lastf="${nextf}"
done

echo "input.list now contains $(wc -l < input.list) files:"
cat input.list
