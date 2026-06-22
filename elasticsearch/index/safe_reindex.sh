#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

# Optional --shards|-s flag to reindex into an index with a different shard count
shards=
while [[ "$1" == "--shards" || "$1" == "-s" ]]; do
  shards=$2
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
    spinner_start "Create temporary index"

    # Build create.sh arguments: optional shard override, index name, optional version
    local create_args=()
    if [[ -n "$shards" ]]; then
        create_args+=(--shards "$shards")
    fi
    create_args+=("$target_index")
    if [[ -n "$version" ]]; then
        create_args+=("$version")
    fi

    # Use create.sh to create the index with settings/mappings
    if ! "$script_dir/create.sh" "${create_args[@]}" > /dev/null; then
        spinner_error "Create temporary index"
        echo ""
        log_error "Failed to create new index '$target_index'"
        exit 1
    fi
    spinner_stop "Create temporary index"
}

reindex_data() {
    local source_index=$1
    local dest_index=$2
    spinner_start "Reindex data"

    # Use reindex.sh to start the task and capture the task ID
    local result=$("$script_dir/reindex.sh" "$source_index" "$dest_index")
    local task_id=$(echo "$result" | jq -r '.task')

    if [[ "$task_id" == "null" || -z "$task_id" ]]; then
        spinner_error "Reindex data"
        echo ""
        log_error "Failed to start reindex task"
        exit 1
    fi

    # Monitor progress
    while true; do
        local task_status=$(curl -s "$ELASTICSEARCH_URL/_tasks/$task_id")
        local completed=$(echo "$task_status" | jq -r '.completed')

        if [[ "$completed" == "true" ]]; then
            break
        fi
        sleep 2
    done

    # Check for failures
    local failures=$(curl -s "$ELASTICSEARCH_URL/_tasks/$task_id" | jq '.response.failures | length')
    if [[ "$failures" != "0" && "$failures" != "null" ]]; then
        spinner_error "Reindex data"
        echo ""
        log_error "Reindex completed with $failures failures"
        exit 1
    fi
    spinner_stop "Reindex data"
}

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
    capture_original_replicas "$index_name"
    create_new_index "$new_index"
    # Drop replicas to 0 on the temporary index to speed up the reindex and save disk;
    # the final index inherits this from the clone, so we restore the count at the end
    set_replicas "$new_index" 0
    reindex_data "$index_name" "$new_index"
    verify_document_count "$index_name" "$new_index"
    swap_indices "$index_name" "$new_index"
    set_replicas "$index_name" "$ORIGINAL_REPLICAS"

    # Final count
    "$script_dir/refresh.sh" "$index_name" > /dev/null
    local final_count=$(curl -s "$ELASTICSEARCH_URL/$index_name/_count" | jq '.count')
    echo ""
    log_kv "Final index contains" "$final_count documents"

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
