load ../../../lib/cli.sh

setup () {
  load ../../test_helper/bats-assert/load
  load ../../test_helper/bats-support/load
}

@test "log_info outputs with checkmark" {
  run log_info "test message"
  assert_success
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"test message"* ]]
}

@test "log_warn outputs with exclamation" {
  run log_warn "warning message"
  assert_success
  [[ "$output" == *"!"* ]]
  [[ "$output" == *"warning message"* ]]
}

@test "log_error outputs with cross" {
  run log_error "error message"
  assert_success
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"error message"* ]]
}

@test "log_kv outputs key-value pair" {
  run log_kv "Key" "Value"
  assert_success
  [[ "$output" == *"Key"* ]]
  [[ "$output" == *"Value"* ]]
}

@test "log_section outputs section header" {
  run log_section "Section"
  assert_success
  [[ "$output" == *"Section"* ]]
}

@test "log_task outputs with checkmark" {
  run log_task "task done"
  assert_success
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"task done"* ]]
}

@test "log_task_error outputs with cross" {
  run log_task_error "task failed"
  assert_success
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"task failed"* ]]
}

@test "log_task_warn outputs with exclamation" {
  run log_task_warn "task warning"
  assert_success
  [[ "$output" == *"!"* ]]
  [[ "$output" == *"task warning"* ]]
}
