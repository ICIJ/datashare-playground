#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<query_string>]'
check_bins
check_env
check_elasticsearch_url

index=$1
query_string=${2:-'*:*'}

log_title "Count Duplicates: $index"

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
          "term" : {
            "type" : "Duplicate"
          }
        }
      ]
    }
  }
}'

spinner_start "Count duplicates"
count=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_count" -H 'Content-Type: application/json' -d "$body" | jq '.count')

if [ -t 1 ]; then
    spinner_stop "Count duplicates"
    log_kv "Duplicates" "$count"
else
    echo "$count"
fi
