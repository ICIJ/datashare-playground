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

log_title "Reindex Documents"

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

curl -sXPOST "$ELASTICSEARCH_URL/_reindex?wait_for_completion=false" -H 'Content-Type: application/json' -d "$body" | jq
