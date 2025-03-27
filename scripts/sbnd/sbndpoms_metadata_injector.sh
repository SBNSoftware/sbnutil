#!/bin/sh
#======================================================================
#
# Name: sbndpoms_metadata.sh
#
# Purpose: Append SAM metadata overrides to a fcl file.
#
# Usage: sbndpoms_metadata_injector.sh [options]
#
# General options:
#
# -h|-?|--help                  - Print help message.
# --inputfclname <fcl file>     - Fcl file to append to.
# --writeExtraMetadata          - Get metadata from the input file argument
#
# Options for overriding SAM built-in metadata (service FileCatalogMetadata).
#
# --mdappfamily <family>        - Application family.
# --mdappversion <version>      - Appliction version.
# --mdfiletype <file_type>      - File type.
# --mdruntype <run_type>        - Run type.
# --mdgroupname <group>         - Group.
#
# Options for overriding experiment-specific metadata.
#
# --configuration <config>      - Configuration of the DAQ.
#
# --mdfclname <fcl file>        - Fcl file name to store in metadata.
# --mdprojectname <project>     - Project name.
# --mdprojectstage <stage>      - Project stage.
# --mdprojectversion <version>  - Project version.
# --mdprojectsoftware <product> - Top level ups product.
# --mdproductionname <campaign> - Campaign name.
# --mdproductiontype <type>     - Campaign type.
#
# Options for non-artroot files.
#
# --tfilemdjsonname <json name> - Name of TFile json file.
# --cafname         <caf name>  - Name of caf file.
#
#======================================================================

INPUTFCLNAME=""
MT_FCLNAME=""
MT_APPFAMILY=""
MT_APPVERSION=""
MT_FILETYPE=""
MT_RUNTYPE=""
MT_GROUPNAME=""
MT_PROJECTSOFTWARE=""
MT_PROJECTVERSION=""
MT_PRODUCTIONNAME=""
MT_PRODUCTIONTYPE=""
MT_CONFIGURATION=""
MT_DATASTREAM=""
MT_EXPERIMENT=""
MT_BEAMTYPE=""
MT_DETECTOR=""
MT_EVENTCOUNT=""
MT_RANDOM=""
MT_RANDOMRUN=""
MT_PROJECTNAME=""
MT_PROJECTSTAGE=""

# Help function
function show_help {
  awk '/# Usage:/,/#======/{print $0}' $0 | head -n -3 | cut -c3-
}

# Take in all of the arguments

b_construct_metadata=0

