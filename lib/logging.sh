# Logging functions
# Requires colors.sh to be sourced first

log_info() {
    echo -e "${Green}[INFO]${Color_Off} $1"
}

log_warn() {
    echo -e "${BYellow}[WARN]${Color_Off} $1"
}

log_error() {
    echo -e "${Red}[ERROR]${Color_Off} $1"
}

# Draw a horizontal line of specified length
# Usage: draw_line <length>
draw_line() {
    local length=$1
    local line=""
    for ((i=0; i<length; i++)); do
        line+="─"
    done
    echo "$line"
}

# Log a title with rounded box border
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
