load ../../../lib/cli.sh

setup () {
  load ../../test_helper/bats-assert/load
  load ../../test_helper/bats-support/load
}

# term_width tests
@test "term_width returns a number" {
  result=$(term_width)
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "term_width returns at least 80 when not in terminal" {
  result=$(term_width)
  [[ "$result" -ge 80 ]]
}

# truncate tests
@test "truncate returns string unchanged if shorter than max" {
  result=$(truncate "short" 10)
  assert_equal "$result" "short"
}

@test "truncate truncates string with ellipsis if longer than max" {
  result=$(truncate "this is a very long string" 10)
  assert_equal "$result" "this is..."
}

@test "truncate handles exact length" {
  result=$(truncate "exact" 5)
  assert_equal "$result" "exact"
}

@test "truncate handles empty string" {
  result=$(truncate "" 10)
  assert_equal "$result" ""
}

@test "truncate handles max width of 3 or less" {
  result=$(truncate "hello" 3)
  assert_equal "$result" "hel"
}

@test "truncate handles max width of 1" {
  result=$(truncate "hello" 1)
  assert_equal "$result" "h"
}

# draw_line tests
@test "draw_line creates line of specified length" {
  result=$(draw_line 5)
  line_count=$(echo "$result" | grep -o "─" | wc -l)
  assert_equal "$line_count" "5"
}

@test "draw_line creates line of default length" {
  result=$(draw_line)
  [[ "$result" == *"─"* ]]
}

# format_duration_s tests
@test "format_duration_s formats seconds" {
  result=$(format_duration_s 45)
  assert_equal "$result" "45s"
}

@test "format_duration_s formats minutes and seconds" {
  result=$(format_duration_s 125)
  assert_equal "$result" "2m 5s"
}

@test "format_duration_s formats hours and minutes" {
  result=$(format_duration_s 3725)
  assert_equal "$result" "1h 2m"
}

@test "format_duration_s handles zero" {
  result=$(format_duration_s 0)
  assert_equal "$result" "0s"
}

@test "format_duration_s handles empty input" {
  result=$(format_duration_s "")
  assert_equal "$result" "0s"
}

@test "format_duration_s handles null input" {
  result=$(format_duration_s "null")
  assert_equal "$result" "0s"
}

# format_duration_ns tests
@test "format_duration_ns converts nanoseconds to readable format" {
  result=$(format_duration_ns 125000000000)
  assert_equal "$result" "2m 5s"
}

@test "format_duration_ns handles zero" {
  result=$(format_duration_ns 0)
  assert_equal "$result" "0s"
}

@test "format_duration_ns handles empty input" {
  result=$(format_duration_ns "")
  assert_equal "$result" "0s"
}

@test "format_duration_ns handles null input" {
  result=$(format_duration_ns "null")
  assert_equal "$result" "0s"
}

# format_status tests
@test "format_status returns Running for running status" {
  result=$(format_status "running")
  [[ "$result" == *"Running"* ]]
}

@test "format_status returns Completed for completed status" {
  result=$(format_status "completed")
  [[ "$result" == *"Completed"* ]]
}

@test "format_status returns Completed for true status" {
  result=$(format_status "true")
  [[ "$result" == *"Completed"* ]]
}

@test "format_status returns Failed for failed status" {
  result=$(format_status "failed")
  [[ "$result" == *"Failed"* ]]
}

@test "format_status returns Pending for pending status" {
  result=$(format_status "pending")
  [[ "$result" == *"Pending"* ]]
}

@test "format_status returns unknown status unchanged" {
  result=$(format_status "unknown")
  [[ "$result" == *"unknown"* ]]
}

@test "format_status handles capitalized Running" {
  result=$(format_status "Running")
  [[ "$result" == *"Running"* ]]
}

@test "format_status handles error as failed" {
  result=$(format_status "error")
  [[ "$result" == *"Failed"* ]]
}

# format_count tests
@test "format_count formats created count with green" {
  result=$(format_count "created" "100")
  [[ "$result" == *"100"* ]]
  [[ "$result" == *"32m"* ]]
}

@test "format_count formats updated count with yellow" {
  result=$(format_count "updated" "50")
  [[ "$result" == *"50"* ]]
  [[ "$result" == *"33m"* ]]
}

@test "format_count formats deleted count with red" {
  result=$(format_count "deleted" "25")
  [[ "$result" == *"25"* ]]
  [[ "$result" == *"31m"* ]]
}

@test "format_count formats failures count with red" {
  result=$(format_count "failures" "5")
  [[ "$result" == *"5"* ]]
  [[ "$result" == *"31m"* ]]
}

@test "format_count formats failed count with red" {
  result=$(format_count "failed" "3")
  [[ "$result" == *"3"* ]]
  [[ "$result" == *"31m"* ]]
}

@test "format_count returns value unchanged for unknown type" {
  result=$(format_count "unknown" "42")
  [[ "$result" == *"42"* ]]
}

@test "format_count handles zero value" {
  result=$(format_count "created" "0")
  [[ "$result" == *"0"* ]]
}
