#!/bin/bash -e

# Bash reads a script incrementally as it runs, so editing this file mid-run shifts the
# byte offsets and the running process reads garbage. Copying the script to a temporary
# file and re-executing from there saves a long reindex from edits.
# Pass -e again: `bash <file>` ignores the shebang, and without errexit a failed step
# would not stop the run before it offers to delete the backup.
if [[ -z "${SAFE_REINDEX_SELF_COPY:-}" ]]; then
    self_copy=$(mktemp "${TMPDIR:-/tmp}/safe_reindex.XXXXXX.sh")
    trap 'rm -f "$self_copy"' EXIT
    cp "$0" "$self_copy"
    SAFE_REINDEX_SELF_COPY="$0" bash -e "$self_copy" "$@"
    exit $?
fi

script_dir=$( cd "$( dirname "${SAFE_REINDEX_SELF_COPY:-${BASH_SOURCE[0]}}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Optional --shards|-s flag to reindex into an index with a different shard count
shards=
batch_size=
while [[ "$1" == "--shards" || "$1" == "-s" || "$1" == "--batch-size" || "$1" == "-b" ]]; do
  case "$1" in
    --shards|-s)     shards=$2 ;;
    --batch-size|-b) batch_size=$2 ;;
  esac
  shift 2
done

check_usage 1 '[--shards|-s <n>] <index> [<version>]'
check_env
check_bins
check_elasticsearch_url

# Configuration
index_name=$1
version=${2:-}
temp_suffix="_reindex_temp"
new_index="${index_name}${temp_suffix}"

# Global variables for results
BACKUP_INDEX=""
DOC_COUNT=0
ORIGINAL_REPLICAS=1
BEFORE_STATE=""
BEFORE_SHARDS=""
BEFORE_SIZE=""
AFTER_SHARDS=""
AFTER_SIZE=""

index_primary_bytes() {
    curl -s "$ELASTICSEARCH_URL/$1/_stats/store" \
        | jq -r '._all.primaries.store.size_in_bytes // 0'
}

human_bytes() {
    awk -v b="${1:-0}" 'BEGIN {
        split("B KB MB GB TB", u, " ")
        i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i]
    }'
}

# Before touching anything save an snapshot of the index, so compare_after_state can diff
# against it at the end and show the reindex didn't lose documents. verify.sh writes the
# file so both sides use the same format.
capture_before_state() {
    local index=$1
    BEFORE_STATE=$(mktemp "${TMPDIR:-/tmp}/safe_reindex_before.XXXXXX")
    spinner_start "Capture state before"
    if ! "$script_dir/verify.sh" --save "$BEFORE_STATE" "$index" > /dev/null; then
        spinner_error "Capture state before"
        echo ""
        log_error "Could not capture the state of '$index'"
        exit 1
    fi
    BEFORE_SHARDS=$(curl -s "$ELASTICSEARCH_URL/$index/_settings?flat_settings=true" \
                    | jq -r '.[].settings["index.number_of_shards"] // "?"')
    BEFORE_SIZE=$(index_primary_bytes "$index")
    spinner_stop "Capture state before"
}

# The mapping is expected to differ: create.sh rebuilds the index from datashare's own
# settings/mappings, which is the point. What must NOT differ is the document count, the
# aliases, the replica count, and every sampled document still resolving. verify.sh exits
# non-zero when the document count changed or a sampled document has gone missing, and
# only warns on the other lines.
compare_after_state() {
    local index=$1

    spinner_start "Wait for primaries"
    curl -s "$ELASTICSEARCH_URL/_cluster/health/$index?wait_for_status=yellow&timeout=300s" > /dev/null
    spinner_stop "Wait for primaries"
    AFTER_SHARDS=$(curl -s "$ELASTICSEARCH_URL/$index/_settings?flat_settings=true" \
                   | jq -r '.[].settings["index.number_of_shards"] // "?"')
    AFTER_SIZE=$(index_primary_bytes "$index")
    log_section "Verification"
    "$script_dir/verify.sh" --compare "$BEFORE_STATE" "$index"
    log_section "Before and after"
    log_kv "Primary shards" "$BEFORE_SHARDS -> $AFTER_SHARDS"
    log_kv "Primary size" "$(human_bytes "${BEFORE_SIZE:-0}") -> $(human_bytes "${AFTER_SIZE:-0}")"
    log_kv "Documents" "$DOC_COUNT (unchanged)"
    log_kv "Replicas" "$ORIGINAL_REPLICAS (restored)"
    log_kv "Backup retained" "$BACKUP_INDEX"
}

