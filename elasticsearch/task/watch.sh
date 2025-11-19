#!/bin/bash

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<task_id>'
check_bins

task_id=$1

log_title "Watch Task"

watch --color '"'"${script_dir}"'"/get.sh "'"${task_id}"'"'
