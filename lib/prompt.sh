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

    # Throw away anything you typed while the previous step was running. On a long
    # operation you press enter to check the terminal is still alive, those newlines queue
    # up in the tty buffer and the next read takes one, sees an empty answer and reads it
    # as a no. Only on a real terminal, piped input is the answer, not leftovers.
    if [ -t 0 ]; then
        while read -r -t 0 2>/dev/null; do
            read -r -t 0.1 _discard 2>/dev/null || break
        done
    fi

    # Ask again rather than reading anything unrecognised as "no". A silent "no" to
    # "delete the backup?" is a decision the operator did not make.
    while true; do
        echo -e "${Dimmed}$(draw_line)${Color_Off}"
        echo -e "> ${Bold}$question${Color_Off} ${Dimmed}(y/n)${Color_Off}"
        echo "> "
        echo -e "${Dimmed}$(draw_line)${Color_Off}"
        # Move cursor up two lines and position after "> "
        echo -ne "\033[2A\r> "
        if ! read -r; then
            # EOF: no answer is coming, so take the cautious branch.
            echo -ne "\033[2B\r"
            return 1
        fi
        # Move cursor down to after the bottom line
        echo -ne "\033[2B\r"

        case "$REPLY" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo])     return 1 ;;
            *) log_warn "Answer y or n." ;;
        esac
    done
}
