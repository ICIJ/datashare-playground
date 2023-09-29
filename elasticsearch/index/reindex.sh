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

body='{
  "source": {
    "index": "'"${source}"'",
    "query": {
      "query_string": {
        "query": "'"${query_string}"'" 
      }
    },
    "_source": {                                                                                                                                                                                                   
      "excludes": [
        "metadata.tika_metadata_x_*", 
        "metadata.tika_metadata_unknown_tag_*", 
        "metadata.tika_metadata_custom_*",
        "metadata.tika_metadata_mboxparser_*",
        "metadata.tika_metadata_message_raw_header_x_*",
        "metadata.tika_metadata_message_raw_header_1*",
        "metadata.tika_metadata_message_raw_header_2*",
        "metadata.tika_metadata_message_raw_header_3*",
        "metadata.tika_metadata_message_raw_header_4*",
        "metadata.tika_metadata_message_raw_header_5*",
        "metadata.tika_metadata_message_raw_header__*"
      ] 
    }
  },
  "dest": {
    "index": "'"${target}"'"
  }
}'

curl -sXPOST "$ELASTICSEARCH_URL/_reindex?wait_for_completion=false" -H 'Content-Type: application/json' -d "$body" | jq
