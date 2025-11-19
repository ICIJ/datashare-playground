# Text and value formatting functions
# Requires colors.sh to be sourced first

# Get terminal width
# Usage: term_width
term_width() {
    # Try tput first (works even in subshells if terminal exists)
    local width
    width=$(tput cols 2>/dev/null)
    if [[ -n "$width" && "$width" -gt 0 ]]; then
        echo "$width"
    else
        echo 80
    fi
}

# Truncate a string to fit a given width
# Usage: truncate <string> <max_width>
# Example: truncate "very long string" 10  -> "very lo..."
truncate() {
    local str=$1
    local max=$2

    # Handle edge cases
    if [[ -z "$str" ]]; then
        echo ""
        return
    fi

    if [[ $max -le 3 ]]; then
        echo "${str:0:$max}"
        return
    fi

    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$((max-3))}..."
    else
        echo "$str"
    fi
}

# Draw a horizontal line of specified length
# Usage: draw_line [<length>]
# If no length specified, uses terminal width
draw_line() {
    local length=${1:-$(term_width)}
    local line=""
    for ((i=0; i<length; i++)); do
        line+="─"
    done
    echo "$line"
}

# Format a duration from seconds to human readable
# Usage: format_duration_s <seconds>
format_duration_s() {
    local secs=$1

    # Handle edge cases
    if [[ -z "$secs" || "$secs" == "null" ]]; then
        echo "0s"
        return
    fi

    if [[ $secs -lt 0 ]]; then
        secs=0
    fi

    if [[ $secs -lt 60 ]]; then
        echo "${secs}s"
    elif [[ $secs -lt 3600 ]]; then
        local mins=$((secs / 60))
        local s=$((secs % 60))
        echo "${mins}m ${s}s"
    else
        local hours=$((secs / 3600))
        local mins=$(((secs % 3600) / 60))
        echo "${hours}h ${mins}m"
    fi
}

# Format a duration from nanoseconds to human readable
# Usage: format_duration_ns <nanoseconds>
format_duration_ns() {
    local nanos=$1

    # Handle edge cases
    if [[ -z "$nanos" || "$nanos" == "null" ]]; then
        echo "0s"
        return
    fi

    local secs=$((nanos / 1000000000))
    format_duration_s "$secs"
}

# Format status display with color
# Usage: format_status <status>
# status: "running", "completed", "failed", "pending"
format_status() {
    local status=$1
    case "$status" in
        running|Running)
            echo -e "${Cyan}Running${Color_Off}"
            ;;
        completed|Completed|true)
            echo -e "${Green}Completed${Color_Off}"
            ;;
        failed|Failed|error)
            echo -e "${Red}Failed${Color_Off}"
            ;;
        pending|Pending)
            echo -e "${BYellow}Pending${Color_Off}"
            ;;
        *)
            echo -e "$status"
            ;;
    esac
}

# Format a number with color based on type
# Usage: format_count <type> <value>
# type: "created", "updated", "deleted", "failed", "total"
format_count() {
    local type=$1
    local value=$2
    case "$type" in
        created)
            echo -e "${Green}$value${Color_Off}"
            ;;
        updated)
            echo -e "${BYellow}$value${Color_Off}"
            ;;
        deleted|failed|failures)
            echo -e "${Red}$value${Color_Off}"
            ;;
        *)
            echo -e "$value"
            ;;
    esac
}
