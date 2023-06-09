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

# Prompt only if file descriptor fd is open and refers to a terminal.
if [ -t 1 ] ; then
  echo -e "${BRed}The \"${target}\" index will be deleted, this action cannot be undone 💣${Color_Off}" 
  read -p "To confirm the replacement, please enter the name of the target index: " choice
else
  choice=$target
fi
case "$choice" in 
  $target ) 
    curl -XDELETE "$ELASTICSEARCH_URL/$target" | jq
    $script_dir/clone.sh $source $target
    ;;
  * ) echo "Invalid input: replacement aborted.";;
esac
