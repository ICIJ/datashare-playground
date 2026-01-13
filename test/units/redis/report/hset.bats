setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export REDIS_URL=${REDIS_URL:-redis://redis}

  TEST_REPORT="bats:report:hset"

  # Clean up any existing test report
  redis-cli -u "$REDIS_URL" DEL "$TEST_REPORT" > /dev/null 2>&1 || true
}

teardown() {
  redis-cli -u "$REDIS_URL" DEL "$TEST_REPORT" > /dev/null 2>&1 || true
}

@test "cannot run hset without a report name" {
  bats_require_minimum_version 1.5.0

  run ! ./redis/report/hset.sh
}

@test "hset does nothing with empty stdin" {
  run ./redis/report/hset.sh "$TEST_REPORT" < /dev/null

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 0
}

@test "hset can add a single path to report" {
  echo "/path/to/file.pdf" | ./redis/report/hset.sh "$TEST_REPORT"

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 1

  value=$(redis-cli -u "$REDIS_URL" HGET "$TEST_REPORT" "/path/to/file.pdf")
  assert_equal "$value" "0"
}

@test "hset can add multiple paths to report" {
  printf '%s\n' "/path/to/file1.pdf" "/path/to/file2.pdf" "/path/to/file3.pdf" | ./redis/report/hset.sh "$TEST_REPORT"

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 3
}

@test "hset sets value to 0 for all paths" {
  printf '%s\n' "/path/1" "/path/2" "/path/3" | ./redis/report/hset.sh "$TEST_REPORT"

  value1=$(redis-cli -u "$REDIS_URL" HGET "$TEST_REPORT" "/path/1")
  value2=$(redis-cli -u "$REDIS_URL" HGET "$TEST_REPORT" "/path/2")
  value3=$(redis-cli -u "$REDIS_URL" HGET "$TEST_REPORT" "/path/3")

  assert_equal "$value1" "0"
  assert_equal "$value2" "0"
  assert_equal "$value3" "0"
}

@test "hset respects batch size" {
  printf '%s\n' "/path/1" "/path/2" "/path/3" "/path/4" "/path/5" | ./redis/report/hset.sh "$TEST_REPORT" 2

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 5
}
