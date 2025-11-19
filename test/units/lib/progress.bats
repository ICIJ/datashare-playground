load ../../../lib/cli.sh

setup () {
  load ../../test_helper/bats-assert/load
  load ../../test_helper/bats-support/load
}

@test "progress_bar shows 0% correctly" {
  result=$(progress_bar 0 10)
  # Should have all empty chars and 0%
  [[ "$result" == *"0%"* ]]
  [[ "$result" == *"─"* ]]
}

@test "progress_bar shows 100% correctly" {
  result=$(progress_bar 100 10)
  # Should have all filled chars and 100%
  [[ "$result" == *"100%"* ]]
  [[ "$result" == *"━"* ]]
}

@test "progress_bar shows 50% correctly" {
  result=$(progress_bar 50 10)
  # Should have 50%
  [[ "$result" == *"50%"* ]]
  # Should have both filled and empty chars
  [[ "$result" == *"━"* ]]
  [[ "$result" == *"─"* ]]
}

@test "progress_bar respects custom width" {
  result=$(progress_bar 100 5)
  # Count the number of filled chars (should be 5)
  filled_count=$(echo "$result" | grep -o "━" | wc -l)
  assert_equal "$filled_count" "5"
}

@test "progress_bar uses default width of 20" {
  result=$(progress_bar 100)
  # Count the number of filled chars (should be 20)
  filled_count=$(echo "$result" | grep -o "━" | wc -l)
  assert_equal "$filled_count" "20"
}

@test "progress_bar clamps negative percent to 0" {
  result=$(progress_bar -10 10)
  [[ "$result" == *"0%"* ]]
  # Should have no filled chars
  if [[ "$result" == *"━"* ]]; then
    return 1
  fi
}

@test "progress_bar clamps percent over 100 to 100" {
  result=$(progress_bar 150 10)
  [[ "$result" == *"100%"* ]]
  filled_count=$(echo "$result" | grep -o "━" | wc -l)
  assert_equal "$filled_count" "10"
}

@test "progress_bar handles empty percent" {
  result=$(progress_bar "" 10)
  [[ "$result" == *"0%"* ]]
}

@test "progress_bar handles non-numeric percent" {
  result=$(progress_bar "abc" 10)
  [[ "$result" == *"0%"* ]]
}

@test "progress_bar handles zero width by using default" {
  result=$(progress_bar 50 0)
  # Should use default width of 20
  total_count=$(echo "$result" | grep -o "[━─]" | wc -l)
  assert_equal "$total_count" "20"
}

@test "progress_bar handles negative width by using default" {
  result=$(progress_bar 50 -5)
  total_count=$(echo "$result" | grep -o "[━─]" | wc -l)
  assert_equal "$total_count" "20"
}
