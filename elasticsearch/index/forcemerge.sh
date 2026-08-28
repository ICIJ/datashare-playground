#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<index>'
check_bins
check_env
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

log_title "Force merge (expunge deletes): $index"

# Synchronous on purpose: _forcemerge has no wait_for_completion on ES 7.x
# (Datashare's target), so we block until the merge returns its _shards report
# and treat a missing successful count (e.g. a 404 error body) as a failure.
spinner_start "Force merge (expunge deletes)"
if ! curl -sXPOST "$esindex/_forcemerge?only_expunge_deletes=true" | jq -e '._shards.successful' > /dev/null; then
    spinner_error "Force merge (expunge deletes)"
    exit 1
fi
spinner_stop "Index '$index' force merged"
