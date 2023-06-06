#!/bin/bash
script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/cli.sh

check_usage 1 '<target>'
check_inotifywait
check_rsync

source="$script_dir/../"
target=$1

rsync -az --info=progress2 --partial $source $target

while inotifywait -re modify,create,delete "$source"
do
  rsync -az --info=progress2 --partial $source $target
done