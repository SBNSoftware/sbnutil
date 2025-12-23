#!/bin/bash

# Script to find, retire, and delete files using samweb OR only delete files.
# Accepts multiple directory paths (shell expansion for wildcards is expected).
# Can optionally filter files by an include name pattern (-n)
# OR by a list of exclude name patterns (-x).
# Includes test mode, statistics, progress bar, and empty directory cleanup.

# --- Functions ---

show_help() {
  echo "Usage: $0 [OPTIONS] <directory_path1> [<directory_path2> ...]"
  echo ""
  echo "Processes files within the specified directories."
  echo "Default action: Retire file via SAMWEB, then delete from disk."
  echo "Use --delete-only to skip retirement and only delete from disk."
  echo "Wildcards in directory paths should be expanded by the shell."
  echo ""
  echo "Examples:"
  echo "  Retire & Delete (Include): $0 -t -n pattern /path/run1*"
  echo "  Retire & Delete (Exclude): $0 -t -x p1,p2 /path/run2*"
  echo "  Delete Only:               $0 -t --delete-only /path/run3*"
  echo ""
  echo "Options:"
  echo "  -t, --test           Run in test mode: print commands."
  echo "  -v, --verbose        Enable verbose output."
  echo "  -h, --help           Show this help message and exit."
  echo "  -l, --log <file>     Specify log file (default: removal_log_YYYYMMDD_HHMMSS.txt)."
  echo "  -p, --progress       Display a progress bar for each directory."
  echo "  -n, --name-pattern <pattern> Include files whose names contain the pattern."
  echo "  -x, --exclude-patterns <p1,p2,...> Exclude files matching any comma-separated pattern."
  echo "  --delete-only        Skip the retire step, only delete files from disk."
  echo "                       (Options -n and -x are mutually exclusive)"
  exit 1
}

# Function to write to the log file
log_message() {
  local message="$1"
  local timestamp
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  # Ensure log file path is set before trying to write
  if [[ -n "$log_file" ]]; then
    echo "$timestamp: $message" >>"$log_file"
  fi
  if [[ "$verbose" == "true" ]]; then
    echo "$timestamp: $message"
  fi
}

# ... other functions (retire_file, delete_file, delete_empty_directories, display_progress) remain unchanged ...
# (They already respect $test_mode internally)
retire_file() {
  local full_path="$1"
  local filename
  filename=$(basename "$full_path")
  local retire_result
  if [[ "$test_mode" == "false" ]]; then
    # Redirect both stdout and stderr of samweb to the log file
    samweb -e sbnd retire-file "$filename" >> "$log_file" 2>&1
    retire_result="$?"
    if [[ "$retire_result" -ne 0 ]]; then
      log_message "Error retiring file: $filename (original path: $full_path). Exit code: $retire_result"
      return 1
    fi
  else
    log_message "[TEST MODE] Would execute: samweb -e sbnd retire-file \"$filename\" (original path: $full_path)"
  fi
  return 0
}

delete_file() {
  local file="$1"
  local delete_result
  if [[ "$test_mode" == "false" ]]; then
    # Redirect both stdout and stderr of rm to the log file
    rm -f "$file" >> "$log_file" 2>&1
    delete_result="$?"
    if [[ "$delete_result" -ne 0 ]]; then
      log_message "Error deleting file: $file. Exit code: $delete_result"
      return 1
    fi
  else
    log_message "[TEST MODE] Would execute: rm -f \"$file\""
  fi
  return 0
}

