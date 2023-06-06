#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../lib/cli.sh

check_env
check_bins
check_elasticsearch_url

sort=${1:-'index'}
format=${2:-'txt'}

curl -sXGET "$ELASTICSEARCH_URL/_cat/indices?v&s=$sort&format=$format"