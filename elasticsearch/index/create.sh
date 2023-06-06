#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_env
check_bins
check_elasticsearch_url

mappings_json=$script_dir/resources/datashare_index_mappings.json
settings_json=$script_dir/resources/datashare_index_settings.json
# Combine contents of mappings and settings JSON files into one body
body=$(jq --slurpfile mappings $mappings_json '{ "mappings": $mappings[0], "settings": . }' $settings_json)

curl -XPUT "$ELASTICSEARCH_URL/$1" -H 'Content-Type: application/json' -d "$body" | jq