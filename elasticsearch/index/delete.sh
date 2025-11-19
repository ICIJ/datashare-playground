#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_env
check_bins
check_elasticsearch_url

log_title "Delete Index"

echo -e "${BRed}This action cannot be undone 💣${Color_Off}" 
read -p "To confirm the deletion, please enter the name of the index again: " choice
case "$choice" in
  $1 ) curl -sXDELETE "$ELASTICSEARCH_URL/$1" | jq;;
  * ) log_error "Invalid input: deletion aborted.";;
esac