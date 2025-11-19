#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 2 '<source> <target>'
check_env
check_bins
check_elasticsearch_url

source=$1
target=$2
esindex=$ELASTICSEARCH_URL/$source

log_title "Clone Index: $source → $target"

spinner_start "Block writes on source index"
if ! curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d'{ "settings": { "index.blocks.write": true } }' | jq -e '.acknowledged' > /dev/null; then
    spinner_error "Block writes on source index"
    exit 1
fi
spinner_stop "Block writes on source index"

spinner_start "Clone index"
if ! curl -sXPOST "$esindex/_clone/$target" -H 'Content-Type: application/json' -d'{ "settings": { "index.mapping.ignore_malformed": true, "index.blocks.write": false } }' | jq -e '.acknowledged' > /dev/null; then
    spinner_error "Clone index"
    # Restore writes on source
    curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d'{ "settings": { "index.blocks.write": false } }' > /dev/null
    exit 1
fi
spinner_stop "Clone index"

spinner_start "Restore writes on source index"
if ! curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d'{ "settings": { "index.blocks.write": false } }' | jq -e '.acknowledged' > /dev/null; then
    spinner_error "Restore writes on source index"
    exit 1
fi
spinner_stop "Index '$source' cloned to '$target'"
