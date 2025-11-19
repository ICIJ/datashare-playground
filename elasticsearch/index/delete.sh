#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Check for --force flag
force=false
if [[ "$1" == "--force" || "$1" == "-f" ]]; then
    force=true
    shift
fi

check_usage 1 '[--force|-f] <index>'
check_env
check_bins
check_elasticsearch_url

log_title "Delete Index: $1"

if [[ "$force" == true ]]; then
    spinner_start "Delete index"
    if ! curl -sXDELETE "$ELASTICSEARCH_URL/$1" | jq -e '.acknowledged' > /dev/null; then
        spinner_error "Delete index"
        exit 1
    fi
    spinner_stop "Index '$1' deleted"
else
    log_warn "This action cannot be undone"
    if prompt_confirm "Do you want to delete the index '$1'?"; then
        spinner_start "Delete index"
        if ! curl -sXDELETE "$ELASTICSEARCH_URL/$1" | jq -e '.acknowledged' > /dev/null; then
            spinner_error "Delete index"
            exit 1
        fi
        spinner_stop "Index '$1' deleted"
    else
        log_error "Deletion aborted"
    fi
fi
