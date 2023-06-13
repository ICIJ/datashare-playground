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

curl -sXPOST "$ELASTICSEARCH_URL/$index/_delete_by_query" -H 'Content-Type: application/json' -d "$body"
