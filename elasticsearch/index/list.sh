#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_env
check_bins
check_elasticsearch_url

target=${1:-'_all'}
sort=${2:-'index'}
format=${3:-'txt'}

curl -sXGET "$ELASTICSEARCH_URL/_cat/indices/$target?v&s=$sort&format=$format"