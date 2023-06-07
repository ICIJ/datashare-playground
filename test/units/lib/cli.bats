load ../../../lib/cli.sh

setup () {
  load ../../test_helper/bats-assert/load
  load ../../test_helper/bats-support/load

  TMP_DIR="$(mktemp -d)"
  echo "FOO=bar" > $TMP_DIR/.env
}

@test "throw an error when ELASTICSEARCH_URL is not defined" {
    bats_require_minimum_version 1.5.0
    unset ELASTICSEARCH_URL
    run ! check_elasticsearch_url
}

@test "don't throw an error when ELASTICSEARCH_URL is defined" {
    export ELASTICSEARCH_URL=http://elasticsearch:9200
    check_elasticsearch_url
}

@test "throw an error when REDIS_URL is not defined" {
    bats_require_minimum_version 1.5.0

    run ! check_redis_url
}

@test "don't throw an error when REDIS_URL is defined" {
    export REDIS_URL=redis://redis
    check_redis_url
}

@test "import variables from .env file" {
  check_env $TMP_DIR/.env
  assert_equal ${FOO} bar
}