check_index_exists() {
    local index=$1
    spinner_start "Check index exists"
    if ! curl -s -f "$ELASTICSEARCH_URL/$index" > /dev/null; then
        spinner_error "Check index exists"
        echo ""
        log_error "Index '$index' does not exist"
        exit 1
    fi
    spinner_stop "Check index exists"
}

create_new_index() {
    local target_index=$1

    # Build create.sh arguments: optional shard override, index name, optional version
    local create_args=()
    if [[ -n "$shards" ]]; then
        create_args+=(--shards "$shards")
    fi
    create_args+=("$target_index")
    if [[ -n "$version" ]]; then
        create_args+=("$version")
    fi

    # Keep create.sh output visible: it logs why it failed (stale mappings, download
    # error) on stdout, and it draws its own spinners.
    if ! "$script_dir/create.sh" "${create_args[@]}"; then
        echo ""
        log_error "Failed to create new index '$target_index'"
        exit 1
    fi
}

# monitor_es_task says the task failed but not why, you just get a red cross. Print the
# first bulk failures so you know what went wrong.
report_reindex_failures() {
    local task_id=$1 failures
    failures=$(curl -s "$ELASTICSEARCH_URL/_tasks/$task_id" \
               | jq -r '(.response.failures // [])[0:3][] | "  \(.cause.type // "?"): \(.cause.reason // "?")  [doc \(.id // "?")]"')
    if [[ -n "$failures" ]]; then
        log_warn "First failures reported by the task:"
        echo "$failures"
        log_kv "  Full detail" "GET /_tasks/$task_id"
    fi
}

# Delete the half written destination index, if it is still there the next run will not
# be able to create it. Nothing is lost, the source index is still intact at this point.
drop_partial_destination() {
    local dest_index=$1 docs
    docs=$(curl -s "$ELASTICSEARCH_URL/$dest_index/_count" | jq -r '.count // 0')
    spinner_start "Remove partial destination"
    if curl -s -XDELETE "$ELASTICSEARCH_URL/$dest_index" | jq -e '.acknowledged' > /dev/null; then
        spinner_stop "Remove partial destination"
        log_kv "  Dropped" "$dest_index ($docs partial documents)"
    else
        spinner_error "Remove partial destination"
        log_warn "Could not delete '$dest_index' - remove it by hand before retrying"
    fi
}