while :; do
    case $1 in
        -h|-\?|--help)
            show_help    # Display a usage synopsis.
            exit
            ;;

	--inputfclname)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                INPUTFCLNAME="$2"
                shift
            else
                echo "$0 ERROR: inputfclname requires a non-empty option argument."
                exit 1
            fi
            ;;

	--mdfclname)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_FCLNAME="$2"
                shift
            else
                echo "$0 ERROR: mdfclname requires a non-empty option argument."
                exit 1
            fi
            ;;

	--mdappfamily)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_APPFAMILY="$2"
                shift
            else
                echo "$0 ERROR: mdappfamily requires a non-empty option argument."
                exit 1
            fi
            ;;

        --mdappversion)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_APPVERSION="$2"
                shift
            else
                echo "$0 ERROR: mdappversion requires a non-empty option argument."
                exit 1
            fi
            ;;
        --inputfclname)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                INPUTFCLNAME="$2"
                shift
            else
                echo "$0 ERROR: inputfclname requires a non-empty option argument."
                exit 1
            fi
            ;;

        --mdfiletype)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_FILETYPE="$2"
                shift
            else
                echo "$0 ERROR: mdfiletype requires a non-empty option argument."
                exit 1
            fi
            ;;
        --mdruntype)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_RUNTYPE="$2"
                shift
            else
                echo "$0 ERROR: mdruntype requires a non-empty option argument."
                exit 1
            fi
            ;;
        --mdgroupname)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_GROUPNAME="$2"
                shift
            else
                echo "$0 ERROR: mdgroupname requires a non-empty option argument."
                exit 1
            fi
            ;;
        --mdprojectsoftware)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_PROJECTSOFTWARE="$2"
                shift
            else
                echo "$0 ERROR: mdprojectsoftware requires a non-empty option argument."
                exit 1
            fi
            ;;
        --mdprojectversion)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_PROJECTVERSION="$2"
                shift
            else
                echo "$0 ERROR: mdprojectversion requires a non-empty option argument."
                exit 1
            fi
            ;;
        --mdproductionname)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_PRODUCTIONNAME="$2"
                shift
            else
                echo "$0 ERROR: mdproductionname requires a non-empty option argument."
                exit 1
            fi
            ;;
        --mdproductiontype)       # Takes an option argument; ensure it has been specified.
            if [[ "$2" && "$2" != "--"* ]]; then
                MT_PRODUCTIONTYPE="$2"
                shift
            else
                echo "$0 ERROR: mdproductiontype requires a non-empty option argument."
                exit 1
            fi
            ;;

	--writeExtraMetadata)   # Takes an option argument; ensure it has been specified
            if [[ "$2" && "$2" != "--"* ]]; then
		b_construct_metadata=1
                INPUTFILE="$2"
                shift
            else
                echo "$0 ERROR: writeExtraMetadata requires a non-empty option argument."
                exit 1
            fi
            ;;
	--configuration)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_CONFIGURATION="$2"
		shift
	    else
		echo "$0 ERROR: configuration requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--datastream)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_DATASTREAM="$2"
		shift
	    else
		echo "$0 ERROR: experiment requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--experiment)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_EXPERIMENT="$2"
		shift
	    else
		echo "$0 ERROR: experiment requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--beamType)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_BEAMTYPE="$2"
		shift
	    else
		echo "$0 ERROR: beamType requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--detector)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_DETECTOR="$2"
		shift
	    else
		echo "$0 ERROR: detector requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--eventCount)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_EVENTCOUNT="$2"
		shift
	    else
		echo "$0 ERROR: eventCount requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--random)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_RANDOM="$2"
		shift
	    else
		echo "$0 ERROR: random requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--randomRun)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_RANDOMRUN="$2"
		shift
	    else
		echo "$0 ERROR: randomRun requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--mdprojectname)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_PROJECTNAME="$2"
		shift
	    else
		echo "$0 ERROR: mdprojectname requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--mdprojectstage)        # Takes an option argument; ensure it has been specified
	    if [[ "$2" && "$2" != "--"* ]]; then
		MT_PROJECTSTAGE="$2"
		shift
	    else
		echo "$0 ERROR: mdprojectstage requires a non-empty option argument."
		exit 1
	    fi
	    ;;
	--)              # End of all options.
            shift
            break
            ;;
        -?*)
            printf "$0 WARN: Unknown option (ignored): %s\n" "$1" >&2
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac
    shift
done

if [[ ${b_construct_metadata} == 1 ]] ; then
    samweb -e sbnd get-metadata --json $(basename ${INPUTFILE})
