#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh
source $script_dir/lib.sh

check_usage 1 '<task_id>'
check_bins
check_env
check_elasticsearch_url

task_id=$1

log_title "Get Task: $task_id"

# Fetch task
response=$(task_fetch "$task_id") || {
    log_error "Task not found: $task_id"
    exit 1
}

# Parse and display
task_parse "$response"
task_display "$task_id" "$TASK_COMPLETED" "$TASK_NODE" "$TASK_ACTION" \
    "$TASK_START_TIME" "$TASK_DURATION" "$TASK_TOTAL" "$TASK_CREATED" \
    "$TASK_UPDATED" "$TASK_DELETED" "$TASK_FAILURES" "$TASK_PERCENT"
