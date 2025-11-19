#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_env
check_bins
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

log_title "Refresh Index: $index"

spinner_start "Refresh index"
if ! curl -sXPOST "$esindex/_refresh" | jq -e '._shards.successful' > /dev/null; then
    spinner_error "Refresh index"
    exit 1
fi
spinner_stop "Index '$index' refreshed"
