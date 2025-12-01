setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.document.count"
  H_CONTENT_TYPE="Content-Type: application/json"

  # Delete index if it exists
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  # Create index directly with curl using Datashare mappings
  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/0 -d'{ "name": "kimchi", "path": "/", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/1 -d'{ "name": "tteokbokki", "path": "/", "type": "Document" }' -H "$H_CONTENT_TYPE"  > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/3 -d'{ "name": "bulgogi", "path": "/dish", "type": "Document" }' -H "$H_CONTENT_TYPE"  > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_refresh > /dev/null
}


teardown() {
  curl -sXDELETE $ELASTICSEARCH_URL/$TEST_INDEX > /dev/null 2>&1 || true
}


@test "cannot run count without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/document/count.sh
}

@test "can run count with an index" {
    count=$(./elasticsearch/document/count.sh $TEST_INDEX)
    assert_equal ${count} 3
}

@test "can run count with an index and a path" {
    count=$(./elasticsearch/document/count.sh $TEST_INDEX /dish)
    assert_equal ${count} 1
}

@test "can run count with an index, a path and a query string" {
    count=$(./elasticsearch/document/count.sh $TEST_INDEX / tteokbokki)
    assert_equal ${count} 1
}
