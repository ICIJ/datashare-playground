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

wait_for_clone() {
    curl -sXGET "$ELASTICSEARCH_URL/_cluster/health/$target?wait_for_status=yellow&timeout=$1s" \
        | jq -r '.status // "unknown"'
}

spinner_start "Wait for clone shards"
clone_status=$(wait_for_clone 120)
if [[ "$clone_status" != "yellow" && "$clone_status" != "green" ]]; then
    # An unassigned clone normally just needs its allocation retried.
    curl -sXPOST "$ELASTICSEARCH_URL/_cluster/reroute?retry_failed=true" > /dev/null
    clone_status=$(wait_for_clone 120)
fi
if [[ "$clone_status" != "yellow" && "$clone_status" != "green" ]]; then
    spinner_error "Wait for clone shards"
    log_error "Clone '$target' was created but its shards did not allocate (status: $clone_status)"
    log_warn "'$source' is left intact and write-blocked on purpose. Delete nothing; inspect with:"
    log_warn "  GET /_cluster/allocation/explain {\"index\":\"$target\",\"shard\":0,\"primary\":true}"
    exit 1
fi
spinner_stop "Wait for clone shards"

spinner_start "Restore writes on source index"
if ! curl -sXPUT "$esindex/_settings" -H 'Content-Type: application/json' -d'{ "settings": { "index.blocks.write": false } }' | jq -e '.acknowledged' > /dev/null; then
    spinner_error "Restore writes on source index"
    exit 1
fi
spinner_stop "Index '$source' cloned to '$target'"
