# Progress bar functions
# Requires colors.sh to be sourced first

# Draw a progress bar
# Usage: progress_bar <percent> [width] [color]
# Example: progress_bar 75 20 "$Purple"
progress_bar() {
    local percent=$1
    local width=${2:-20}
    local color=${3:-$Purple}

    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local bar=""

    # Build filled part
    for ((i=0; i<filled; i++)); do
        bar+="━"
    done

    # Build empty part
    local empty_bar=""
    for ((i=0; i<empty; i++)); do
        empty_bar+="─"
    done

    echo -e "${color}${bar}${Color_Off}${Dimmed}${empty_bar}${Color_Off} ${percent}%"
}
