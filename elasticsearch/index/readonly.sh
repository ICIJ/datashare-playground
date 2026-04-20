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

# Report readonly state for every index matched by the input pattern
# (wildcards and comma-separated names work natively against the ES settings API)
report_readonly_status() {
  local settings=$(curl -sXGET "$esindex/_settings")
  local matched_indices=$(echo "$settings" | jq -r 'keys[]?')
  if [[ -z "$matched_indices" ]]; then
    log_warn "No index matched '$index'"
    exit 1
  fi
  for name in $matched_indices; do
    log_readonly_status "$name" "$settings"
  done
}

# Log whether a single index has blocks.write set to true
# (ES omits the setting when it has never been set — treat missing as false)
log_readonly_status() {
  local name=$1
  local settings=$2
  local blocks_write=$(echo "$settings" | jq -r ".\"$name\".settings.index.blocks.write // \"false\"")
  if [[ "$blocks_write" == "true" ]]; then
    log_info "The $name index is readonly"
  else
    log_info "The $name index is not readonly"
  fi
}

log_title "Readonly: $index"

# A second argument means the caller wants to toggle the flag, not read it
if [[ $# -gt 1 ]]; then
  set_readonly "$2"
else
  report_readonly_status
fi
