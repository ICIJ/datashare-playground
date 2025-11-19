#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<interval>]'
check_env
check_bins
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

log_title "Refresh Interval: $index"

# More than one argument: set refresh interval
if [[ $# -gt 1 ]]; then
  body='{ "index": { "refresh_interval": "'"${2}"'" } }'
  spinner_start "Set refresh interval to ${2}"
  if ! curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d"$body" | jq -e '.acknowledged' > /dev/null; then
      spinner_error "Set refresh interval to ${2}"
      exit 1
  fi
  spinner_stop "Refresh interval set to ${2}"
# Only 1 argument: get the refresh interval
else
  refresh_interval=$(curl -sXGET "$esindex/_settings" | jq -r ".\"$index\".settings.index.refresh_interval // empty")
  if [[ -z "$refresh_interval" ]]; then
    log_info "The $index index has no refresh interval set (default: 1s)"
  else
    log_info "The $index index has a refresh interval of $refresh_interval"
  fi
fi