delete_empty_directories() {
  log_message "----------------------------------------------------"
  log_message "Checking and deleting empty directories..."
  # Only run if processed_directories array is not empty
  if [[ ${#processed_directories[@]} -gt 0 ]]; then
      # Use find -print0 and while read -d for safety with special chars
      find "${processed_directories[@]}" -depth -type d -empty -print0 | while IFS= read -r -d $'\0' dir; do
        if [[ "$test_mode" == "false" ]]; then
          log_message "Deleting empty directory: $dir"
          rmdir "$dir" >> "$log_file" 2>&1
          if [[ "$?" -ne 0 ]]; then
            log_message "Warning: Could not delete empty directory: $dir (perhaps not empty now or permissions issue)"
          fi
        else
          log_message "[TEST MODE] Would execute: rmdir \"$dir\""
        fi
      done
  else
      log_message "No directories were successfully processed, skipping empty directory cleanup."
  fi
  log_message "Empty directory cleanup check complete."
}

display_progress() {
  local current="$1"
  local total="$2"
  # Prevent division by zero if total is 0
  if [[ "$total" -eq 0 ]]; then
      printf "\rProgress: N/A (0 matching files) "
      return
  fi
  local width=50
  local progress=$((current * 100 / total))
  local filled=$((current * width / total))
  local bar="["
  local i
  for ((i = 0; i < width; i++)); do
    if ((i < filled)); then
      bar+="="
    else
      bar+=" "
    fi
  done
  bar+="]"
  # Use printf for reliable carriage return and formatting
  # Pad with spaces at the end to overwrite previous longer lines
  printf "\rProgress: %3d%% %s (%d/%d)      " "$progress" "$bar" "$current" "$total"
}

# --- Script Initialization ---
start_time=$(date +%s)
test_mode="false"
verbose="false"
delete_only="false" # New flag for delete-only mode
declare -a target_dirs=() # Array to hold directories passed as arguments
declare -a processed_directories=() # Keep track of dirs actually processed for cleanup
log_file=""
use_progress_bar="false"
filename_pattern="" # Variable for include pattern (-n)
exclude_patterns_list="" # Variable for exclude patterns list (-x)

# Counters
total_files=0
retired_ok=0 # Will remain 0 in delete-only mode
deleted_ok=0
retire_errors=0 # Will remain 0 in delete-only mode
delete_errors=0

# --- Argument Processing ---
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -t|--test)
      test_mode="true"
      shift
      ;;
    -v|--verbose)
      verbose="true"
      shift
      ;;
    -h|--help)
      show_help # Exits
      ;;
    -l|--log)
      if [[ -z "$2" || "$2" == -* ]]; then echo "Error: -l requires argument." >&2; show_help; fi
      log_file="$2"
      shift 2
      ;;
    -p|--progress)
      use_progress_bar="true"
      shift
      ;;
    -n|--name-pattern)
      if [[ -z "$2" || "$2" == -* ]]; then echo "Error: -n requires argument." >&2; show_help; fi
      filename_pattern="$2"
      shift 2
      ;;
    -x|--exclude-patterns)
      if [[ -z "$2" || "$2" == -* ]]; then echo "Error: -x requires argument (comma-separated list)." >&2; show_help; fi
      exclude_patterns_list="$2"
      shift 2
      ;;
    --delete-only) # New flag
      delete_only="true"
      shift
      ;;
    --) # End of options marker
      shift
      target_dirs+=("$@")
      break
      ;;
    -*) # Handle unknown options
      echo "Error: Unknown option: $1" >&2
      show_help
      ;;
    *) # Assume it's a directory path/pattern argument
      target_dirs+=("$1")
      shift
      ;;
  esac
done

