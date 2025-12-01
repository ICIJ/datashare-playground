setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX_FOO="bats.index.create.from.version.foo"
  VERSION="17.1.0"

  H_CONTENT_TYPE="Content-Type: application/json"

  # Cleanup any existing test index
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
}


@test "cannot run create_from_version without a source index and a version number" {
    bats_require_minimum_version 1.5.0

    run  ./elasticsearch/index/create.sh
}

@test "can create a foo index" {
    run ./elasticsearch/index/create.sh $TEST_INDEX_FOO
    run ./elasticsearch/index/list.sh
    assert_output --partial $TEST_INDEX_FOO
}

@test "can create a foo index from specified version" {
    run ./elasticsearch/index/create.sh $TEST_INDEX_FOO $VERSION
    run ./elasticsearch/index/list.sh
    assert_output --partial $TEST_INDEX_FOO
}