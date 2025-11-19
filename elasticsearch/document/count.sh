#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<path>] [<query_string>]'
check_bins
check_env
check_elasticsearch_url

index=$1
path=${2:-/}
path=${path%/}
query_string=${3:-'*:*'}

log_title "Count Documents: $index"

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

if [ -t 1 ]; then
    spinner_start "Count documents"
fi

count=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_count" -H 'Content-Type: application/json' -d "$body" | jq '.count')

if [ -t 1 ]; then
    spinner_stop "Count documents"
    log_kv "Documents" "$count"
else
    echo "$count"
fi