# A fresh index only declares the fields datashare publishes (currently 36 of them), but
# the documents have thousands of metadata fields mapped dynamically. Every unseen field
# forces a dynamic mapping update (that is a cluster state update through the master),
# and with a steady stream of them a document finally exceeds
# index.mapping.dynamic_timeout (30s by default) and the whole reindex falls apart on
# that one bulk failure.
#
# Copying the source's own dynamic fields up front turns thousands of cluster state
# updates into one, so the copy runs with nothing left to map.
seed_dynamic_mapping() {
    local source_index=$1
    local dest_index=$2

    spinner_start "Seed dynamic fields"

    # There is no per-index timeout to raise, just the cluster wide
    # indices.mapping.dynamic_timeout, too big a hammer for one index. If a copy is still
    # timing out after seeding just raise it by hand and put it back.

    # Take the source properties block, drop what the destination already declares, and
    # PUT the rest. It all goes through files, these mappings are thousands of fields and
    # passing them as arguments blows ARG_MAX, shell variables, jq --argjson and curl -d
    # all fail with "Argument list too long".
    local src_file dst_file seed_file count
    src_file=$(mktemp "${TMPDIR:-/tmp}/seed_src.XXXXXX.json")
    dst_file=$(mktemp "${TMPDIR:-/tmp}/seed_dst.XXXXXX.json")
    seed_file=$(mktemp "${TMPDIR:-/tmp}/seed_body.XXXXXX.json")
    # shellcheck disable=SC2064
    trap "rm -f '$src_file' '$dst_file' '$seed_file'" RETURN

    curl -s "$ELASTICSEARCH_URL/$source_index/_mapping" | jq '.[].mappings.properties // {}' > "$src_file"
    curl -s "$ELASTICSEARCH_URL/$dest_index/_mapping"   | jq '.[].mappings.properties // {}' > "$dst_file"
    jq -n --slurpfile src "$src_file" --slurpfile dst "$dst_file" \
       '{properties: ($src[0] * $dst[0])}' > "$seed_file"
    count=$(jq '[.properties | .. | objects | select(has("type") or has("properties") or has("enabled"))] | length' "$seed_file")

    if [[ "$(jq -S . "$seed_file")" == "$(jq -S '{properties: .}' "$dst_file")" ]]; then
        spinner_stop "Seed dynamic fields"
        log_kv "  Fields to seed" "none, destination already declares them all"
        return 0
    fi

    if ! curl -s -XPUT "$ELASTICSEARCH_URL/$dest_index/_mapping" \
         -H 'Content-Type: application/json' \
         -d "@$seed_file" | jq -e '.acknowledged' > /dev/null; then
        spinner_error "Seed dynamic fields"
        echo ""
        log_error "Could not seed the source mapping onto '$dest_index'"
        log_warn "Retry is safe: '$source_index' has not been touched yet"
        drop_partial_destination "$dest_index"
        exit 1
    fi

    spinner_stop "Seed dynamic fields"
    log_kv "  Fields declared up front" "$count"
    log_kv "  Top level" "$(jq '.properties | length' "$seed_file")"
    log_kv "  Under metadata" "$(jq '.properties.metadata.properties // {} | length' "$seed_file")"
}

# A bulk request bigger than the cluster indexing pressure limit
# (indexing_pressure.memory.limit, 10% of heap by default) gets rejected and takes the
# whole reindex with it. One batch size doesn't work on an uneven index, half the
# documents are tiny and the top percentile runs to hundreds of megabytes. Size the batch
# for the big ones and the small ones crawl, size it for the small ones and one unlucky
# batch kills the run.
#
# So copy in bands. Each band takes a slice of the size distribution and gets the batch
# size that fits the budget at that band ceiling. The bands don't overlap and cover
# everything, so every document is copied once and the count check still proves it.
#
# Band on contentTextLength, the text datashare stored, not on contentLength, the size of
# the original file. The two diverge a lot, a huge file that Tika couldn't open has no
# text at all, and banding on the file size would send it off by itself and put tiny
# documents in huge batches. A document costs its text plus a fixed overhead for
# metadata, translations and NER offsets, so the model is a floor plus a multiplier. The
# numbers are from measuring real documents, not from guessing.
SOURCE_FLOOR=4096
SOURCE_OVERHEAD_PCT=120

# Bands, smallest first: "<query_string>|<text ceiling in bytes>|<label>".
# datashare caps stored text at 20MB, so the top band has a real ceiling and never needs
# to fall back to one document at a time.
BANDS=(
    "(NOT _exists_:contentTextLength) OR contentTextLength:[* TO 102399]|102400|under 100KB of text"
    "contentTextLength:[102400 TO 1048575]|1048576|100KB to 1MB"
    "contentTextLength:[1048576 TO 10485759]|10485760|1MB to 10MB"
    "contentTextLength:[10485760 TO *]|20971520|over 10MB"
)