else
    if [ -z "$INPUTFCLNAME" ]; then
	echo "$0 ERROR: inputfclname is mandatory"
	exit 2
    fi

    if [ -z "$MT_APPFAMILY" ]; then
	echo "$0 ERROR: mdappfamily is mandatory"
	exit 2
    fi

    if [ -z "$MT_APPVERSION" ]; then
	echo "$0 ERROR: mdappversion is mandatory"
	exit 2
    fi

    if [ -z "$MT_FILETYPE" ]; then
	echo "$0 ERROR: mdfiletype is mandatory"
	exit 2
    fi

    if [ -z "$MT_RUNTYPE" ]; then
	echo "$0 ERROR: mdruntype is mandatory"
	exit 2
    fi

    if [ -z "$MT_GROUPNAME" ]; then
	echo "$0 ERROR: mdgroupname is mandatory"
	exit 2
    fi

    if [ -z "$MT_FCLNAME" ]; then
	echo "$0 ERROR: mdfclname is mandatory"
	exit 2
    fi

    if [ -z "$MT_PROJECTNAME" ]; then
	echo "$0 ERROR: mdprojectname is mandatory"
	exit 2
    fi

    if [ -z "$MT_PROJECTSTAGE" ]; then
	echo "$0 ERROR: mdprojectstage is mandatory"
	exit 2
    fi

    if [ -z "$MT_PROJECTSOFTWARE" ]; then
	echo "$0 ERROR: mdprojectsoftware is mandatory"
	exit 2
    fi

    if [ -z "$MT_PROJECTVERSION" ]; then
	echo "$0 ERROR: mdprojectversion is mandatory"
	exit 2
    fi

    if [ -z "$MT_PRODUCTIONNAME" ]; then
	echo "$0 ERROR: mdproductionname is mandatory"
	exit 2
    fi

    if [ -z "$MT_PRODUCTIONTYPE" ]; then
	echo "$0 ERROR: mdproductiontype is mandatory"
	exit 2
    fi

    echo "Dumping all the variables I have!"
    echo "INPUTFCLNAME: ${INPUTFCLNAME}"
    echo "MT_FCLNAME: ${MT_FCLNAME}"
    echo "MT_APPFAMILY: ${MT_APPFAMILY}"
    echo "MT_APPVERSION: ${MT_APPVERSION}"
    echo "MT_FILETYPE: ${MT_FILETYPE}"
    echo "MT_RUNTYPE: ${MT_RUNTYPE}"
    echo "MT_GROUPNAME: ${MT_GROUPNAME}"
    echo "MT_PROJECTSOFTWARE: ${MT_PROJECTSOFTWARE}"
    echo "MT_PROJECTVERSION: ${MT_PROJECTVERSION}"
    echo "MT_PRODUCTIONNAME: ${MT_PRODUCTIONNAME}"
    echo "MT_PRODUCTIONTYPE: ${MT_PRODUCTIONTYPE}"
    echo "MT_CONFIGURATION: ${MT_CONFIGURATION}"
    echo "MT_DATASTREAM: ${MT_DATASTREAM}"
    echo "MT_EXPERIMENT: ${MT_EXPERIMENT}"
    echo "MT_BEAMTYPE: ${MT_BEAMTYPE}"
    echo "MT_DETECTOR: ${MT_DETECTOR}"
    echo "MT_EVENTCOUNT: ${MT_EVENTCOUNT}"
    echo "MT_RANDOM: ${MT_RANDOM}"
    echo "MT_RANDOMRUN: ${MT_RANDOMRUN}"
    echo "MT_PROJECTNAME: ${MT_PROJECTNAME}"
    echo "MT_PROJECTSTAGE: ${MT_PROJECTSTAGE}"

    #Start the injection
    echo -e "\n#Metadata injection by $0" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadata: @local::art_file_catalog_data" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadata.applicationFamily: \"$MT_APPFAMILY\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadata.applicationVersion: \"$MT_APPVERSION\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadata.fileType: \"$MT_FILETYPE\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadata.runType: \"$MT_RUNTYPE\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadata.group: \"$MT_GROUPNAME\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.FCLName: \"$MT_FCLNAME\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.Experiment: \"$MT_EXPERIMENT\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.ProjectName: \"$MT_PROJECTNAME\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.ProjectStage: \"$MT_PROJECTSTAGE\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.ProjectSoftware: \"$MT_PROJECTSOFTWARE\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.ProjectVersion: \"$MT_PROJECTVERSION\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.ProductionName: \"$MT_PRODUCTIONNAME\"" | tee -a $INPUTFCLNAME
    echo "services.FileCatalogMetadataSBN.ProductionType: \"$MT_PRODUCTIONTYPE\"" | tee -a $INPUTFCLNAME
    # We can leverage the "Parameters" to add specific metadata
    echo "services.FileCatalogMetadataSBN.Parameters: [[\"configuration.name\", \"$MT_CONFIGURATION\"], [\"data_stream\", \"$MT_DATASTREAM\"], [\"sbn_dm.event_count\", \"$MT_EVENTCOUNT\"], [\"sbn_dm.beam_type\", \"$MT_BEAMTYPE\"], [\"sbn_dm.detector\", \"$MT_DETECTOR\"], [\"sbnd.random\", \"$MT_RANDOM\"], [\"sbnd.random_run\", \"$MT_RANDOMRUN\"]]" | tee -a $INPUTFCLNAME

fi
