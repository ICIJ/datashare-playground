#!/bin/bash -e

# Reindex an index FROM a remote Elasticsearch cluster INTO a destination cluster
# using the Reindex API with a remote source. It does NOT delete the source index.
#
# PREREQUISITE: the destination cluster must whitelist the remote host in
# elasticsearch.yml, e.g.:
#   reindex.remote.whitelist: "remote-host:9200"
#
# Auth can be embedded in the remote URL (https://user:pass@host:9200), with any
# special character URL-encoded (e.g. @ -> %40).

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Flags
remote_url=
destination_url=
shards=
while [[ "$1" == --* || "$1" == -s ]]; do
  case "$1" in
    --remote-es-url) remote_url=${2%/}; shift 2 ;;
    --destination-es-url) destination_url=${2%/}; shift 2 ;;
    --shards|-s) shards=$2; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

check_usage 1 '--remote-es-url <url> [--destination-es-url <url>] [--shards|-s <n>] <source_index> [<dest_index>]'
check_env
check_bins

# The destination defaults to ELASTICSEARCH_URL when not given explicitly
if [[ -z "$destination_url" ]]; then
  check_elasticsearch_url
  destination_url=${ELASTICSEARCH_URL%/}
fi

if [[ -z "$remote_url" ]]; then
  log_error "--remote-es-url is required"
  exit 1
fi

source_index=$1
dest_index=${2:-$1}

log_title "Remote Reindex: $source_index → $dest_index"

# Parse scheme, host and (optional) credentials out of the remote URL
remote_scheme=$(echo "$remote_url" | sed -E 's|(https?)://.*|\1|')
if echo "$remote_url" | grep -q '@'; then
  remote_auth=$(echo "$remote_url" | sed -E 's|https?://([^@]+)@.*|\1|')
  remote_user=$(echo "$remote_auth" | cut -d: -f1)
  remote_pass=$(echo "$remote_auth" | cut -d: -f2-)
  remote_host=$(echo "$remote_url" | sed -E 's|https?://[^@]+@([^/]+).*|\1|')
else
  remote_host=$(echo "$remote_url" | sed -E 's|https?://([^/]+).*|\1|')
  remote_user=""
  remote_pass=""
fi

log_kv "Remote source" "$remote_scheme://$remote_host/$source_index"
log_kv "Destination" "$destination_url/$dest_index"

# 1. Fetch settings, mappings and aliases from the remote source index
spinner_start "Fetch settings/mappings from remote"
index_config=$(curl -s "$remote_url/$source_index")
settings=$(echo "$index_config" | jq --raw-output '.[].settings.index | del(.uuid, .version, .provided_name, .creation_date, .number_of_replicas)')
mappings=$(echo "$index_config" | jq '.[].mappings')
aliases=$(echo "$index_config" | jq '.[].aliases')
if [[ -z "$settings" || "$settings" == "null" ]]; then
  spinner_error "Fetch settings/mappings from remote"
  echo ""
  log_error "Could not read '$source_index' from remote cluster"
  exit 1
fi
spinner_stop "Fetch settings/mappings from remote"

# 2. Build the destination index body: 0 replicas for a fast/cheap copy,
#    optional shard override, and drop settings that can't be set on create
body=$(jq -n --argjson settings "$settings" --argjson mappings "$mappings" --argjson aliases "$aliases" \
  '{ settings: $settings, mappings: $mappings, aliases: $aliases }')
body=$(echo "$body" | jq '.settings.number_of_replicas = 0
  | del(.settings.resize)
  | del(.settings.routing.allocation.initial_recovery)')
if [[ -n "$shards" ]]; then
  body=$(echo "$body" | jq --argjson n "$shards" '.settings.number_of_shards = $n')
fi

# 3. Create the destination index
spinner_start "Create destination index"
if ! curl -sXPUT "$destination_url/$dest_index" -H 'Content-Type: application/json' -d "$body" | jq -e '.acknowledged' > /dev/null; then
  spinner_error "Create destination index"
  echo ""
  log_error "Failed to create destination index '$dest_index'"
  exit 1
fi
spinner_stop "Create destination index"

# 4. Start the remote reindex asynchronously
if [[ -n "$remote_user" ]]; then
  remote_user_decoded=$(printf '%b' "${remote_user//%/\\x}")
  remote_pass_decoded=$(printf '%b' "${remote_pass//%/\\x}")
  remote_config=$(jq -n --arg host "$remote_scheme://$remote_host" --arg u "$remote_user_decoded" --arg p "$remote_pass_decoded" \
    '{ host: $host, username: $u, password: $p }')
else
  remote_config=$(jq -n --arg host "$remote_scheme://$remote_host" '{ host: $host }')
fi
reindex_body=$(jq -n --argjson remote "$remote_config" --arg src "$source_index" --arg dst "$dest_index" \
  '{ source: { remote: $remote, index: $src }, dest: { index: $dst } }')

spinner_start "Start remote reindex"
task_id=$(curl -sXPOST "$destination_url/_reindex?wait_for_completion=false" -H 'Content-Type: application/json' -d "$reindex_body" | jq -r '.task')
if [[ "$task_id" == "null" || -z "$task_id" ]]; then
  spinner_error "Start remote reindex"
  echo ""
  log_error "Failed to start remote reindex task"
  exit 1
fi
spinner_stop "Start remote reindex"

# 5. Monitor the task on the destination cluster until it completes
spinner_start "Reindex data"
while true; do
  task_status=$(curl -s "$destination_url/_tasks/$task_id")
  completed=$(echo "$task_status" | jq -r '.completed')
  if [[ "$completed" == "true" ]]; then
    break
  fi
  sleep 2
done
failures=$(curl -s "$destination_url/_tasks/$task_id" | jq '.response.failures | length')
if [[ "$failures" != "0" && "$failures" != "null" ]]; then
  spinner_error "Reindex data"
  echo ""
  log_error "Remote reindex completed with $failures failures"
  exit 1
fi
spinner_stop "Reindex data"

# 6. Verify document counts match
spinner_start "Verify document count"
curl -s -XPOST "$destination_url/$dest_index/_refresh" > /dev/null
source_count=$(curl -s "$remote_url/$source_index/_count" | jq '.count')
dest_count=$(curl -s "$destination_url/$dest_index/_count" | jq '.count')
if [[ "$source_count" != "$dest_count" ]]; then
  spinner_error "Verify document count"
  echo ""
  log_error "Document count mismatch! Source: $source_count, Dest: $dest_count"
  exit 1
fi
spinner_stop "Verify document count"

# 7. Restore replicas on the destination index (curl directly, as the destination
#    cluster may differ from ELASTICSEARCH_URL used by number_of_replicas.sh)
spinner_start "Restore replicas"
if ! curl -sXPUT "$destination_url/$dest_index/_settings" -H 'Content-Type: application/json' -d'{ "index": { "number_of_replicas": 1 } }' | jq -e '.acknowledged' > /dev/null; then
  spinner_error "Restore replicas"
  exit 1
fi
spinner_stop "Restore replicas"

echo ""
log_kv "Destination index contains" "$dest_count documents"
log_info "Remote reindex completed (source left untouched)"
