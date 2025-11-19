#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_env
check_bins
check_elasticsearch_url

log_title "List Tasks"

# Fetch all tasks
response=$(curl -sXGET "$ELASTICSEARCH_URL/_tasks?detailed&group_by=none")

# Check if there are any tasks
task_count=$(echo "$response" | jq '.tasks | length')

if [[ "$task_count" == "0" || "$task_count" == "null" ]]; then
    log_info "No running tasks"
    exit 0
fi

# Print table header
table_header "TASK ID:45" "ACTION:40" "TIME:10"

# Process each task
echo "$response" | jq -r '.tasks[] | [
    (.node + ":" + (.id | tostring)),
    .action,
    .running_time_in_nanos
] | @tsv' | while IFS=$'\t' read -r task_id action running_time_nanos; do
    # Format duration
    duration=$(format_duration_ns "$running_time_nanos")

    # Shorten action for display
    short_action=$(echo "$action" | sed 's/indices:data\/write\///' | sed 's/indices:admin\///')

    # Print row with colors
    printf "${Cyan}%-45s${Color_Off} %-40s ${BYellow}%-10s${Color_Off}\n" \
        "$task_id" "$short_action" "$duration"
done

echo ""
log_kv "Total running tasks" "$task_count"