compute_budget() {
    local index=$1 limit
    # indexing_pressure stats only show counters, not the limit, so do it like
    # Elasticsearch does, 10% of the heap. Checked against a real rejection, it matches
    # the max_coordinating_and_primary_bytes the error quoted.
    limit=$(curl -s "$ELASTICSEARCH_URL/_nodes/stats/jvm" \
            | jq -r '[.nodes[].jvm.mem.heap_max_in_bytes // empty] | min // empty')
    if [[ -n "$limit" && "$limit" != "null" && "$limit" -gt 0 ]]; then
        limit=$(( limit / 10 ))
    else
        log_warn "Could not read the heap size; assuming a 1GB indexing pressure limit"
        limit=$(( 1024 * 1024 * 1024 ))
    fi
    PRESSURE_LIMIT=$limit
    # reindex.sh runs with slices=auto, one slice per source primary, and every slice has
    # a batch in flight at the same time. So split the budget between them.
    SOURCE_SHARDS=$(curl -s "$ELASTICSEARCH_URL/$index/_settings?flat_settings=true" \
                    | jq -r '.[].settings["index.number_of_shards"] // empty')
    [[ "$SOURCE_SHARDS" =~ ^[1-9][0-9]*$ ]] || SOURCE_SHARDS=1
    # A quarter of the limit, so the batches in flight cannot monopolise it and there is
    # room for the estimate to be wrong.
    BATCH_BUDGET=$(( limit / 4 / SOURCE_SHARDS ))
}

# Documents bigger than the whole limit can never be copied, whatever the batch size,
# because a batch of one still carries that document. The run would abort hours in, so
# stop here instead and let the operator deal with them first.
check_oversized_documents() {
    local index=$1 oversized
    oversized=$(curl -s "$ELASTICSEARCH_URL/$index/_count" -H 'Content-Type: application/json' \
        -d "{\"query\":{\"range\":{\"contentTextLength\":{\"gt\":$(( PRESSURE_LIMIT * 100 / SOURCE_OVERHEAD_PCT ))}}}}" \
        | jq -r '.count // 0')
    if [[ "$oversized" =~ ^[0-9]+$ ]] && [[ "$oversized" -gt 0 ]]; then
        log_error "$oversized document(s) in '$index' are larger than the indexing pressure"
        log_error "limit ($(human_bytes "$PRESSURE_LIMIT")). No batch size can carry them and the copy"
        log_error "would abort on them. Raise indexing_pressure.memory.limit or exclude them first."
        exit 1
    fi
}

reindex_data() {
    local source_index=$1
    local dest_index=$2
    local band query ceiling label size copied total_expected
    local -a bands=("${BANDS[@]}")

    # --batch-size turns the banding off: one pass over everything at the given size.
    if [[ -n "$batch_size" ]]; then
        bands=("*|fixed|every document")
        log_warn "Banding disabled: copying everything at $batch_size documents per batch"
    fi

    total_expected=$(curl -s "$ELASTICSEARCH_URL/$source_index/_count" | jq -r '.count // 0')
    log_kv "Reindex" "$total_expected documents in ${#bands[@]} size band(s)"

    local i=0
    for band in "${bands[@]}"; do
        i=$(( i + 1 ))
        IFS='|' read -r query ceiling label <<< "$band"

        # The batch size that keeps a full batch of this band's largest documents inside
        # the budget. The open-ended top band goes one document at a time.
        if [[ "$ceiling" == "fixed" ]]; then
            size=$batch_size
        elif [[ "$ceiling" == "*" ]]; then
            size=1
        else
            size=$(( BATCH_BUDGET / (SOURCE_FLOOR + ceiling * SOURCE_OVERHEAD_PCT / 100) ))
            (( size < 1 )) && size=1
            (( size > 10000 )) && size=10000
        fi

        copied=$(curl -s "$ELASTICSEARCH_URL/$source_index/_count" -H 'Content-Type: application/json' \
                 -d "{\"query\":{\"query_string\":{\"query\":\"$query\"}}}" | jq -r '.count // 0')
        if [[ "$copied" == "0" ]]; then
            log_kv "  Band $i/${#bands[@]} ($label)" "no documents, skipped"
            continue
        fi
        log_kv "  Band $i/${#bands[@]} ($label)" "$copied documents, $size per batch"

        local result task_id
        result=$("$script_dir/reindex.sh" --batch-size "$size" "$source_index" "$dest_index" "$query")
        task_id=$(echo "$result" | jq -r '.task')
        if [[ "$task_id" == "null" || -z "$task_id" ]]; then
            log_error "Failed to start the reindex task for band $i ($label)"
            drop_partial_destination "$dest_index"
            exit 1
        fi

        if ! monitor_es_task "$task_id" "  Copying $label"; then
            echo ""
            log_error "Band $i ($label) failed - '$source_index' is untouched"
            report_reindex_failures "$task_id"
            drop_partial_destination "$dest_index"
            exit 1
        fi

        local failures
        failures=$(curl -s "$ELASTICSEARCH_URL/_tasks/$task_id" | jq '.response.failures | length')
        if [[ "$failures" != "0" && "$failures" != "null" ]]; then
            log_error "Band $i ($label) reported $failures failures - '$source_index' is untouched"
            report_reindex_failures "$task_id"
            drop_partial_destination "$dest_index"
            exit 1
        fi
    done
}

