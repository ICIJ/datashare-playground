#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 2 '<source> <target>'
check_env
check_bins
check_elasticsearch_url

source=$1
target=$2

log_title "Replace Index: $target ← $source"

do_replace() {
    spinner_start "Delete target index"
    if ! curl -sXDELETE "$ELASTICSEARCH_URL/$target" | jq -e '.acknowledged' > /dev/null; then
        spinner_error "Delete target index"
        exit 1
    fi
    spinner_stop "Delete target index"

    spinner_start "Clone source to target"
    $script_dir/clone.sh $source $target > /dev/null
    spinner_stop "Index '$target' replaced with '$source'"
}

# Skip prompt if not running interactively
if [ ! -t 1 ]; then
    do_replace
else
    log_warn "The '$target' index will be deleted, this action cannot be undone"
    if prompt_confirm "Do you want to replace '$target' with '$source'?"; then
        do_replace
    else
        log_error "Replacement aborted"
    fi
fi
