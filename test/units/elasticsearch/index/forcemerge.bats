setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.index.forcemerge.foo"
  H_CONTENT_TYPE="Content-Type: application/json"

  # Clean any index leftover from a previous failed run
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  # Create the index and seed it with a few docs
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/1" -H "$H_CONTENT_TYPE" -d'{ "name": "a" }' > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/2" -H "$H_CONTENT_TYPE" -d'{ "name": "b" }' > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/3" -H "$H_CONTENT_TYPE" -d'{ "name": "c" }' > /dev/null

  # Delete one doc so the index holds a deleted document to expunge
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/2" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true
}

@test "cannot run forcemerge without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/forcemerge.sh
}

@test "returns a task id for a valid index" {
    run ./elasticsearch/index/forcemerge.sh $TEST_INDEX
    assert_success
    task_id=$(echo "$output" | jq -re '.task')
    assert [ -n "$task_id" ]
}

@test "the returned task id is resolvable via task/get.sh" {
    task_id=$(./elasticsearch/index/forcemerge.sh $TEST_INDEX | jq -re '.task')

    run ./elasticsearch/task/get.sh "$task_id"
    assert_success
    assert_output --partial "$task_id"
}