block_source_writes() {
    local index=$1
    spinner_start "Block writes on source"
    if ! "$script_dir/readonly.sh" "$index" true > /dev/null; then
        spinner_error "Block writes on source"
        echo ""
        log_error "Failed to block writes on '$index'"
        exit 1
    fi
    SOURCE_BLOCKED=true
    spinner_stop "Block writes on source"
}

# If the script dies between the block writes and the swap, the index stays read only and
# nobody can write to it, so unblock it on the way out. After the swap there is nothing
# to do, the clone comes without the block.
restore_source_writes_on_failure() {
    local code=$?
    if [[ $code -ne 0 && "$SOURCE_BLOCKED" == true ]]; then
        echo ""
        log_warn "Aborted with '$index_name' still write-blocked - restoring writes"
        "$script_dir/readonly.sh" "$index_name" false > /dev/null 2>&1 || \
            log_warn "Could not restore writes on '$index_name'; do it by hand"
    fi
}
trap restore_source_writes_on_failure EXIT

capture_original_replicas() {
    local index=$1
    local replicas
    replicas=$(curl -s "$ELASTICSEARCH_URL/$index/_settings" | jq -r ".\"$index\".settings.index.number_of_replicas // empty")
    if [[ -n "$replicas" ]]; then
        ORIGINAL_REPLICAS=$replicas
    fi
}

set_replicas() {
    local index=$1
    local replicas=$2
    "$script_dir/number_of_replicas.sh" "$index" "$replicas" > /dev/null
}

verify_document_count() {
    local source_index=$1
    local dest_index=$2
    spinner_start "Verify document count"

    # Refresh indices using refresh.sh
    "$script_dir/refresh.sh" "$source_index" > /dev/null
    "$script_dir/refresh.sh" "$dest_index" > /dev/null

    local source_count=$(curl -s "$ELASTICSEARCH_URL/$source_index/_count" | jq '.count')
    local dest_count=$(curl -s "$ELASTICSEARCH_URL/$dest_index/_count" | jq '.count')

    if [[ "$source_count" != "$dest_count" ]]; then
        spinner_error "Verify document count"
        echo ""
        log_error "Document count mismatch! Source: $source_count, Dest: $dest_count"
        exit 1
    fi

    DOC_COUNT=$source_count
    spinner_stop "Verify document count"
    # Print both numbers, not just a tick. A tick that says it matched is not proof, the
    # numbers are.
    log_kv "  $source_index" "$source_count documents"
    log_kv "  $dest_index" "$dest_count documents"
}

