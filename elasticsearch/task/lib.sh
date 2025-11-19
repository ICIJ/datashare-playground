# Task display library
# Shared functions for task scripts

# Fetch task data from Elasticsearch
# Usage: response=$(task_fetch <task_id>)
# Returns: Normalized JSON response on stdout, exit code 1 if not found
# Note: Running tasks return {nodes:{...}} format, completed tasks return {completed:true,task:{...}}
task_fetch() {
    local task_id=$1
    local response
    response=$(curl -sXGET "$ELASTICSEARCH_URL/_tasks/$task_id")

    # Check if task exists (error field present)
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        return 1
    fi

    # Check if this is a running task (nodes format) vs completed task (task format)
    if echo "$response" | jq -e '.nodes' > /dev/null 2>&1; then
        # Running task - extract from nodes structure and normalize
        local task_data
        task_data=$(echo "$response" | jq --arg id "$task_id" '
            .nodes | to_entries[0].value.tasks[$id] // empty
        ')

        if [[ -z "$task_data" || "$task_data" == "null" ]]; then
            return 1
        fi

        # Normalize to completed task format
        echo "{\"completed\": false, \"task\": $task_data}"
    else
        # Already in completed task format
        echo "$response"
    fi
}

# Parse task response and set global variables
# Usage: task_parse <response>
task_parse() {
    local response=$1

    TASK_COMPLETED=$(echo "$response" | jq -r '.completed')
    TASK_NODE=$(echo "$response" | jq -r '.task.node')
    TASK_ACTION=$(echo "$response" | jq -r '.task.action')
    TASK_DESCRIPTION=$(echo "$response" | jq -r '.task.description // "-"')
    TASK_START_MS=$(echo "$response" | jq -r '.task.start_time_in_millis')
    TASK_RUNNING_NS=$(echo "$response" | jq -r '.task.running_time_in_nanos')

    # Parse progress info
    if [[ "$TASK_COMPLETED" == "true" ]]; then
        TASK_TOTAL=$(echo "$response" | jq -r '.response.total // .task.status.total // 0')
        TASK_CREATED=$(echo "$response" | jq -r '.response.created // .task.status.created // 0')
        TASK_UPDATED=$(echo "$response" | jq -r '.response.updated // .task.status.updated // 0')
        TASK_DELETED=$(echo "$response" | jq -r '.response.deleted // .task.status.deleted // 0')
        TASK_FAILURES=$(echo "$response" | jq -r '.response.failures | length // 0')
    else
        TASK_TOTAL=$(echo "$response" | jq -r '.task.status.total // 0')
        TASK_CREATED=$(echo "$response" | jq -r '.task.status.created // 0')
        TASK_UPDATED=$(echo "$response" | jq -r '.task.status.updated // 0')
        TASK_DELETED=$(echo "$response" | jq -r '.task.status.deleted // 0')
        TASK_FAILURES=0
    fi

    # Calculate derived values
    TASK_PROCESSED=$((TASK_CREATED + TASK_UPDATED + TASK_DELETED))
    if [[ "$TASK_TOTAL" != "0" && "$TASK_TOTAL" != "null" && $TASK_TOTAL -gt 0 ]]; then
        TASK_PERCENT=$((TASK_PROCESSED * 100 / TASK_TOTAL))
    else
        TASK_PERCENT=0
    fi

    TASK_DURATION=$(format_duration_ns "$TASK_RUNNING_NS")
    TASK_START_TIME=$(date -d "@$((TASK_START_MS / 1000))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
}

# Display task details in table format
# Usage: task_display <task_id> <completed> <node> <action> <start_time> <duration> <total> <created> <updated> <deleted> <failures> <percent>
task_display() {
    local task_id=$1
    local completed=$2
    local node=$3
    local action=$4
    local start_time=$5
    local duration=$6
    local total=$7
    local created=$8
    local updated=$9
    local deleted=${10}
    local failures=${11}
    local percent=${12}

    # Calculate available width for values (terminal width - field column - spacing)
    local width=$(term_width)
    local field_width=15
    local value_width=$((width - field_width - 2))
    [[ $value_width -lt 20 ]] && value_width=20

    # Status with color
    local status_display
    if [[ "$completed" == "true" ]]; then
        status_display=$(format_status "completed")
    else
        status_display=$(format_status "running")
    fi

    # Shorten action for display
    local short_action=$(echo "$action" | sed 's/indices:data\/write\///' | sed 's/indices:admin\///')

    echo ""
    table_header "FIELD:$field_width" "VALUE:$value_width"
    echo -e "$(printf '%-15s' 'Status') $status_display"
    echo -e "$(printf '%-15s' 'Task ID') ${Cyan}$(truncate "$task_id" "$value_width")${Color_Off}"
    echo -e "$(printf '%-15s' 'Node') $(truncate "$node" "$value_width")"
    echo -e "$(printf '%-15s' 'Action') $(truncate "$short_action" "$value_width")"
    echo -e "$(printf '%-15s' 'Started') $start_time"
    echo -e "$(printf '%-15s' 'Duration') ${BYellow}$duration${Color_Off}"

    # Show progress if we have total > 0
    if [[ "$total" != "0" && "$total" != "null" ]]; then
        # Adjust progress bar width based on terminal
        local bar_width=$((value_width - 6))
        [[ $bar_width -lt 10 ]] && bar_width=10
        [[ $bar_width -gt 40 ]] && bar_width=40
        echo -e "$(printf '%-15s' 'Progress') $(progress_bar "$percent" "$bar_width")"
        echo -e "$(printf '%-15s' 'Total') $total"
        [[ "$created" != "0" ]] && echo -e "$(printf '%-15s' 'Created') $(format_count created "$created")"
        [[ "$updated" != "0" ]] && echo -e "$(printf '%-15s' 'Updated') $(format_count updated "$updated")"
        [[ "$deleted" != "0" ]] && echo -e "$(printf '%-15s' 'Deleted') $(format_count deleted "$deleted")"
        [[ "$failures" != "0" && "$failures" != "null" ]] && echo -e "$(printf '%-15s' 'Failures') $(format_count failures "$failures")"
    fi

    echo ""
}