# --- Validation ---
if [[ ${#target_dirs[@]} -eq 0 ]]; then
  echo "Error: Please provide one or more directory paths." >&2
  show_help
fi

# Check for mutually exclusive options
if [[ -n "$filename_pattern" && -n "$exclude_patterns_list" ]]; then
  echo "Error: Options -n (--name-pattern) and -x (--exclude-patterns) are mutually exclusive." >&2
  show_help
fi

# --- Log File Initialization ---
# (No changes needed here)
if [[ -z "$log_file" ]]; then
  log_file="removal_log_$(date +'%Y%m%d_%H%M%S').txt"
fi
if ! > "$log_file"; then
   echo "Error: Cannot write to log file '$log_file'. Check path and permissions." >&2
   exit 1
fi
chmod 644 "$log_file" || echo "Warning: Could not chmod log file '$log_file'" >&2


# --- Pre-computation for find filter arguments ---
# (No changes needed here)
declare -a find_filter_args=()
declare -a exclude_patterns_array=()

if [[ -n "$filename_pattern" ]]; then
    find_filter_args=(-name "*${filename_pattern}*")
elif [[ -n "$exclude_patterns_list" ]]; then
    IFS=',' read -r -a raw_patterns <<< "$exclude_patterns_list"
    for item in "${raw_patterns[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"; item="${item%"${item##*[![:space:]]}"}"
        if [[ -n "$item" ]]; then exclude_patterns_array+=("$item"); fi
    done
    if [[ ${#exclude_patterns_array[@]} -gt 0 ]]; then
        for patt in "${exclude_patterns_array[@]}"; do find_filter_args+=(-not -name "*${patt}*"); done
    else
        echo "Warning: Exclude pattern list (-x) provided but resulted in no valid patterns." >&2
        log_message "Warning: Exclude pattern list (-x) provided but resulted in no valid patterns."
    fi
fi

# --- Main Processing ---
current_date=$(date +'%Y-%m-%d %H:%M:%S %Z') # Get current date for logging start
log_message "===================================================="
log_message "Script execution started at $current_date"
log_message "Target directories specified: ${target_dirs[*]}"
# Log active mode
if [[ "$delete_only" == "true" ]]; then
    log_message "Mode: Delete Only"
else
    log_message "Mode: Retire then Delete"
fi
# Log filter info
if [[ -n "$filename_pattern" ]]; then log_message "Applying filename INCLUDE filter: *${filename_pattern}*"
elif [[ ${#exclude_patterns_array[@]} -gt 0 ]]; then log_message "Applying filename EXCLUDE filters for patterns: ${exclude_patterns_array[*]}"
else log_message "No filename filters applied."; fi
[[ "$test_mode" == "true" ]] && log_message "Running in TEST MODE"
[[ "$verbose" == "true" ]] && log_message "Verbose output enabled"
[[ "$use_progress_bar" == "true" ]] && log_message "Progress bar enabled"
log_message "Log file: $log_file"
log_message "----------------------------------------------------"


# Iterate over the directories
for directory in "${target_dirs[@]}"; do

  if [[ ! -d "$directory" ]]; then
    log_message "Warning: Skipping '$directory' as it is not a valid or accessible directory."
    echo "Warning: Skipping '$directory' as it is not a valid or accessible directory." >&2
    continue
  fi

  directory="${directory%/}"
  processed_directories+=("$directory")

  # Count files matching the filter
  dir_file_count=0
  dir_file_count=$(find "$directory" "${find_filter_args[@]}" -type f -print0 2>/dev/null | grep -czc . ) || dir_file_count=0
  ((total_files += dir_file_count))

  log_message "Processing directory: $directory (${dir_file_count} matching files found)"

  if [[ "$dir_file_count" -eq 0 ]]; then
      log_message "No files matching the filter criteria found in $directory to process."
      continue
  fi

  current_file=0
  # Process files matching the filter
  find "$directory" "${find_filter_args[@]}" -type f -print0 2>/dev/null | while IFS= read -r -d $'\0' file; do
       ((current_file++))

       # === Action Logic Based on Mode ===
       if [[ "$delete_only" == "true" ]]; then
           # --- Delete Only Mode ---
           # log_message "[Delete Only Mode] Attempting to delete: $file" # Logged by delete_file in test mode
           if delete_file "$file"; then
               ((deleted_ok++))
           else
               ((delete_errors++))
               # Error already logged by delete_file
           fi
           # Skip retirement counters

       else
           # --- Default Retire-Then-Delete Mode ---
           if retire_file "$file"; then
               ((retired_ok++))
               if delete_file "$file"; then
                   ((deleted_ok++))
               else
                   ((delete_errors++))
                   # Error already logged by delete_file
                   log_message "File retired but FAILED TO DELETE: $file" # Add specific context
               fi
           else
               ((retire_errors++))
               # Error logged by retire_file
               log_message "File retirement FAILED, deletion skipped for: $file" # Add specific context
           fi
       fi # === End of mode check ===

       # Update progress/verbose output
       if [[ "$use_progress_bar" == "true" ]]; then
          display_progress "$current_file" "$dir_file_count"
       elif [[ "$verbose" == "true" ]]; then
          # Provide slightly different message depending on mode? Or keep generic?
          # Keep generic for simplicity unless delete_only verbose needs different info
          log_message "Completed processing attempt for: $file"
       fi
  done # End of the while loop

  if [[ "$use_progress_bar" == "true" ]]; then echo ""; fi # Newline after progress bar
  log_message "Finished processing directory: $directory"

done # End of the main loop

# --- Cleanup and Statistics ---
log_message "----------------------------------------------------"
log_message "Main file processing complete."

if [[ "$test_mode" == "false" ]]; then
    # Only attempt cleanup if not in test mode
    # Optional: Add check if delete_only was true? Probably still want cleanup.
    delete_empty_directories
else
    log_message "[TEST MODE] Skipping empty directory cleanup."
fi

end_time=$(date +%s)
duration=$((end_time - start_time))

# Final report
filter_desc="all files"
if [[ -n "$filename_pattern" ]]; then filter_desc="files matching include pattern";
elif [[ ${#exclude_patterns_array[@]} -gt 0 ]]; then filter_desc="files matching exclude criteria"; fi
op_mode="Retire & Delete"
[[ "$delete_only" == "true" ]] && op_mode="Delete Only"

current_date=$(date +'%Y-%m-%d %H:%M:%S %Z') # Get current date for logging end
log_message "===================================================="
log_message "Processing Statistics:"
log_message "  Operation Mode:                   $op_mode"
log_message "  Filter applied:                     $filter_desc"
log_message "  Total files found (matching filter): $total_files"
log_message "  Successfully retired:               $retired_ok"
log_message "  Retirement errors:                  $retire_errors"
log_message "  Successfully deleted:               $deleted_ok"
log_message "  Deletion errors:                    $delete_errors"
log_message "  Processing time:                    $(($duration / 60))m $(($duration % 60))s"
log_message "===================================================="
log_message "Script execution finished at $current_date."

echo "===================================================="
echo "Processing Statistics:"
echo "  Operation Mode:                   $op_mode"
echo "  Filter applied:                     $filter_desc"
echo "  Total files found (matching filter): $total_files"
echo "  Successfully retired:               $retired_ok"
echo "  Retirement errors:                  $retire_errors"
echo "  Successfully deleted:               $deleted_ok"
echo "  Deletion errors:                    $delete_errors"
echo "  Processing time:                    $(($duration / 60))m $(($duration % 60))s"
echo "  Log file:                           $log_file"
echo "===================================================="

exit 0
