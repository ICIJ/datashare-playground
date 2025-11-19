load ../../../lib/cli.sh

setup () {
  load ../../test_helper/bats-assert/load
  load ../../test_helper/bats-support/load
}

@test "table_header outputs header with bold formatting" {
  run table_header "COL1:10" "COL2:20"
  assert_success
  [[ "$output" == *"COL1"* ]]
  [[ "$output" == *"COL2"* ]]
}

@test "table_header outputs multiple columns" {
  run table_header "A:5" "B:10" "C:15"
  assert_success
  [[ "$output" == *"A"* ]]
  [[ "$output" == *"B"* ]]
  [[ "$output" == *"C"* ]]
}

@test "table_header draws line after header" {
  run table_header "COL1:10"
  assert_success
  [[ "$output" == *"─"* ]]
}

@test "table_row outputs values" {
  run table_row "val1" "val2" -- "10" "20"
  assert_success
  [[ "$output" == *"val1"* ]]
  [[ "$output" == *"val2"* ]]
}
