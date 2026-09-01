#!/bin/bash

# Configuration
SAMWEB_CMD="samweb -e sbnd"
TEST_MODE=false
CONFIRM=true
DRY_RUN=false

# Functions
usage() {
    echo "Usage: $0 [-t] [-y] [-n] <dataset_name>"
    echo "  -t    Test mode (show actions but don't execute)"
    echo "  -y    Skip confirmation prompts"
    echo "  -n    Dry run (just show analysis, no deletion info)"
    exit 1
}

get_last_ancestor() {
    local file=$1
    $SAMWEB_CMD file-lineage ancestors "$file" | tail -n 1
}

get_file_age() {
    local file=$1
    $SAMWEB_CMD get-metadata "$file" | grep -oP 'create_time:\s*\K.*' || echo "0"
}

get_descendants() {
    local file=$1
    $SAMWEB_CMD list-files "ischildof:(file_name $file)" 2>/dev/null || echo ""
}

get_full_path() {
    local file=$1
    # Extract directory from locate-file output and combine with filename
    local dir=$($SAMWEB_CMD locate-file "$file" | cut -d':' -f2 | sed 's/^ *//;s/ *$//')
    echo "${dir}/${file}"
}

validate_file_path() {
    local path=$1
    [[ -n "$path" ]] && [[ "$path" =~ ^/pnfs/ ]] && [[ "$path" =~ \.(root|art|json|txt|log)$ ]]
}

delete_file() {
    local file=$1
    
    echo "Processing file: $file"
    
    # Get physical file path
    local full_path=$(get_full_path "$file")
    
    # Clean path formatting
    full_path=$(echo "$full_path" | sed 's#//#/#g')
    
    if ! validate_file_path "$full_path"; then
        echo "  Warning: Invalid file path '$full_path' - skipping"
        return 1
    fi

    # Delete physical file
    if ! $DRY_RUN; then
        echo "  [DELETE] rm -f \"$full_path\""
        if ! $TEST_MODE; then
            if [[ -f "$full_path" ]]; then
                if ! rm -f "$full_path"; then
                    echo "  Error: Failed to delete $full_path"
                    return 1
                fi
            else
                echo "  Warning: File $full_path does not exist - skipping"
            fi
        fi
    fi

    # Retire from SAM
    if ! $DRY_RUN; then
        echo "  [RETIRE] $SAMWEB_CMD retire-file \"$file\""
        if ! $TEST_MODE; then
            if ! $SAMWEB_CMD retire-file "$file"; then
                echo "  Error: Failed to retire $file"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Parse arguments
while getopts "tyn" opt; do
    case $opt in
        t) TEST_MODE=true ;;
        y) CONFIRM=false ;;
        n) DRY_RUN=true ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

[ $# -eq 0 ] && usage
dataset_name=$1

if $TEST_MODE; then
    echo "=== RUNNING IN TEST MODE ==="
    echo "No files will actually be deleted or retired"
elif $DRY_RUN; then
    echo "=== DRY RUN ==="
    echo "Only showing analysis results"
fi

# Verify dataset exists
echo "Verifying dataset: $dataset_name"
if ! $SAMWEB_CMD list-definitions | grep -q "^${dataset_name}$"; then
    echo "Error: Dataset $dataset_name not found"
    exit 1
fi

# Get file list
echo "Retrieving file list..."
file_list=$($SAMWEB_CMD list-definition-files "$dataset_name")
total_files=$(echo "$file_list" | wc -w)
[ "$total_files" -eq 0 ] && { echo "No files found in dataset"; exit 0; }

# Process files
declare -A ancestor_map
declare -A file_ages
declare -A duplicate_groups
files_to_delete=()
processed_files=0
duplicates_found=0

echo "Analyzing $total_files files for duplicates..."
for file in $file_list; do
    ((processed_files++))
    echo -ne "Processing file $processed_files/$total_files\r"
    
    last_ancestor=$(get_last_ancestor "$file")
    file_age=$(get_file_age "$file")
    file_ages["$file"]=$file_age
    
    if [ -n "${ancestor_map[$last_ancestor]}" ]; then
        # Duplicate found - compare ages
        existing_file=${ancestor_map[$last_ancestor]}
        existing_age=${file_ages["$existing_file"]}
        
        if [ "$file_age" -lt "$existing_age" ]; then
            # Current file is older - keep it instead
            ancestor_map[$last_ancestor]=$file
            duplicate_groups["$last_ancestor"]+=" $existing_file"
            files_to_delete+=("$existing_file")
        else
            duplicate_groups["$last_ancestor"]+=" $file"
            files_to_delete+=("$file")
        fi
        ((duplicates_found++))
    else
        ancestor_map[$last_ancestor]=$file
    fi
done

echo -e "\nFound $duplicates_found primary duplicates in dataset"

# Find all descendants of duplicate files
descendants_to_delete=()
if [ $duplicates_found -gt 0 ]; then
    echo "Identifying descendants of duplicate files..."
    for ancestor in "${!duplicate_groups[@]}"; do
        for file in ${duplicate_groups[$ancestor]}; do
            echo -n "Checking descendants of $file... "
            descendants=$(get_descendants "$file")
            if [ -n "$descendants" ]; then
                count=$(echo "$descendants" | wc -w)
                echo "found $count"
                descendants_to_delete+=($descendants)
            else
                echo "none found"
            fi
        done
    done
fi

total_descendants=${#descendants_to_delete[@]}
total_to_delete=$((${#files_to_delete[@]} + total_descendants))

# Summary report
echo -e "\n=== ANALYSIS SUMMARY ==="
echo "Primary duplicates found: ${#files_to_delete[@]}"
echo "Descendant files found: $total_descendants"
echo "Total files to remove: $total_to_delete"

if [ $total_to_delete -eq 0 ]; then
    echo "No duplicates found to delete"
    exit 0
fi

# Process deletions if needed
if $DRY_RUN; then
    exit 0
fi

if $CONFIRM && ! $TEST_MODE; then
    read -p "Delete $total_to_delete files? [y/N] " confirm
    [[ $confirm == [yY] ]] || exit 0
fi

echo -e "\nProcessing deletions..."
deleted_count=0

# First delete descendants (children before parents)
if [ $total_descendants -gt 0 ]; then
    echo "Deleting descendant files..."
    for file in "${descendants_to_delete[@]}"; do
        if delete_file "$file"; then
            ((deleted_count++))
        fi
    done
fi

# Then delete primary duplicates
echo "Deleting primary duplicate files..."
for file in "${files_to_delete[@]}"; do
    if delete_file "$file"; then
        ((deleted_count++))
    fi
done

echo -e "\nSuccessfully processed $deleted_count/$total_to_delete files"

exit 0