swap_indices() {
    local old_index=$1
    local temp_index=$2
    local backup_suffix="_backup_$(date +%Y%m%d_%H%M%S)"
    BACKUP_INDEX="${old_index}${backup_suffix}"

    # Create backup using clone.sh
    spinner_start "Create backup"
    if ! "$script_dir/clone.sh" "$old_index" "$BACKUP_INDEX" > /dev/null; then
        spinner_error "Create backup"
        echo ""
        log_error "Failed to create backup!"
        exit 1
    fi
    spinner_stop "Create backup"

    # Check for aliases
    local aliases=$(curl -s "$ELASTICSEARCH_URL/$old_index/_alias" | jq -r ".\"$old_index\".aliases | keys | .[]" 2>/dev/null || echo "")

    # Delete old index
    spinner_start "Delete old index"
    if ! curl -s -X DELETE "$ELASTICSEARCH_URL/$old_index" | jq -e '.acknowledged' > /dev/null; then
        spinner_error "Delete old index"
        echo ""
        log_error "Failed to delete old index"
        log_warn "Your data is safe in backup: $BACKUP_INDEX"
        exit 1
    fi
    spinner_stop "Delete old index"

    # Rename temp index to original name using clone.sh
    spinner_start "Rename temporary index"
    if ! "$script_dir/clone.sh" "$temp_index" "$old_index" > /dev/null; then
        spinner_error "Rename temporary index"
        echo ""
        log_error "Failed to rename temp index!"
        log_warn "Restoring from backup: $BACKUP_INDEX"

        # Clone backup back to original
        "$script_dir/clone.sh" "$BACKUP_INDEX" "$old_index" > /dev/null
        log_info "Restored from backup: $BACKUP_INDEX"
        exit 1
    fi
    spinner_stop "Rename temporary index"

    # Clean up temp index
    spinner_start "Clean temporary index"
    curl -s -X DELETE "$ELASTICSEARCH_URL/$temp_index" > /dev/null
    spinner_stop "Clean temporary index"

    # Restore aliases using the reusable alias command. This runs after the
    # reindex and swap have already succeeded, so a failed restore is best-effort:
    # warn and keep going rather than aborting (alias.sh exits non-zero on failure,
    # and an unguarded call under 'set -e' would kill the run mid-restore).
    if [[ -n "$aliases" ]]; then
        spinner_start "Restore aliases"
        local alias_failures=0
        for alias in $aliases; do
            if ! "$script_dir/alias.sh" "$old_index" "$alias" > /dev/null; then
                alias_failures=$((alias_failures + 1))
            fi
        done
        if [[ "$alias_failures" -gt 0 ]]; then
            spinner_error "Restore aliases"
            log_warn "Could not restore $alias_failures alias(es) on '$old_index'"
        else
            spinner_stop "Restore aliases"
        fi
    fi
}

# Main execution
main() {
    log_title "Safe Reindex: $index_name"

    # Confirmation
    if ! prompt_confirm "Do you want to proceed with the safe reindex?"; then
        log_warn "Reindex cancelled"
        exit 0
    fi

    # Execute steps
    check_index_exists "$index_name"

    compute_budget "$index_name"
    log_kv "Indexing pressure limit" "$(human_bytes "$PRESSURE_LIMIT")"
    log_kv "Budget per bulk request" "$(human_bytes "$BATCH_BUDGET") ($SOURCE_SHARDS slice(s) in parallel)"
    check_oversized_documents "$index_name"

    capture_before_state "$index_name"
    capture_original_replicas "$index_name"
    create_new_index "$new_index"
    # Drop replicas to 0 on the temporary index to speed up the reindex and save disk;
    # the final index inherits this from the clone, so we restore the count at the end
    set_replicas "$new_index" 0
    seed_dynamic_mapping "$index_name" "$new_index"
    block_source_writes "$index_name"
    reindex_data "$index_name" "$new_index"
    verify_document_count "$index_name" "$new_index"
    swap_indices "$index_name" "$new_index"
    # The clone in swap_indices leaves the new index writable, so there is no block left
    # to undo from here on.
    SOURCE_BLOCKED=false
    set_replicas "$index_name" "$ORIGINAL_REPLICAS"

    # Final verification against the capture taken before anything was touched
    "$script_dir/refresh.sh" "$index_name" > /dev/null
    echo ""
    compare_after_state "$index_name"
    rm -f "$BEFORE_STATE"

    # Offer to delete backup
    echo ""
    if prompt_confirm "Do you want to delete the backup index '$BACKUP_INDEX'?"; then
        "$script_dir/delete.sh" --force "$BACKUP_INDEX"
    else
        log_info "Backup retained at: $BACKUP_INDEX"
        log_kv "  └─ To delete it later, run" "elasticsearch/index/delete.sh $BACKUP_INDEX"
    fi
}

# Run main function
main
