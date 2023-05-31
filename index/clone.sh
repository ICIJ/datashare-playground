#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../lib/cli.sh

check_usage 2 '<source> <target>'
check_env
check_bins
check_elasticsearch_url

source=$1
target=$2
esindex=$ELASTICSEARCH_URL/$source

curl -sXPUT  "$esindex/_settings" -H 'Content-Type: application/json' -d'{ "settings": { "index.blocks.write": true } }' | jq
curl -sXPOST "$esindex/_clone/$target" -H 'Content-Type: application/json' -d'{ "settings": { "index.mapping.ignore_malformed": true, "index.blocks.write": false } }' | jq
curl -sXPUT  "$esindex/_settings" -H 'Content-Type: application/json' -d'{ "settings": { "index.blocks.write": false } }' | jq