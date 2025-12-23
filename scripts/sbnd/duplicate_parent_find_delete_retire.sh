#!/bin/bash

# Configuration
SAMWEB_CMD="samweb -e sbnd"
TEST_MODE=false
CONFIRM=true

# Functions
usage() {
    echo "Usage: $0 [-t] [-y] <dataset_name>"
    echo "  -t    Test mode (only show what would be done)"
    echo "  -y    Skip confirmation prompts"
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

delete_file() {
    local file=$1
    
    # Get physical locations
    local locations=$($SAMWEB_CMD locate-file "$file" | grep -oP 'enstore:\K[^ ]*')
    
    if [ -z "$locations" ]; then
        echo "Warning: No locations found for $file - cannot delete"
        return 1
    fi

    # Delete physical files
    for loc in $locations; do
        local full_path="/pnfs/sbnd/$loc"
        echo "[DELETE] rm -f \"$full_path\""
        if ! $TEST_MODE; then
            rm -f "$full_path" || { echo "Error: Failed to delete $full_path"; return 1; }
        fi
    done

    # Retire from SAM
    echo "[RETIRE] $SAMWEB_CMD retire-file \"$file\""
    if ! $TEST_MODE; then
        $SAMWEB_CMD retire-file "$file" || { echo "Error: Failed to retire $file"; return 1; }
    fi
    
    return 0
}

# Parse arguments
while getopts "ty" opt; do
    case $opt in
        t) TEST_MODE=true ;;
        y) CONFIRM=false ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

[ $# -eq 0 ] && usage
dataset_name=$1

if $TEST_MODE; then
    echo "=== RUNNING IN TEST MODE ==="
    echo "No files will actually be deleted or retired"
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
files_to_delete=()
processed_files=0
duplicates_found=0

echo "Processing $total_files files..."
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
            files_to_delete+=("$existing_file")
        else
            files_to_delete+=("$file")
        fi
        ((duplicates_found++))
    else
        ancestor_map[$last_ancestor]=$file
    fi
done

echo -e "\nFound $duplicates_found duplicates in dataset"

# Process deletions if needed
if [ ${#files_to_delete[@]} -gt 0 ]; then
    if $CONFIRM && ! $TEST_MODE; then
        read -p "Delete ${#files_to_delete[@]} duplicates? [y/N] " confirm
        [[ $confirm == [yY] ]] || exit 0
    fi
    
    echo "Processing duplicates..."
    deleted_count=0
    for file in "${files_to_delete[@]}"; do
        if delete_file "$file"; then
            ((deleted_count++))
        fi
    done
    echo "Successfully processed $deleted_count duplicates"
else
    echo "No duplicates found to delete"
fi

exit 0
