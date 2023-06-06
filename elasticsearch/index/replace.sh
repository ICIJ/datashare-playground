#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh
source $script_dir/../../lib/colors.sh

check_usage 2 '<source> <target>'
check_env
check_bins
check_elasticsearch_url

source=$1
target=$2

echo -e "${BRed}The \"${target}\" index will be deleted, this action cannot be undone 💣${Color_Off}" 
read -p "To confirm the replacement, please enter the name of the target index: " choice
case "$choice" in 
  $target ) 
    curl -XDELETE "$ELASTICSEARCH_URL/$target" | jq
    $script_dir/clone.sh $source $target
    $script_dir/number_of_replicas.sh $target 1
    $script_dir/refresh_interval.sh $target 1s
    curl -XDELETE "$ELASTICSEARCH_URL/$source" | jq
    ;;
  * ) echo "Invalid input: replacement aborted.";;
esac
