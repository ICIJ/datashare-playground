#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_bins
check_env
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

log_title "Force merge (expunge deletes): $index"

# Start async force merge
result=$(curl -sXPOST "$esindex/_forcemerge?only_expunge_deletes=true&wait_for_completion=false")
task_id=$(echo "$result" | jq -r '.task // empty' 2>/dev/null || true)

if [[ -z "$task_id" ]]; then
    log_error "Failed to start force merge: $(echo "$result" | jq -r '.error.reason // .' 2>/dev/null || echo "$result")"
    exit 1
fi

monitor_es_task "$task_id" "Force merge (expunge deletes): $index"
