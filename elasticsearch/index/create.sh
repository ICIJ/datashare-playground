#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Optional --shards|-s flag to override the default number of shards
shards=
while [[ "$1" == "--shards" || "$1" == "-s" ]]; do
  shards=$2
  shift 2
done

check_usage 1 '[--shards|-s <n>] <index> [<version>]'
check_env
check_bins
check_elasticsearch_url

resources_dir="$script_dir"/resources

log_title "Create Index: $1"

# A stale mappings file will create an index with missing or wrongly typed fields
# that will only show up later, so check the copy you are using against the latest
# datashare release before creating anything. Github being unreachable is not
# fatal, but a copy that is known to be stale is rejected unless the caller allows it.
check_mappings_version() {
  local using=$1 index_name=$2 latest
  latest=$(curl -s --max-time 10 https://api.github.com/repos/ICIJ/datashare/releases/latest \
           | jq -r '.tag_name // empty' 2>/dev/null)

  if [[ -z "$latest" ]]; then
    log_warn "Could not reach GitHub to check the datashare release; using $using"
    return 0
  fi

  if [[ "$using" != "vendored" ]]; then
    if [[ "$using" == "$latest" ]]; then
      log_kv "Mappings" "datashare $using (latest)"
    else
      log_warn "Using datashare $using mappings; the latest release is $latest"
    fi
    return 0
  fi

  # No version given, so run is about to use the copy checked into this repo.
  # That is the dangerous default, nobody sees it and it gets old.
  local remote
  remote=$(mktemp "${TMPDIR:-/tmp}/ds_mappings.XXXXXX.json")
  curl -sL --max-time 20 -o "$remote" \
    "https://github.com/ICIJ/datashare/releases/download/$latest/datashare_index_mappings.json"

  if ! jq -e . "$remote" > /dev/null 2>&1; then
    rm -f "$remote"
    log_warn "Could not fetch the $latest mappings; using the vendored copy unchecked"
    return 0
  fi

  if [[ "$(jq -S . "$mappings_json" | md5sum)" == "$(jq -S . "$remote" | md5sum)" ]]; then
    log_kv "Mappings" "vendored copy, same as datashare $latest"
    rm -f "$remote"
    return 0
  fi

  local vendored_fields latest_fields
  vendored_fields=$(jq -r '.properties | keys | length' "$mappings_json")
  latest_fields=$(jq -r '.properties | keys | length' "$remote")
  rm -f "$remote"

  log_error "The vendored mappings differ from datashare $latest ($vendored_fields fields vs $latest_fields)"
  log_warn "Fields missing from the vendored copy are created by dynamic mapping instead,"
  log_warn "which can change their type (a keyword field comes back as text)."
  log_warn "Pass the deployed version instead:  $0 $index_name <version>"
  log_warn "Or set ALLOW_STALE_MAPPINGS=1 to use the vendored copy anyway."
  [[ "${ALLOW_STALE_MAPPINGS:-}" == "1" ]] || exit 1
}

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

check_mappings_version "${desired_version:-vendored}" "$1"
# Combine contents of mappings and settings JSON files into one body
body=$(jq --slurpfile mappings $mappings_json '{ "mappings": $mappings[0], "settings": . }' $settings_json)

# Override the number of shards if requested
if [[ -n "$shards" ]]; then
  body=$(echo "$body" | jq --argjson n "$shards" '.settings["index.number_of_shards"] = $n')
fi

spinner_start "Create index"
if ! curl -sXPUT "$ELASTICSEARCH_URL/$1" -H 'Content-Type: application/json' -d "$body" | jq -e '.acknowledged' > /dev/null; then
    spinner_error "Create index"
    rm -rf "$script_dir"/resources_tmp
    exit 1
fi
spinner_stop "Index '$1' created"

rm -rf "$script_dir"/resources_tmp
