#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../lib/cli.sh

check_usage 1 '<index>'
check_env
check_bins
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

# More than one argument: set refresh interval
if [[ $# -gt 1 ]]; then
  body='{ "index": { "refresh_interval": "'"${2}"'" } }'
  curl -sXPUT  "$esindex/_settings" -H 'Content-Type: application/json'  -d"$body" | jq
# Only 1 argument: get the refresh interval
else
  refresh_interval=$(curl -sXGET  "$esindex/_settings" | jq ".\"$index\".settings.index.refresh_interval // empty")
  if [[ -z "$refresh_interval" ]]; then
    echo "The $index index has no refresh interval set. The default is 1s."
  else
    echo "The $index index has a refresh interval of $refresh_interval"
  fi
fi
