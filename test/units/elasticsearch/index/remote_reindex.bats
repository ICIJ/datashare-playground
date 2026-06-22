setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_SRC="bats.index.remote_reindex.src"
  TEST_DST="bats.index.remote_reindex.dst"

  H_CONTENT_TYPE="Content-Type: application/json"

  # Cleanup any leftover test indices
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_SRC" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_DST" > /dev/null 2>&1 || true

  # Create the source index with Datashare mappings and a few documents
  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_SRC" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null

  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_SRC/_doc/1" -d'{ "name": "doc1", "path": "/test", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_SRC/_doc/2" -d'{ "name": "doc2", "path": "/test", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_SRC/_refresh" > /dev/null
}


teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_SRC" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_DST" > /dev/null 2>&1 || true
}


@test "cannot run remote_reindex without a source index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/remote_reindex.sh --remote-es-url "$ELASTICSEARCH_URL"
}

@test "remote_reindex requires --remote-es-url" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/remote_reindex.sh $TEST_SRC
    assert_output --partial "remote-es-url"
}

@test "remote_reindex copies documents to a new index and leaves the source untouched" {
    src_count=$(curl -s "$ELASTICSEARCH_URL/$TEST_SRC/_count" | jq '.count')

    # Treat the same cluster as the remote source (requires reindex.remote.whitelist)
    run ./elasticsearch/index/remote_reindex.sh --remote-es-url "$ELASTICSEARCH_URL" $TEST_SRC $TEST_DST
    assert_success

    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_DST/_refresh" > /dev/null
    dst_count=$(curl -s "$ELASTICSEARCH_URL/$TEST_DST/_count" | jq '.count')
    assert_equal "$src_count" "$dst_count"

    # Source must still exist with the same documents
    src_count_after=$(curl -s "$ELASTICSEARCH_URL/$TEST_SRC/_count" | jq '.count')
    assert_equal "$src_count" "$src_count_after"

    # Destination replicas restored to 1
    replicas=$(curl -s "$ELASTICSEARCH_URL/$TEST_DST/_settings" | jq -r ".\"$TEST_DST\".settings.index.number_of_replicas")
    assert_equal "$replicas" "1"
}

@test "remote_reindex can change the shard count on the destination" {
    run ./elasticsearch/index/remote_reindex.sh --remote-es-url "$ELASTICSEARCH_URL" --shards 3 $TEST_SRC $TEST_DST
    assert_success

    shards=$(curl -s "$ELASTICSEARCH_URL/$TEST_DST/_settings" | jq -r ".\"$TEST_DST\".settings.index.number_of_shards")
    assert_equal "$shards" "3"
}
