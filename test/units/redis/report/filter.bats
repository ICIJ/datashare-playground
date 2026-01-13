setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export REDIS_URL=${REDIS_URL:-redis://redis}

  TEST_REPORT="bats:report:filter"

  # Clean up and create test report with sample data
  redis-cli -u "$REDIS_URL" DEL "$TEST_REPORT" > /dev/null 2>&1 || true
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/data/project1/file1.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/data/project1/file2.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/data/project1/subdir/file3.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/data/project2/file1.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/other/path/file.pdf" "0" > /dev/null
}

teardown() {
  redis-cli -u "$REDIS_URL" DEL "$TEST_REPORT" > /dev/null 2>&1 || true
}

@test "cannot run filter without a report name" {
  bats_require_minimum_version 1.5.0

  run ! ./redis/report/filter.sh
}

@test "filter removes paths matching prefix" {
  ./redis/report/filter.sh "$TEST_REPORT" "/data/project1/" > /dev/null 2>&1

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 2

  # project1 files should be gone
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project1/file1.pdf")
  assert_equal "$exists" "0"

  # project2 and other should remain
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project2/file1.pdf")
  assert_equal "$exists" "1"
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/other/path/file.pdf")
  assert_equal "$exists" "1"
}

@test "filter removes all paths under a parent directory" {
  ./redis/report/filter.sh "$TEST_REPORT" "/data/" > /dev/null 2>&1

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 1

  # Only /other/path/file.pdf should remain
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/other/path/file.pdf")
  assert_equal "$exists" "1"
}

@test "filter does nothing when no paths match" {
  ./redis/report/filter.sh "$TEST_REPORT" "/nonexistent/" > /dev/null 2>&1

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 5
}

@test "filter shows correct count in output" {
  run ./redis/report/filter.sh "$TEST_REPORT" "/data/project1/"

  assert_output --partial "Found 3 paths to delete"
  assert_output --partial "Deleted 3 paths"
}

@test "filter reports zero when no matches found" {
  run ./redis/report/filter.sh "$TEST_REPORT" "/nonexistent/"

  assert_output --partial "No paths found"
}

@test "filter respects batch size parameter" {
  ./redis/report/filter.sh "$TEST_REPORT" "/data/" 2 > /dev/null 2>&1

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 1
}

@test "filter deletes all items with small batch size" {
  # This tests the rescan logic - with batch_size=1, each item triggers a batch flush
  # which modifies the hash during iteration, potentially invalidating the cursor
  ./redis/report/filter.sh "$TEST_REPORT" "/data/project1/" 1 > /dev/null 2>&1

  count=$(redis-cli -u "$REDIS_URL" HLEN "$TEST_REPORT")
  assert_equal "$count" 2

  # All project1 files (including subdir) should be gone
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project1/file1.pdf")
  assert_equal "$exists" "0"
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project1/file2.pdf")
  assert_equal "$exists" "0"
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project1/subdir/file3.pdf")
  assert_equal "$exists" "0"

  # project2 and other should remain
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project2/file1.pdf")
  assert_equal "$exists" "1"
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/other/path/file.pdf")
  assert_equal "$exists" "1"
}

@test "filter handles special glob characters in prefix" {
  # Add paths with special characters
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/data/[special]/file.pdf" "0" > /dev/null
  redis-cli -u "$REDIS_URL" HSET "$TEST_REPORT" "/data/[special]/other.pdf" "0" > /dev/null

  ./redis/report/filter.sh "$TEST_REPORT" "/data/[special]/" > /dev/null 2>&1

  # The special paths should be removed
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/[special]/file.pdf")
  assert_equal "$exists" "0"

  # Regular paths should still exist
  exists=$(redis-cli -u "$REDIS_URL" HEXISTS "$TEST_REPORT" "/data/project1/file1.pdf")
  assert_equal "$exists" "1"
}
