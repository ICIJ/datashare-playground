export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load
  
  TEST_INDEX="bats.document.count"
  H_CONTENT_TYPE="Content-Type: application/json"
  command ./elasticsearch/index/create.sh $TEST_INDEX
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/0 -d'{ "name": "kimchi", "path": "/", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/1 -d'{ "name": "tteokbokki", "path": "/", "type": "Document" }' -H "$H_CONTENT_TYPE"  > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_doc/3 -d'{ "name": "bulgogi", "path": "/dish", "type": "Document" }' -H "$H_CONTENT_TYPE"  > /dev/null
  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX/_refresh
}


teardown() {
  curl -sXDELETE $ELASTICSEARCH_URL/$TEST_INDEX > /dev/null
}


@test "cannot run count without an index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/document/count.sh
}

@test "can run count with an index" {
    count=$(./elasticsearch/document/count.sh $TEST_INDEX)
    assert_equal ${count} 3
}

@test "can run count with an index and a path" {
    count=$(./elasticsearch/document/count.sh $TEST_INDEX /dish)
    assert_equal ${count} 1
}

@test "can run count with an index, a path and a query string" {
    count=$(./elasticsearch/document/count.sh $TEST_INDEX / tteokbokki)
    assert_equal ${count} 1
}
