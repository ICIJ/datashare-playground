#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 3 '<index> <path> <new_path>'
check_bins
check_env
check_elasticsearch_url

index=$1
path=${2%/};
new_path=${3%/};

log_title "Move Documents: $index"

log_kv "From" "$path"
log_kv "To" "$new_path"

# The slashed prefix is a param so the painless source needs no character literals
script='
if (ctx._source.path != null && ctx._source.path.startsWith(params.old_prefix)) {
  ctx._source.path = params.new + ctx._source.path.substring(params.old.length());
}
if (ctx._source.dirname != null && (ctx._source.dirname == params.old || ctx._source.dirname.startsWith(params.old_prefix))) {
  ctx._source.dirname = params.new + ctx._source.dirname.substring(params.old.length());
}
'

body=$(jq -nc --arg old "$path" --arg new "$new_path" --arg src "$script" '{
  query: { prefix: { path: ($old + "/") } },
  script: {
    lang: "painless",
    source: $src,
    params: { old: $old, new: $new, old_prefix: ($old + "/") }
  }
}')

log_kv "Matches" "$(count_es_documents "$index" "$(echo "$body" | jq -c '{query}')")"

# Start async update
result=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_update_by_query?wait_for_completion=false&refresh=true&slices=auto&scroll_size=10000" -H 'Content-Type: application/json' -d "$body")
task_id=$(echo "$result" | jq -r '.task')

if [[ "$task_id" == "null" || -z "$task_id" ]]; then
    log_error "Failed to start move task"
    exit 1
fi

monitor_es_task "$task_id" "Move documents"
