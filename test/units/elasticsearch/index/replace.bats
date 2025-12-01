setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX_FOO="bats.index.replace.foo"
  TEST_INDEX_BAR="bats.index.replace.bar"

  H_CONTENT_TYPE="Content-Type: application/json"

  # Cleanup any existing test indices
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null 2>&1 || true

  # Create indices directly with curl using Datashare mappings
  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null

  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX_BAR/_doc/0" -d'{ "name": "kimchi", "path": "/", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX_BAR/_refresh" > /dev/null
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null 2>&1 || true
}


@test "cannot run replace without a source index and a target index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/replace.sh
}

@test "can replace 'foo' index by 'bar' index" {
    run ./elasticsearch/index/replace.sh $TEST_INDEX_BAR $TEST_INDEX_FOO
    run ./elasticsearch/index/refresh.sh $TEST_INDEX_FOO
    count=$(./elasticsearch/document/count.sh $TEST_INDEX_FOO)
    assert_equal ${count} 1
}