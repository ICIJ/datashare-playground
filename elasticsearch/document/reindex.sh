#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 3 '<source> <target> <path>'
check_bins
check_env
check_elasticsearch_url

source=$1
target=$2
path=${3%/};

log_title "Reindex Documents: $source → $target"

log_kv "Path" "$path"

body='{
  "source": {
    "index": "'"${source}"'",
    "query": {
      "bool" : {
        "must" : [
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
  },
  "dest": {
    "index": "'"${target}"'"
  }
}'

# Start async reindex
result=$(curl -sXPOST "$ELASTICSEARCH_URL/_reindex?wait_for_completion=false" -H 'Content-Type: application/json' -d "$body")
task_id=$(echo "$result" | jq -r '.task')

if [[ "$task_id" == "null" || -z "$task_id" ]]; then
    log_error "Failed to start reindex task"
    exit 1
fi

monitor_es_task "$task_id" "Reindex documents"
