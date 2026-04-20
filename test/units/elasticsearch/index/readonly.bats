setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX_FOO="bats.index.readonly.foo"
  TEST_INDEX_BAR="bats.index.readonly.bar"

  H_CONTENT_TYPE="Content-Type: application/json"

  # Clean any index leftover from a previous failed run
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null 2>&1 || true

  # Create two empty indices (mappings don't matter here, only settings)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null
}

teardown() {
  # Restore writes first — a readonly index with blocks.write=true can still
  # be deleted, but we unblock to keep the state clean for following runs
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_FOO/_settings" -H "$H_CONTENT_TYPE" -d'{ "index": { "blocks.write": false } }' > /dev/null 2>&1 || true
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_BAR/_settings" -H "$H_CONTENT_TYPE" -d'{ "index": { "blocks.write": false } }' > /dev/null 2>&1 || true

  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null 2>&1 || true
}


@test "cannot run readonly without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/readonly.sh
}

@test "reports that a fresh index is not readonly" {
    run ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO
    assert_success
    assert_line --regexp "$TEST_INDEX_FOO.*no"
}

@test "can mark an index as readonly" {
    run ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO true
    assert_success

    run ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO
    assert_line --regexp "$TEST_INDEX_FOO.*yes"
}

@test "can unmark an index as readonly" {
    ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO true > /dev/null

    run ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO false
    assert_success

    run ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO
    assert_line --regexp "$TEST_INDEX_FOO.*no"
}

@test "reports readonly status for several indices at once" {
    ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO true > /dev/null

    run ./elasticsearch/index/readonly.sh "$TEST_INDEX_FOO,$TEST_INDEX_BAR"
    assert_success
    assert_line --regexp "$TEST_INDEX_FOO.*yes"
    assert_line --regexp "$TEST_INDEX_BAR.*no"
}

@test "supports wildcards when reporting status" {
    ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO true > /dev/null

    run ./elasticsearch/index/readonly.sh "bats.index.readonly.*"
    assert_success
    assert_line --regexp "$TEST_INDEX_FOO.*yes"
    assert_line --regexp "$TEST_INDEX_BAR.*no"
}

@test "renders a table header when reporting status" {
    run ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO
    assert_success
    assert_output --partial "INDEX"
    assert_output --partial "READONLY"
}

@test "actually blocks writes when set to true" {
    ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO true > /dev/null

    # Direct write should fail with a ClusterBlockException
    response=$(curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX_FOO/_doc/1" -H "$H_CONTENT_TYPE" -d'{ "name": "blocked" }')
    echo "$response" | grep -q "blocked by"
}

@test "restores writes when set to false" {
    ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO true > /dev/null
    ./elasticsearch/index/readonly.sh $TEST_INDEX_FOO false > /dev/null

    # Write should now succeed
    response=$(curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX_FOO/_doc/1" -H "$H_CONTENT_TYPE" -d'{ "name": "allowed" }')
    result=$(echo "$response" | jq -r '.result')
    assert_equal "$result" "created"
}
