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

# Hide cursor for cleaner display
tput civis 2>/dev/null || true

# Trap to ensure cursor is restored on exit
trap 'tput cnorm 2>/dev/null || true; echo' EXIT INT TERM

# Watch loop
first_run=true
display_lines=0
while true; do
    # Fetch and prepare output BEFORE clearing screen
    response=$(task_fetch "$task_id") || {
        echo ""
        log_error "Error fetching task status"
        exit 1
    }

    task_parse "$response"

    # Prepare complete output buffer
    output=$(task_display "$task_id" "$TASK_COMPLETED" "$TASK_NODE" "$TASK_ACTION" \
        "$TASK_START_TIME" "$TASK_DURATION" "$TASK_TOTAL" "$TASK_CREATED" \
        "$TASK_UPDATED" "$TASK_DELETED" "$TASK_FAILURES" "$TASK_PERCENT")

    # Count lines properly (including last line without newline)
    new_display_lines=$(printf "%s" "$output" | grep -c "^" || echo 0)

    # Now do the clear and redraw atomically
    if [[ "$first_run" == false ]]; then
        # Use ANSI escape to move cursor up N lines in one operation
        printf "\033[%dA" "$display_lines"
        # Clear from cursor to end of screen
        printf "\033[J"
    fi
    first_run=false

    # Display the pre-rendered output
    printf "%s\n" "$output"
    display_lines=$new_display_lines

    sleep "$interval"
done
