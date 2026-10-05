#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Optional --batch-size|-b flag: how many documents per bulk request
batch_size=1000
while [[ "$1" == "--batch-size" || "$1" == "-b" ]]; do
  batch_size=$2
  shift 2
done

check_usage 2 '[--batch-size|-b <n>] <source> <target> [<query_string>]'
check_bins
check_env
check_elasticsearch_url

source=$1
target=$2
query_string=${3:-'*:*'}

log_title "Reindex: $source → $target"

body='{
  "source": {
    "index": "'"${source}"'",
    "size": '"${batch_size}"',
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
        "metadata.tika_metadata_xmpmm_*",
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

# This outputs JSON with task id for the caller to use
curl -sXPOST "$ELASTICSEARCH_URL/_reindex?wait_for_completion=false&slices=auto" -H 'Content-Type: application/json' -d "$body"
