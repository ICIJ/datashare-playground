setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export REDIS_URL=${REDIS_URL:-redis://redis}

  TEST_QUEUE="bats:queue:rpush"

  # Clean up any existing test queue
  redis-cli -u "$REDIS_URL" DEL "$TEST_QUEUE" > /dev/null 2>&1 || true
}

teardown() {
  redis-cli -u "$REDIS_URL" DEL "$TEST_QUEUE" > /dev/null 2>&1 || true
}

@test "cannot run rpush without a queue name" {
  bats_require_minimum_version 1.5.0

  run ! ./redis/queue/rpush.sh
}

@test "rpush does nothing with empty stdin" {
  run ./redis/queue/rpush.sh "$TEST_QUEUE" < /dev/null

  count=$(redis-cli -u "$REDIS_URL" LLEN "$TEST_QUEUE")
  assert_equal "$count" 0
}

@test "rpush can add a single item to queue" {
  echo "/path/to/file.pdf" | ./redis/queue/rpush.sh "$TEST_QUEUE"

  count=$(redis-cli -u "$REDIS_URL" LLEN "$TEST_QUEUE")
  assert_equal "$count" 1

  value=$(redis-cli -u "$REDIS_URL" LINDEX "$TEST_QUEUE" 0)
  assert_equal "$value" "/path/to/file.pdf"
}

@test "rpush can add multiple items to queue" {
  printf '%s\n' "/path/to/file1.pdf" "/path/to/file2.pdf" "/path/to/file3.pdf" | ./redis/queue/rpush.sh "$TEST_QUEUE"

  count=$(redis-cli -u "$REDIS_URL" LLEN "$TEST_QUEUE")
  assert_equal "$count" 3
}

@test "rpush respects batch size" {
  # Create 5 items with batch size 2 (should result in 3 batches: 2+2+1)
  printf '%s\n' "/path/1" "/path/2" "/path/3" "/path/4" "/path/5" | ./redis/queue/rpush.sh "$TEST_QUEUE" 2

  count=$(redis-cli -u "$REDIS_URL" LLEN "$TEST_QUEUE")
  assert_equal "$count" 5
}

@test "rpush preserves item order" {
  printf '%s\n' "first" "second" "third" | ./redis/queue/rpush.sh "$TEST_QUEUE"

  first=$(redis-cli -u "$REDIS_URL" LINDEX "$TEST_QUEUE" 0)
  second=$(redis-cli -u "$REDIS_URL" LINDEX "$TEST_QUEUE" 1)
  third=$(redis-cli -u "$REDIS_URL" LINDEX "$TEST_QUEUE" 2)

  assert_equal "$first" "first"
  assert_equal "$second" "second"
  assert_equal "$third" "third"
}
