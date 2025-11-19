# Logging functions
# Requires colors.sh and format.sh to be sourced first

# Task list for organized output
_TASK_HEADER=""
_TASK_LIST=()

# Spinner variables
_SPINNER_PID=""
_SPINNER_MSG=""

# Start a spinner with a message
# Usage: spinner_start "message"
spinner_start() {
    _SPINNER_MSG="$1"

    # Only show spinner if running interactively
    [ -t 1 ] || return 0

    # Print initial spinner state
    echo -ne "${Cyan}⠋${Color_Off} ${_SPINNER_MSG}"

    (
        trap 'exit 0' TERM
        local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local i=0
        local len=${#chars}
        while true; do
            local char="${chars:$i:1}"
            echo -ne "\r${Cyan}${char}${Color_Off} ${_SPINNER_MSG}"
            i=$(( (i + 1) % len ))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    disown $_SPINNER_PID
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
                fi
                return 1
            fi

            if [ -t 1 ]; then
                spinner_stop "$message"
            fi
            return 0
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
