setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.document.move"
  H_CONTENT_TYPE="Content-Type: application/json"

  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null

  # the whole old prefix appears twice, which is what a non-anchored replace mangles
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/repeat" -H "$H_CONTENT_TYPE" \
    -d '{"type":"Document","path":"/data/foo/bar/data/foo/x.pdf","dirname":"/data/foo/bar/data/foo"}' > /dev/null
  # sibling directory sharing a name prefix, to catch a missing trailing slash
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/sibling" -H "$H_CONTENT_TYPE" \
    -d '{"type":"Document","path":"/data/foobar/y.pdf","dirname":"/data/foobar"}' > /dev/null
  # Duplicate carries a path and no dirname
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/dup" -H "$H_CONTENT_TYPE" \
    -d '{"type":"Duplicate","path":"/data/foo/z.pdf","documentId":"direct"}' > /dev/null
  # file directly inside the renamed directory: dirname equals it exactly, no trailing slash
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/direct" -H "$H_CONTENT_TYPE" \
    -d '{"type":"Document","path":"/data/foo/z.pdf","dirname":"/data/foo"}' > /dev/null

  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true
}

# Read one _source field of one document
field() {
  curl -s "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/$1" | jq -r "._source.$2"
}

@test "cannot run move without enough arguments" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/document/move.sh
    run ! ./elasticsearch/document/move.sh $TEST_INDEX /data/foo
}

@test "rewrites only the leading occurrence of a repeated prefix" {
    ./elasticsearch/document/move.sh $TEST_INDEX /data/foo /data/baz
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field repeat path)" "/data/baz/bar/data/foo/x.pdf"
    assert_equal "$(field repeat dirname)" "/data/baz/bar/data/foo"
}

@test "does not touch a sibling directory sharing a name prefix" {
    ./elasticsearch/document/move.sh $TEST_INDEX /data/foo /data/baz
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field sibling path)" "/data/foobar/y.pdf"
    assert_equal "$(field sibling dirname)" "/data/foobar"
}

@test "moves Duplicate documents, which carry no dirname" {
    ./elasticsearch/document/move.sh $TEST_INDEX /data/foo /data/baz
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field dup path)" "/data/baz/z.pdf"
}

@test "moves a dirname that equals the renamed directory exactly" {
    ./elasticsearch/document/move.sh $TEST_INDEX /data/foo /data/baz
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field direct path)" "/data/baz/z.pdf"
    assert_equal "$(field direct dirname)" "/data/baz"
}

@test "handles a directory name containing a quote and a tab" {
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/weird" -H "$H_CONTENT_TYPE" \
      -d "$(jq -nc '{type:"Document", path:"/data/we\"ird\tdir/a.pdf", dirname:"/data/we\"ird\tdir"}')" > /dev/null
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    ./elasticsearch/document/move.sh $TEST_INDEX "$(printf '/data/we"ird\tdir')" /data/clean
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field weird path)" "/data/clean/a.pdf"
    assert_equal "$(field weird dirname)" "/data/clean"
}
