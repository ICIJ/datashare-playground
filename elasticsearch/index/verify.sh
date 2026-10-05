#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Capture the state of an index, or compare it to an earlier capture. Made for reshard
# and reindex work. A doc count alone doesn't prove a copy is good, and the sample
# documents have to be known ids, not whatever _search returns first, that changes with
# the shard count and proves nothing.
usage_extra() {
  echo "  --save <file>     write the capture to <file> as well as stdout"
  echo "  --compare <file>  capture now and diff against an earlier capture"
}

mode=save
state_file=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --save)    mode=save;    state_file=$2; shift 2 ;;
    --compare) mode=compare; state_file=$2; shift 2 ;;
    *) break ;;
  esac
done

check_usage 1 '[--save <file> | --compare <file>] <index>'
check_env
check_bins
check_elasticsearch_url

index=$1
esindex=$ELASTICSEARCH_URL/$index

# Everything that should come out of a reshard intact. The shard count and node placement
# are not here on purpose, those are what a reshard changes.
capture() {
  local settings mapping docs
  settings=$(curl -sXGET "$esindex/_settings?flat_settings=true")
  mapping=$(curl -sXGET "$esindex/_mapping")
  docs=$(curl -sXGET "$esindex/_count" | jq -r '.count // "ERROR"')
  if ! [[ "$docs" =~ ^[0-9]+$ ]]; then
    log_error "Could not count the documents in '$index'" >&2
    exit 1
  fi

  echo "index            $index"
  echo "docs             $docs"
  echo "replicas         $(echo "$settings" | jq -r '.[].settings["index.number_of_replicas"] // "?"')"
  # Normalise this one. The setting is missing on one index and set to false on the
  # other, they mean the same thing but the diff shows them as different.
  echo "write_blocked    $(echo "$settings" | jq -r 'if (.[].settings["index.blocks.write"] // "false") == "true" then "yes" else "no" end')"
  echo "aliases          $(curl -sXGET "$esindex/_alias" | jq -cr '.[].aliases // {}')"

  # We are not comparing the mapping by design, a reshard rebuilds the index from the
  # datashare mapping, so the field list always differs and a diff on it looks like a
  # failure when nothing is wrong. The important thing is that the documents survived,
  # and the samples below prove it. The field count is printed as info on the "# " lines,
  # the compare ignores them.
  echo "# mapping_fields $(echo "$mapping" | jq -r '[.[].mappings.properties | keys[]] | length') (informational, expected to change)"

  # 10 ids sorted on path, so the sample does not depend on the shard layout. Not on _id:
  # sorting on it needs indices.id_field_data.enabled, which is off by default on ES 8.
  # path is a keyword with doc values; unmapped_type keeps a non datashare index working.
  # These are the documents a later --compare looks up one by one.
  local response ids
  response=$(curl -sXGET "$esindex/_search?size=10" -H 'Content-Type: application/json' \
             -d '{"sort":[{"path":{"order":"asc","unmapped_type":"keyword"}}],"_source":false}')
  if echo "$response" | jq -e '.error' > /dev/null; then
    log_error "Could not sample documents: $(echo "$response" | jq -r '.error.reason // .error')" >&2
    exit 1
  fi
  ids=$(echo "$response" | jq -r '.hits.hits[]._id')
  # An empty sample makes --compare pass after checking nothing, so it is an error
  # unless the index really is empty.
  if [[ -z "$ids" && "$docs" != "0" ]]; then
    log_error "Sample search returned no documents but the index has $docs" >&2
    exit 1
  fi
  local id
  for id in $ids; do
    echo "sample_doc       $id"
  done
}

# On compare every sampled id has to still be there. A count that matches with documents
# missing is exactly the failure a count check can't see.
check_samples() {
  local file=$1 missing=0 id found
  while read -r id; do
    # Search by id instead of GET /_doc/<id>. datashare uses a join field and indexes
    # documents with an explicit _routing, so a GET hashes the wrong value and says
    # found:false as soon as the index has more than one shard, a good reshard looks like
    # it lost documents.
    found=$(curl -sXGET "$esindex/_search" -H 'Content-Type: application/json' \
            -d "{\"query\":{\"ids\":{\"values\":[\"$id\"]}},\"_source\":false}" \
            | jq -r 'if (.hits.total.value // 0) > 0 then "true" else "false" end')
    if [[ "$found" != "true" ]]; then
      log_error "sample document missing: $id"
      missing=$((missing + 1))
    fi
  done < <(awk '$1 == "sample_doc" { print $2 }' "$file")
  echo "$missing"
}

log_title "Verify Index: $index"

if [[ "$mode" == "compare" ]]; then
  [[ -f "$state_file" ]] || { log_error "No such capture: $state_file"; exit 1; }

  now=$(mktemp "${TMPDIR:-/tmp}/verify.XXXXXX")
  trap 'rm -f "$now"' EXIT
  capture > "$now"

  # Shard count and placement are supposed to change, compare everything else.
  if diff <(grep -v '^sample_doc\|^# ' "$state_file") <(grep -v '^sample_doc\|^# ' "$now")
  then
    log_info "State matches the capture"
  else
    log_warn "State differs from the capture (above: < before, > now)"
  fi

  # The other lines only warn, but a changed document count means documents were lost
  # or added, and the 10 samples alone would not catch it.
  docs_before=$(awk '$1 == "docs" { print $2 }' "$state_file")
  docs_now=$(awk '$1 == "docs" { print $2 }' "$now")
  docs_changed=false
  if [[ "$docs_before" != "$docs_now" ]]; then
    docs_changed=true
  fi

  spinner_start "Check sampled documents"
  missing=$(check_samples "$state_file")
  if [[ "$missing" == "0" ]]; then
    spinner_stop "Check sampled documents"
    log_kv "Sampled documents" "all present"
  else
    spinner_error "Check sampled documents"
    log_error "$missing sampled document(s) missing"
    exit 1
  fi

  if [[ "$docs_changed" == true ]]; then
    log_error "Document count changed: $docs_before before, $docs_now now"
    exit 1
  fi
else
  if [[ -n "$state_file" ]]; then
    # Not `capture | tee`: in a pipeline a failed capture would not stop the script.
    capture > "$state_file"
    cat "$state_file"
    echo ""
    log_kv "Capture written to" "$state_file"
  else
    capture
  fi
fi
