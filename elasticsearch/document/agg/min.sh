#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../../lib/cli.sh
source $script_dir/lib.sh

check_usage 2 '<index> <field> [<path>] [<query_string>]'
check_bins
check_env
check_elasticsearch_url

index=$1
field=$2
path=${3:-/}
path=${path%/}
query_string=${4:-'*:*'}

log_title "Minimum: $field"

if [ -t 1 ]; then
    spinner_start "Calculating minimum"
fi

result=$(agg_query "$index" "$field" "min" "$path" "$query_string")

if [ -t 1 ]; then
    spinner_stop "Calculating minimum"
    log_kv "Minimum of $field" "$result"
else
    echo "$result"
fi
