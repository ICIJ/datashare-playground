#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<task_id>'
check_bins
check_env
check_elasticsearch_url

task_id=$1

log_title "Get Task"

curl -sXGET "$ELASTICSEARCH_URL/_tasks/$task_id" | jq -C
