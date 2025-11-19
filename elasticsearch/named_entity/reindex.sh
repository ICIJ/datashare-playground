#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 2 '<source> <target> [<query_string>]'
check_bins
check_env
check_elasticsearch_url

source=$1
target=$2
query_string=${3:-'*:*'}

log_title "Reindex Named Entities"

body='{
  "source": {
    "index": "'"${source}"'",
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
              "type" : "NamedEntity" 
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

curl -sXPOST "$ELASTICSEARCH_URL/_reindex?wait_for_completion=false" -H 'Content-Type: application/json' -d "$body" | jq
