#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 2 '<source> <target>'
check_env
check_bins
check_elasticsearch_url

source=$1
target=$2

log_title "Replace Index"

# Skip prompt if not running interactively
if [ ! -t 1 ]; then
    curl -sXDELETE "$ELASTICSEARCH_URL/$target" > /dev/null
    $script_dir/clone.sh $source $target > /dev/null
    log_info "Index '$target' replaced with '$source'"
else
    log_warn "The '$target' index will be deleted, this action cannot be undone"
    if prompt_confirm "Do you want to replace '$target' with '$source'?"; then
        curl -sXDELETE "$ELASTICSEARCH_URL/$target" > /dev/null
        $script_dir/clone.sh $source $target > /dev/null
        log_info "Index '$target' replaced with '$source'"
    else
        log_error "Replacement aborted."
    fi
fi
