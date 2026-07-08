setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  # Source .env to get ELASTICSEARCH_URL
  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX_FOO="bats.index.alias.foo"
  TEST_INDEX_BAR="bats.index.alias.bar"
  TEST_ALIAS="bats.index.alias.pointer"

  # Clean any leftover from a previous failed run (dropping an index drops its aliases)
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null 2>&1 || true

  # Create two empty indices
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_FOO" > /dev/null 2>&1 || true
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX_BAR" > /dev/null 2>&1 || true
}

@test "cannot run alias without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/alias.sh
}

@test "fails when --remove is the only argument" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/alias.sh --remove
}

@test "reports no aliases for a fresh index" {
    run ./elasticsearch/index/alias.sh $TEST_INDEX_FOO
    assert_success
    assert_line --regexp "$TEST_INDEX_FOO.*-"
}

@test "renders a table header when listing" {
    run ./elasticsearch/index/alias.sh $TEST_INDEX_FOO
    assert_success
    assert_output --partial "INDEX"
    assert_output --partial "ALIAS"
}

@test "lists several indices at once" {
    run ./elasticsearch/index/alias.sh "bats.index.alias.*"
    assert_success
    assert_line --regexp "$TEST_INDEX_FOO.*-"
    assert_line --regexp "$TEST_INDEX_BAR.*-"
}
