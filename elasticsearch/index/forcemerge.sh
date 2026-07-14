#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_bins
check_env
check_elasticsearch_url

index=$1

log_title "Force merge (expunge deletes): $index"

# This outputs JSON with a task id for the caller to track (see task/get.sh)
curl -sXPOST "$ELASTICSEARCH_URL/$index/_forcemerge?only_expunge_deletes=true&wait_for_completion=false" \
  -H 'Content-Type: application/json'
