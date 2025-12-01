setup() {
  load ../../../../test_helper/bats-assert/load
  load ../../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.document.agg"
  H_CONTENT_TYPE="Content-Type: application/json"

  # Delete index if it exists
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  # Create index directly with curl using Datashare mappings
  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/0 -d'{ "name": "kimchi", "path": "/", "type": "Document", "contentLength": 100 }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/1 -d'{ "name": "tteokbokki", "path": "/", "type": "Document", "contentLength": 200 }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/2 -d'{ "name": "bulgogi", "path": "/dish", "type": "Document", "contentLength": 300 }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/3 -d'{ "name": "bibimbap", "path": "/dish", "type": "Document", "contentLength": 400 }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_refresh > /dev/null
}

teardown() {
  curl -sXDELETE $ELASTICSEARCH_URL/$TEST_INDEX > /dev/null
}

# sum.sh tests

@test "sum: cannot run without an index" {
    bats_require_minimum_version 1.5.0
    run ! ./elasticsearch/document/agg/sum.sh
}

@test "sum: cannot run without a field" {
    bats_require_minimum_version 1.5.0
    run ! ./elasticsearch/document/agg/sum.sh $TEST_INDEX
}

@test "sum: can sum a field" {
    result=$(./elasticsearch/document/agg/sum.sh $TEST_INDEX contentLength)
    assert_equal "$result" "1000"
}

@test "sum: can sum a field with path filter" {
    result=$(./elasticsearch/document/agg/sum.sh $TEST_INDEX contentLength /dish)
    assert_equal "$result" "700"
}

@test "sum: can sum a field with query string" {
    result=$(./elasticsearch/document/agg/sum.sh $TEST_INDEX contentLength / "name:kimchi")
    assert_equal "$result" "100"
}

# avg.sh tests

@test "avg: cannot run without an index" {
    bats_require_minimum_version 1.5.0
    run ! ./elasticsearch/document/agg/avg.sh
}

@test "avg: can average a field" {
    result=$(./elasticsearch/document/agg/avg.sh $TEST_INDEX contentLength)
    assert_equal "$result" "250"
}

@test "avg: can average a field with path filter" {
    result=$(./elasticsearch/document/agg/avg.sh $TEST_INDEX contentLength /dish)
    assert_equal "$result" "350"
}

@test "avg: can average a field with query string" {
    result=$(./elasticsearch/document/agg/avg.sh $TEST_INDEX contentLength / "name:kimchi OR name:tteokbokki")
    assert_equal "$result" "150"
}

# min.sh tests

@test "min: cannot run without an index" {
    bats_require_minimum_version 1.5.0
    run ! ./elasticsearch/document/agg/min.sh
}

@test "min: can get minimum of a field" {
    result=$(./elasticsearch/document/agg/min.sh $TEST_INDEX contentLength)
    assert_equal "$result" "100"
}

@test "min: can get minimum with path filter" {
    result=$(./elasticsearch/document/agg/min.sh $TEST_INDEX contentLength /dish)
    assert_equal "$result" "300"
}

# max.sh tests

@test "max: cannot run without an index" {
    bats_require_minimum_version 1.5.0
    run ! ./elasticsearch/document/agg/max.sh
}

@test "max: can get maximum of a field" {
    result=$(./elasticsearch/document/agg/max.sh $TEST_INDEX contentLength)
    assert_equal "$result" "400"
}

@test "max: can get maximum with path filter" {
    result=$(./elasticsearch/document/agg/max.sh $TEST_INDEX contentLength /)
    assert_equal "$result" "400"
}

# count.sh tests

@test "count: cannot run without an index" {
    bats_require_minimum_version 1.5.0
    run ! ./elasticsearch/document/agg/count.sh
}

@test "count: can count field values" {
    result=$(./elasticsearch/document/agg/count.sh $TEST_INDEX contentLength)
    assert_equal "$result" "4"
}

@test "count: can count field values with path filter" {
    result=$(./elasticsearch/document/agg/count.sh $TEST_INDEX contentLength /dish)
    assert_equal "$result" "2"
}

@test "count: can count field values with query string" {
    result=$(./elasticsearch/document/agg/count.sh $TEST_INDEX contentLength / "name:bulgogi")
    assert_equal "$result" "1"
}
