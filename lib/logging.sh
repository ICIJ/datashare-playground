# Logging functions
# Requires colors.sh and format.sh to be sourced first

# Task list for organized output
_TASK_HEADER=""
_TASK_LIST=()

# Spinner variables
_SPINNER_PID=""
_SPINNER_MSG=""
_SPINNER_MSG_FILE=""

# Start a spinner with a message
# Usage: spinner_start "message"
spinner_start() {
    _SPINNER_MSG="$1"

    # Only show spinner if running interactively
    [ -t 1 ] || return 0

    # The spinner runs in a subshell, so live message updates go through a file
    _SPINNER_MSG_FILE=$(mktemp)
    printf '%s' "$_SPINNER_MSG" > "$_SPINNER_MSG_FILE"

    # Print initial spinner state
    echo -ne "${Cyan}⠋${Color_Off} ${_SPINNER_MSG}"

    (
        trap 'exit 0' TERM
        local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local i=0
        local len=${#chars}
        while true; do
            local char="${chars:$i:1}"
            local msg
            msg=$(<"$_SPINNER_MSG_FILE")
            echo -ne "\r\033[K${Cyan}${char}${Color_Off} ${msg}"
            i=$(( (i + 1) % len ))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    disown $_SPINNER_PID
}

# Update the message of a running spinner
# Usage: spinner_update "message"
spinner_update() {
    _SPINNER_MSG="$1"
    [[ -n "$_SPINNER_MSG_FILE" ]] && printf '%s' "$1" > "$_SPINNER_MSG_FILE"
    return 0
}

# Stop spinner and show success
# Usage: spinner_stop "message"
spinner_stop() {
    local msg="${1:-$_SPINNER_MSG}"

    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        sleep 0.1
        _SPINNER_PID=""
        # Clear spinner line
        echo -ne "\r\033[K"
    fi
    [[ -n "$_SPINNER_MSG_FILE" ]] && rm -f "$_SPINNER_MSG_FILE" && _SPINNER_MSG_FILE=""

    echo -e "${Green}✓${Color_Off} ${msg}"
}

# Stop spinner and show error
# Usage: spinner_error "message"
spinner_error() {
    local msg="${1:-$_SPINNER_MSG}"

    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        sleep 0.1
        _SPINNER_PID=""
        # Clear spinner line
        echo -ne "\r\033[K"
    fi
    [[ -n "$_SPINNER_MSG_FILE" ]] && rm -f "$_SPINNER_MSG_FILE" && _SPINNER_MSG_FILE=""

    echo -e "${Red}✗${Color_Off} ${msg}"
}

# Print a key-value pair
# Usage: log_kv "key" "value"
log_kv() {
    echo -e "$1: ${Bold}$2${Color_Off}"
}

# Print a section header
# Usage: log_section "header"
log_section() {
    echo -e "\n${Bold}$1:${Color_Off}"
}

# Print a task as completed
# Usage: log_task "task description"
log_task() {
    echo -e "${Green}✓${Color_Off} $1"
}

# Print a task as failed
# Usage: log_task_error "task description"
log_task_error() {
    echo -e "${Red}✗${Color_Off} $1"
}

# Print a task as warning
# Usage: log_task_warn "task description"
log_task_warn() {
    echo -e "${BYellow}!${Color_Off} $1"
}

# Simple log functions (with left margin)
log_info() {
    echo -e "${Green}✓${Color_Off} $1"
}

log_warn() {
    echo -e "${BYellow}!${Color_Off} $1"
}

log_error() {
    echo -e "${Red}✗${Color_Off} $1"
}

# Compute the completion percentage of an Elasticsearch task
# Usage: es_task_progress <task_status_json> [<child_tasks_json>]
# Outputs an integer percent, or nothing when the total is unknown.
# A sliced parent task only aggregates completed slices, so the running
# slices' counters must be added from a _tasks?parent_task_id listing.
es_task_progress() {
    jq -rn --argjson parent "$1" --argjson children "${2:-null}" '
        def done: (.updated // 0) + (.created // 0) + (.deleted // 0) + (.noops // 0) + (.version_conflicts // 0);
        ($parent.task.status // {}) as $p
        | [$children.nodes[]?.tasks[]?.status // empty] as $slices
        | (($p.total // 0) + ([$slices[].total // 0] | add // 0)) as $total
        | (($p | done) + ([$slices[] | done] | add // 0)) as $done
        | if $total > 0 then ($done * 100 / $total | floor) else empty end
    '
}

# Monitor an async Elasticsearch task
# Usage: monitor_es_task <task_id> <message>
# Returns the final task response
monitor_es_task() {
    local task_id=$1
    local message=$2

    # Only show spinner if running interactively
    if [ -t 1 ]; then
        spinner_start "$message"
    fi

    while true; do
        local task_status
        task_status=$(curl -s "$ELASTICSEARCH_URL/_tasks/$task_id")
        local completed
        completed=$(echo "$task_status" | jq -r '.completed')

        if [[ "$completed" == "true" ]]; then
            local failures
            failures=$(echo "$task_status" | jq -r '.response.failures | length')

            if [[ "$failures" != "0" && "$failures" != "null" ]]; then
                if [ -t 1 ]; then
                    spinner_error "$message"
                else
                    log_error "$message failed"
                fi
                return 1
            fi

            if [ -t 1 ]; then
                spinner_stop "$message"
            fi
            return 0
        fi

        if [ -t 1 ]; then
            local percent children
            children=$(curl -s "$ELASTICSEARCH_URL/_tasks?parent_task_id=$task_id&detailed=true")
            percent=$(es_task_progress "$task_status" "$children" 2>/dev/null) || percent=""
            if [[ -n "$percent" ]]; then
                spinner_update "$message (${percent}%)"
            fi
        fi
        sleep 2
    done
}

# Log a title/step header with rounded box
# Only displays if running interactively (stdout is a terminal)
# Usage: log_title <title>
log_title() {
    # Skip if not running interactively
    [ -t 1 ] || return 0

    local title=$1
    local length=$((${#title} + 2))
    local line=$(draw_line "$length")
    echo -e "╭${line}╮"
    echo -e "│ ${Bold}${title}${Color_Off} │"
    echo -e "╰${line}╯"
}
