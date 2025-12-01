setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.index.safe_reindex"

  H_CONTENT_TYPE="Content-Type: application/json"

  # Cleanup any existing test index
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/${TEST_INDEX}_reindex_temp" > /dev/null 2>&1 || true

  # Create index directly with curl using Datashare mappings
  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null

  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/1" -d'{ "name": "doc1", "path": "/test", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/2" -d'{ "name": "doc2", "path": "/test", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/3" -d'{ "name": "doc3", "path": "/other", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null

  # Refresh to make documents searchable
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
}


teardown() {
  # Clean up test index and any backups
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/${TEST_INDEX}_reindex_temp" > /dev/null 2>&1 || true
  # Delete any backup indices
  curl -sXDELETE "$ELASTICSEARCH_URL/${TEST_INDEX}_backup_*" > /dev/null 2>&1 || true
}


@test "cannot run safe_reindex without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/safe_reindex.sh
}

@test "safe_reindex fails if index does not exist" {
    bats_require_minimum_version 1.5.0

    run bash -c 'echo "y" | ./elasticsearch/index/safe_reindex.sh nonexistent_index'
    assert_failure
    assert_output --partial "does not exist"
}

@test "safe_reindex can be cancelled" {
    run bash -c "echo 'n' | ./elasticsearch/index/safe_reindex.sh $TEST_INDEX"
    assert_output --partial "cancelled"
}

@test "can run safe_reindex on an existing index" {
    # Get initial document count
    initial_count=$(curl -s "$ELASTICSEARCH_URL/$TEST_INDEX/_count" | jq '.count')

    # Run safe_reindex with auto-confirmation
    run bash -c "echo 'y' | ./elasticsearch/index/safe_reindex.sh $TEST_INDEX"
    assert_success

    # Refresh and verify document count is preserved
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
    final_count=$(curl -s "$ELASTICSEARCH_URL/$TEST_INDEX/_count" | jq '.count')

    assert_equal "$initial_count" "$final_count"
}

@test "safe_reindex creates a backup" {
    # Run safe_reindex
    run bash -c "echo 'y' | ./elasticsearch/index/safe_reindex.sh $TEST_INDEX"
    assert_success

    # Check that a backup index exists
    backup_indices=$(curl -s "$ELASTICSEARCH_URL/_cat/indices/${TEST_INDEX}_backup_*?format=json" | jq 'length')
    assert [ "$backup_indices" -ge 1 ]
}

@test "safe_reindex preserves document content" {
    # Run safe_reindex
    run bash -c "echo 'y' | ./elasticsearch/index/safe_reindex.sh $TEST_INDEX"
    assert_success

    # Refresh index
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    # Verify specific document still exists
    doc=$(curl -s "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/1" | jq -r '.found')
    assert_equal "$doc" "true"
}
