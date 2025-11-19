#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index> [<version>]'
check_env
check_bins
check_elasticsearch_url

resources_dir="$script_dir"/resources

log_title "Create Index: $1"

if [[ $# -eq 2 ]]; then
  desired_version=$2
  resources_dir="$script_dir"/resources_tmp

  spinner_start "Download settings/mappings for $desired_version"
  if ! wget -q -P "$resources_dir" https://github.com/ICIJ/datashare/releases/download/"${desired_version}"/datashare_index_settings.json \
  https://github.com/ICIJ/datashare/releases/download/"${desired_version}"/datashare_index_mappings.json
  then
    spinner_error "Download settings/mappings for $desired_version"
    rm -rf "$resources_dir"
    exit 1
  fi
  spinner_stop "Download settings/mappings for $desired_version"
fi

mappings_json=$resources_dir/datashare_index_mappings.json
settings_json=$resources_dir/datashare_index_settings.json
# Combine contents of mappings and settings JSON files into one body
body=$(jq --slurpfile mappings $mappings_json '{ "mappings": $mappings[0], "settings": . }' $settings_json)

spinner_start "Create index"
if ! curl -sXPUT "$ELASTICSEARCH_URL/$1" -H 'Content-Type: application/json' -d "$body" | jq -e '.acknowledged' > /dev/null; then
    spinner_error "Create index"
    rm -rf "$script_dir"/resources_tmp
    exit 1
fi
spinner_stop "Index '$1' created"

rm -rf "$script_dir"/resources_tmp
