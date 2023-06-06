#!/bin/bash

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<task_id>'
check_env
check_bins
check_elasticsearch_url

task_id=$1
curl -sXPOST "$ELASTICSEARCH_URL/_tasks/$task_id/_cancel" | jq
