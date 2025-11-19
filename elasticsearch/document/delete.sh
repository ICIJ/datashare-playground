#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<path>] [<query_string>]'
check_bins
check_env
check_elasticsearch_url

index=$1
path=${2:-/}
query_string=${3:-'*:*'}

log_title "Delete Documents: $index"

log_kv "Path" "$path"

body='{
  "query": {
    "bool" : {
      "must" : [
        {
          "query_string": {
            "query": "'"${query_string}"'"
          }
        },
        {
          "prefix": {
            "path": "'"${path}"'"
          }
        },
        {
          "term" : {
            "type" : "Document"
          }
        }
      ]
    }
  }
}'

# Start async delete
result=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_delete_by_query?wait_for_completion=false" -H 'Content-Type: application/json' -d "$body")
task_id=$(echo "$result" | jq -r '.task')

if [[ "$task_id" == "null" || -z "$task_id" ]]; then
    log_error "Failed to start delete task"
    exit 1
fi

monitor_es_task "$task_id" "Delete documents"
