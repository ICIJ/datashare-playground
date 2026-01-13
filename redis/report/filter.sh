#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<report> [<prefix>] [<batch_size>]'
check_env
check_redis_cli
check_redis_url

report_name=$1
prefix=${2:-}
batch_size=${3:-1000}

# Prompt for prefix if not provided
if [[ -z "$prefix" ]]; then
  echo -n "Enter prefix to filter out: "
  read -r prefix
fi

if [[ -z "$prefix" ]]; then
  log_error "Prefix cannot be empty"
  exit 1
fi

# Escape glob special characters in prefix except for the trailing wildcard
escaped_prefix=$(printf '%s' "$prefix" | sed 's/[][*?\\^]/\\&/g')

redis_cli="redis-cli -u $REDIS_URL --pipe"

hdel_batch() {
  local key_name=$1
  shift 1
  local values=("$@")
  local joined_values=$(printf '"%s" ' "${values[@]}")
  echo "HDEL $key_name ${joined_values}" | $redis_cli 2>/dev/null
}

show_progress() {
  local current=$1
  local total=$2
  local percent=0
  if [[ $total -gt 0 ]]; then
    percent=$((current * 100 / total))
  fi
  printf "\rProgress: %d/%d (%d%%)" "$current" "$total" "$percent"
}

# First pass: count matching keys (use large COUNT for fewer round-trips)
echo "Counting paths starting with '$prefix' in $report_name..."
cursor=0
total_count=0

while true; do
  mapfile -t lines < <(redis-cli -u "$REDIS_URL" HSCAN "$report_name" "$cursor" MATCH "${escaped_prefix}*" COUNT 10000)
  cursor=${lines[0]}

  # Count fields (every other line after cursor, starting at index 1)
  for ((i = 1; i < ${#lines[@]}; i += 2)); do
    [[ -n "${lines[i]}" ]] && ((++total_count))
  done
  printf "\rCounting: %d" "$total_count"

  [[ "$cursor" == "0" ]] && break
done

echo ""

if [[ $total_count -eq 0 ]]; then
  echo "No paths found starting with '$prefix'"
  exit 0
fi

echo "Found $total_count paths to delete"

# Second pass: delete with progress
# We must keep rescanning from cursor 0 because deleting items
# during HSCAN can invalidate the cursor position
deleted=0
batch=()

while true; do
  cursor=0
  found_in_pass=0

  # Scan through the entire hash once
  while true; do
    mapfile -t lines < <(redis-cli -u "$REDIS_URL" HSCAN "$report_name" "$cursor" MATCH "${escaped_prefix}*" COUNT "$batch_size")
    cursor=${lines[0]}

    # Extract fields (every other line after cursor, starting at index 1)
    for ((i = 1; i < ${#lines[@]}; i += 2)); do
      field="${lines[i]}"
      [[ -z "$field" ]] && continue

      batch+=("$field")
      ((++deleted))
      ((++found_in_pass))

      if ((${#batch[@]} >= batch_size)); then
        hdel_batch "$report_name" "${batch[@]}"
        batch=()
        show_progress "$deleted" "$total_count"
      fi
    done

    [[ "$cursor" == "0" ]] && break
  done

  # Flush remaining batch from this pass
  if [[ ${#batch[@]} -gt 0 ]]; then
    hdel_batch "$report_name" "${batch[@]}"
    batch=()
    show_progress "$deleted" "$total_count"
  fi

  # Stop when a full scan finds no more matches
  [[ $found_in_pass -eq 0 ]] && break
done

show_progress "$deleted" "$total_count"
echo ""
echo "Done. Deleted $deleted paths starting with '$prefix'"
