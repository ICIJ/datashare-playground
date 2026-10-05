setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.index.verify"
  STATE_FILE=$(mktemp)

  H_CONTENT_TYPE="Content-Type: application/json"

  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  # Create index directly with curl using Datashare mappings
  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null

  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/1" -d'{ "name": "doc1", "path": "/test", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/2" -d'{ "name": "doc2", "path": "/test", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/3" -d'{ "name": "doc3", "path": "/other", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true
  rm -f "$STATE_FILE"
}

@test "verify samples documents without sorting on _id" {
  run ./elasticsearch/index/verify.sh --save "$STATE_FILE" "$TEST_INDEX"
  assert_success
  run grep -c '^sample_doc' "$STATE_FILE"
  assert_output "3"
}

@test "verify compare passes on an unchanged index" {
  ./elasticsearch/index/verify.sh --save "$STATE_FILE" "$TEST_INDEX" > /dev/null
  run ./elasticsearch/index/verify.sh --compare "$STATE_FILE" "$TEST_INDEX"
  assert_success
  assert_output --partial "all present"
}

@test "verify compare fails when the document count changes" {
  ./elasticsearch/index/verify.sh --save "$STATE_FILE" "$TEST_INDEX" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/4" -d'{ "name": "doc4", "path": "/new", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
  run ./elasticsearch/index/verify.sh --compare "$STATE_FILE" "$TEST_INDEX"
  assert_failure
  assert_output --partial "Document count changed: 3 before, 4 now"
}

@test "verify compare fails when a sampled document is missing" {
  ./elasticsearch/index/verify.sh --save "$STATE_FILE" "$TEST_INDEX" > /dev/null
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/1?refresh=true" > /dev/null
  run ./elasticsearch/index/verify.sh --compare "$STATE_FILE" "$TEST_INDEX"
  assert_failure
  assert_output --partial "sample document missing: 1"
}
