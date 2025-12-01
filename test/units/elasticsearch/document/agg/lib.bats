load ../../../../test_helper/bats-assert/load
load ../../../../test_helper/bats-support/load

# Load dependencies for the lib
export ELASTICSEARCH_URL="http://localhost:9200"
source lib/cli.sh
source elasticsearch/document/agg/lib.sh

# Test agg_query builds correct request body
@test "agg_query function is defined" {
    run type agg_query
    assert_success
}

@test "agg_count_query function is defined" {
    run type agg_count_query
    assert_success
}
