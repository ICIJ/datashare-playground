#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../lib/cli.sh

check_usage 3 '<index> <path> <new_path>'
check_bins
check_env
check_elasticsearch_url

index=$1
path=${2%/};
new_path=${3%/};

# Script to be used in the update by query
script='
  if (ctx._source.path != null) {
    ctx._source.path = ctx._source.path.replace(params.path, params.new_path); 
  }

  if (ctx._source.dirname != null) {
    ctx._source.dirname = ctx._source.dirname.replace(params.path, params.new_path);
  }
'

# Building the request body for the update by query
body='{
  "query": {
    "bool" : {
      "must" : [
        {
          "prefix": {
            "dirname": "'"${path}"'"
          }
        },
        {
          "term" : {
            "type" : "Document"
          }
        }
      ]
    }
  },
  "script": {
    "source": "'"${script//$'\n'/}"'",
    "lang": "painless",
    "params": {
      "path": "'"${path}"'",
      "new_path": "'"${new_path}"'"
    }
  }
}'

curl -sXPOST "$ELASTICSEARCH_URL/$index/_update_by_query?wait_for_completion=false" -H 'Content-Type: application/json' -d "$body" | jq