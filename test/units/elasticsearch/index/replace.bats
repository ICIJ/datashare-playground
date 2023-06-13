export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load
  
  TEST_INDEX_FOO="bats.index.replace.foo"
  TEST_INDEX_BAR="bats.index.replace.bar"
  
  H_CONTENT_TYPE="Content-Type: application/json"

  command ./elasticsearch/index/create.sh $TEST_INDEX_FOO
  command ./elasticsearch/index/create.sh $TEST_INDEX_BAR

  curl -sXPOST $ELASTICSEARCH_URL/$TEST_INDEX_BAR/_doc/0 -d'{ "name": "kimchi", "path": "/", "type": "Document" }' -H "$H_CONTENT_TYPE" > /dev/null
}


teardown() {
  curl -sXDELETE $ELASTICSEARCH_URL/$TEST_INDEX_FOO > /dev/null
  curl -sXDELETE $ELASTICSEARCH_URL/$TEST_INDEX_BAR > /dev/null
}


@test "cannot run replace without a source index and a target index" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/index/replace.sh
}

@test "can replace 'foo' index by 'bar' index" {
    run ./elasticsearch/index/replace.sh $TEST_INDEX_BAR $TEST_INDEX_FOO
    run ./elasticsearch/index/refresh.sh $TEST_INDEX_FOO
    count=$(./elasticsearch/document/count.sh $TEST_INDEX_FOO)
    assert_equal ${count} 1
}