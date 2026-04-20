#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [true|false]'
check_env
check_bins
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

# Update the readonly flag on every matched index in one PUT
# (uses index.blocks.write — the same block that clone.sh toggles —
# which stops writes while keeping data readable)
set_readonly() {
  local value=$1
  local message="Set readonly to $value"
  local body='{ "index": { "blocks.write": '"$value"' } }'
  spinner_start "$message"
  if ! curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d"$body" | jq -e '.acknowledged' > /dev/null; then
    spinner_error "$message"
    exit 1
  fi
  spinner_stop "$message"
}

# Report readonly state as a two-column table so many indices stay scannable
# (wildcards and comma-separated names work natively against the ES settings API)
report_readonly_status() {
  local settings=$(curl -sXGET "$esindex/_settings")
  local matched_indices=$(echo "$settings" | jq -r 'keys[]?' | sort)
  if [[ -z "$matched_indices" ]]; then
    log_warn "No index matched '$index'"
    exit 1
  fi

  # Size the INDEX column to the longest name so rows align even for long IDs
  local index_column_width=$(longest_width "$matched_indices" "INDEX")
  table_header "INDEX:$index_column_width" "READONLY:10"
  for name in $matched_indices; do
    log_readonly_row "$name" "$settings" "$index_column_width"
  done
}

# Print one table row per index, coloring the status so readonly stands out
# (ES omits blocks.write entirely when it has never been set — treat missing as false)
log_readonly_row() {
  local name=$1
  local settings=$2
  local index_column_width=$3
  local blocks_write=$(echo "$settings" | jq -r ".\"$name\".settings.index.blocks.write // \"false\"")
  if [[ "$blocks_write" == "true" ]]; then
    printf "%-${index_column_width}s ${Green}%-10s${Color_Off}\n" "$name" "yes"
  else
    printf "%-${index_column_width}s ${Dimmed}%-10s${Color_Off}\n" "$name" "no"
  fi
}

# Return the max length among the given lines and a fallback label
# (the label keeps the column at least wide enough to fit the header)
longest_width() {
  local lines=$1
  local fallback=$2
  local max=${#fallback}
  while IFS= read -r line; do
    if [[ ${#line} -gt $max ]]; then
      max=${#line}
    fi
  done <<< "$lines"
  echo "$max"
}

log_title "Readonly: $index"

# A second argument means the caller wants to toggle the flag, not read it
if [[ $# -gt 1 ]]; then
  set_readonly "$2"
else
  report_readonly_status
fi
