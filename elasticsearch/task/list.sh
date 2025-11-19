#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_env
check_bins
check_elasticsearch_url

log_title "List Tasks"

curl -sXGET "$ELASTICSEARCH_URL/_tasks?detailed" | jq