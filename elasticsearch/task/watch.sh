#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh
source $script_dir/lib.sh

check_usage 1 '<task_id>'
check_bins
check_env
check_elasticsearch_url

task_id=$1
interval=${2:-2}

log_title "Watch Task: $task_id"

# Initial fetch to check if task exists
response=$(task_fetch "$task_id") || {
    log_error "Task not found: $task_id"
    exit 1
}

# Count lines in task_display output for clearing
task_parse "$response"
display_lines=$(task_display "$task_id" "$TASK_COMPLETED" "$TASK_NODE" "$TASK_ACTION" \
    "$TASK_START_TIME" "$TASK_DURATION" "$TASK_TOTAL" "$TASK_CREATED" \
    "$TASK_UPDATED" "$TASK_DELETED" "$TASK_FAILURES" "$TASK_PERCENT" | wc -l)

# Watch loop
first_run=true
while true; do
    response=$(task_fetch "$task_id") || {
        echo ""
        log_error "Error fetching task status"
        exit 1
    }

    task_parse "$response"

    # Clear previous output (except on first run)
    if [[ "$first_run" == false ]]; then
        # Move cursor up and clear lines
        for ((i=0; i<display_lines; i++)); do
            echo -ne "\033[A\033[K"
        done
    fi
    first_run=false

    # Display task table
    task_display "$task_id" "$TASK_COMPLETED" "$TASK_NODE" "$TASK_ACTION" \
        "$TASK_START_TIME" "$TASK_DURATION" "$TASK_TOTAL" "$TASK_CREATED" \
        "$TASK_UPDATED" "$TASK_DELETED" "$TASK_FAILURES" "$TASK_PERCENT"

    sleep "$interval"
done
