#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<number>]'
check_env
check_bins
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

log_title "Number of Replicas: $index"

# More than one argument: set number of replicas
if [[ $# -gt 1 ]]; then
  body='{ "index": { "number_of_replicas": '"${2}"' } }'
  spinner_start "Set number of replicas to ${2}"
  if ! curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d"$body" | jq -e '.acknowledged' > /dev/null; then
      spinner_error "Set number of replicas to ${2}"
      exit 1
  fi
  spinner_stop "Number of replicas set to ${2}"
# Only 1 argument: get the number of replicas
else
  replicas=$(curl -sXGET "$esindex/_settings" | jq -r ".\"$index\".settings.index.number_of_replicas // empty")
  if [[ -z "$replicas" ]]; then
    log_info "The $index index has no replicas number set"
  else
    log_info "The $index index has $replicas replica(s)"
  fi
fi
