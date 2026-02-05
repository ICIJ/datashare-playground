#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 2 '<index> <from_date> [<to_date>]'
check_bins
check_env
check_elasticsearch_url

index=$1
from_date=$2
to_date=${3:-}

# Convert YYYYMMDD to ISO 8601 datetime format (required by date_time field)
from_iso="${from_date:0:4}-${from_date:4:2}-${from_date:6:2}T00:00:00.000Z"

# Build range query (conditional upper bound)
if [[ -n "$to_date" ]]; then
    to_iso="${to_date:0:4}-${to_date:4:2}-${to_date:6:2}T00:00:00.000Z"
    range_query='"gte": "'"$from_iso"'", "lt": "'"$to_iso"'"'
else
    range_query='"gte": "'"$from_iso"'"'
fi

log_title "Count Documents Indexed Since: ${from_date:0:4}-${from_date:4:2}-${from_date:6:2}"

body='{
  "query": {
    "bool": {
      "must": [
        {
          "range": {
            "extractionDate": {
              '"$range_query"'
            }
          }
        },
        {
          "term": {
            "type": "Document"
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
