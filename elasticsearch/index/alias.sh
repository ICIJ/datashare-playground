#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<alias>] [--remove|-r]'
check_env
check_bins
check_elasticsearch_url

# Strip the --remove/-r flag from anywhere in the args and keep the rest
# positional (the flag may follow the alias, so a leading shift is not enough)
remove=false
args=()
for arg in "$@"; do
  case "$arg" in
    --remove|-r) remove=true ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

index=${1:-}
alias_name=${2:-}
esindex=$ELASTICSEARCH_URL/$index

# check_usage counts the raw args, so `alias.sh --remove` clears it even though
# no index survives stripping — guard the real index here
if [[ -z "$index" ]]; then
  log_error "Usage: $0 <index> [<alias>] [--remove|-r]"
  exit 1
fi

# Report which aliases point at each matched index as a two-column table so many
# indices stay scannable (wildcards and comma-separated names work natively)
report_aliases() {
  local response=$(curl -sXGET "$esindex/_alias")
  local matched_indices=$(echo "$response" | jq -r 'keys[]?' | sort)
  if [[ -z "$matched_indices" ]]; then
    log_warn "No index matched '$index'"
    exit 1
  fi

  local index_column_width=$(longest_width "$matched_indices" "INDEX")
  table_header "INDEX:$index_column_width" "ALIAS:30"
  for name in $matched_indices; do
    log_alias_rows "$name" "$response" "$index_column_width"
  done
}

# Print one row per alias for an index; an index with no aliases still prints a
# single dimmed "-" row so every matched index is accounted for
log_alias_rows() {
  local name=$1
  local response=$2
  local index_column_width=$3
  local aliases=$(echo "$response" | jq -r ".\"$name\".aliases | keys[]?")
  if [[ -z "$aliases" ]]; then
    printf "%-${index_column_width}s ${Dimmed}%-30s${Color_Off}\n" "$name" "-"
  else
    while IFS= read -r name_alias; do
      printf "%-${index_column_width}s ${Cyan}%-30s${Color_Off}\n" "$name" "$name_alias"
    done <<< "$aliases"
  fi
}

# Return the max length among the given lines and a fallback label
# (keeps the column at least as wide as the header)
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

# Add or remove a single alias via the atomic _aliases actions API
# Usage: apply_alias_action <add|remove> <human-verb>
apply_alias_action() {
  local action=$1
  local verb=$2
  local body='{ "actions": [ { "'"$action"'": { "index": "'"$index"'", "alias": "'"$alias_name"'" } } ] }'
  local message="$verb alias '$alias_name'"
  spinner_start "$message"
  if ! curl -sXPOST "$ELASTICSEARCH_URL/_aliases" -H 'Content-Type: application/json' -d"$body" | jq -e '.acknowledged' > /dev/null; then
    spinner_error "$message"
    exit 1
  fi
  spinner_stop "$message"
}

# Removing requires an explicit alias; without one there is nothing to remove
if [[ "$remove" == true && -z "$alias_name" ]]; then
  log_error "Removing an alias requires <alias>: $0 <index> <alias> --remove"
  exit 1
fi

log_title "Alias: $index"

if [[ -z "$alias_name" ]]; then
  report_aliases
elif [[ "$remove" == true ]]; then
  apply_alias_action remove "Remove"
else
  apply_alias_action add "Add"
fi
