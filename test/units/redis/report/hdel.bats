setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export REDIS_URL=${REDIS_URL:-redis://redis}

  TEST_REPORT="bats:report:hdel"

  # Clean up and create test report with sample data
  redis-cli -u "$REDIS_URL" DEL "$TEST_REPORT" > /dev/null 2>&1 || true
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/path/to/file1.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/path/to/file2.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/path/to/file3.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/other/path/file.pdf" "0" > /dev/null
}

teardown() {
  redis-cli -u "$REDIS_URL" DEL "$TEST_REPORT" > /dev/null 2>&1 || true
}

@test "cannot run hdel without a report name" {
  bats_require_minimum_version 1.5.0

  run ! ./redis/report/hdel.sh
}

@test "hdel does nothing with empty stdin" {
  run ./redis/report/hdel.sh "$TEST_REPORT" < /dev/null

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 4
}

@test "hdel can remove a single path from report" {
  echo "/path/to/file1.pdf" | ./redis/report/hdel.sh "$TEST_REPORT"

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 3

  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/path/to/file1.pdf")
  assert_equal "$exists" "0"
}

@test "hdel can remove multiple paths from report" {
  printf '%s\n' "/path/to/file1.pdf" "/path/to/file2.pdf" | ./redis/report/hdel.sh "$TEST_REPORT"

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 2
}

@test "hdel ignores non-existent paths" {
  echo "/nonexistent/path.pdf" | ./redis/report/hdel.sh "$TEST_REPORT"

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 4
}

@test "hdel respects batch size" {
  printf '%s\n' "/path/to/file1.pdf" "/path/to/file2.pdf" "/path/to/file3.pdf" | ./redis/report/hdel.sh "$TEST_REPORT" 2

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 1

  # Only /other/path/file.pdf should remain
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/other/path/file.pdf")
  assert_equal "$exists" "1"
}
