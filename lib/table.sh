# Table formatting functions
# Requires colors.sh and format.sh to be sourced first

# Print a table header
# Usage: table_header "COL1:width" "COL2:width" ...
# Example: table_header "TASK ID:45" "ACTION:35" "TIME:10"
table_header() {
    local format=""
    local names=()

    for col in "$@"; do
        local name="${col%%:*}"
        local width="${col##*:}"
        format+="%-${width}s "
        names+=("$name")
    done

    # Print header with bold
    printf "${Bold}${format}${Color_Off}\n" "${names[@]}"
    draw_line "$(term_width)"
}

# Print a table row
# Usage: table_row "value1" "value2" ... -- "width1" "width2" ...
table_row() {
    local values=()
    local widths=()
    local in_widths=false

    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            in_widths=true
            continue
        fi

        if [[ "$in_widths" == true ]]; then
            widths+=("$arg")
        else
            values+=("$arg")
        fi
    done

    local format=""
    for width in "${widths[@]}"; do
        format+="%-${width}s "
    done

    printf "${format}\n" "${values[@]}"
}
