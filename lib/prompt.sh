# Prompt functions
# Requires colors.sh and logging.sh to be sourced first

# Check if input is a positive confirmation
# Returns 0 for yes/y (case insensitive), 1 otherwise
# Usage: is_confirmed "$input"
is_confirmed() {
    local input=$1
    [[ "$input" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Display a confirmation prompt with muted borders
# Returns 0 if user confirms (y/yes/Y/YES), 1 otherwise
# Usage: prompt_confirm "Your question here"
prompt_confirm() {
    local question=$1

    echo -e "${Dimmed}$(draw_line)${Color_Off}"
    echo -e "> ${Bold}$question${Color_Off} ${Dimmed}(y/n)${Color_Off}"
    echo "> "
    echo -e "${Dimmed}$(draw_line)${Color_Off}"
    # Move cursor up two lines and position after "> "
    echo -ne "\033[2A\r> "
    read -r
    # Move cursor down to after the bottom line
    echo -ne "\033[2B\r"

    is_confirmed "$REPLY"
}
