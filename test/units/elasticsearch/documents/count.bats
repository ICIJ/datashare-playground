export ELASTICSEARCH_URL=http://elasticsearch:9200

@test "cannot run count without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/document/count.sh
}

@test "can run count with an index" {
    command ./elasticsearch/document/count.sh local-datashare
}