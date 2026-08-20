setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.document.rename"
  H_CONTENT_TYPE="Content-Type: application/json"
  MANIFEST="$BATS_TEST_TMPDIR/manifest.jsonl"

  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null
}

teardown() {
  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true
}

# Emit one manifest entry. Fixtures are generated, never committed: a file holding a
# raw 0xE9 is one that editors, git diff and CI checkouts can all quietly corrupt.
# Usage: entry <kind> <old> <new> [rules] [mode]
entry() {
  local kind=$1 old=$2 new=$3 rules=${4:-nfc} mode=${5:-clean}
  jq -nc --arg k "$kind" \
         --arg o "$(printf %s "$old" | base64 -w0)" \
         --arg n "$(printf %s "$new" | base64 -w0)" \
         --arg r "$rules" --arg m "$mode" \
    '{kind:$k, old_b64:$o, new_b64:$n, rules:($r|split(",")), mode:$m}'
}

# Emit a meta line, which the reader must ignore
meta() {
  jq -nc --arg r "$(printf %s "$1" | base64 -w0)" \
    '{meta:{root_b64:$r, root:"printable", argv:["pystou","normalize"]}}'
}

seed() {
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/$1" -H "$H_CONTENT_TYPE" -d "$2" > /dev/null
  curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null
}

field() {
  curl -s "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/$1" | jq -r "._source.$2"
}

@test "cannot run rename without an index and a manifest" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/document/rename.sh
    assert_output --partial "Usage:"
    run ! ./elasticsearch/document/rename.sh $TEST_INDEX
    assert_output --partial "Usage:"
}

@test "fails on a missing manifest" {
    bats_require_minimum_version 1.5.0

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX /nope/absent.jsonl
    assert_output --partial "Manifest not found"
}

@test "rejects an unknown option" {
    bats_require_minimum_version 1.5.0

    entry file /data/a.pdf /data/b.pdf > "$MANIFEST"
    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --wat
    assert_output --partial "Unknown option"
}

@test "rejects a --map without an equals sign" {
    bats_require_minimum_version 1.5.0

    entry file /data/a.pdf /data/b.pdf > "$MANIFEST"
    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --map /mnt/nas
    assert_output --partial "--map expects"
}

@test "rejects --dry-run together with --verify" {
    bats_require_minimum_version 1.5.0

    entry file /data/a.pdf /data/b.pdf > "$MANIFEST"
    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run --verify
    assert_output --partial "mutually exclusive"
}

@test "rejects a non-numeric or zero --batch-size" {
    bats_require_minimum_version 1.5.0

    entry file /data/a.pdf /data/b.pdf > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --batch-size abc
    assert_output --partial "--batch-size expects a positive integer"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --batch-size 0
    assert_output --partial "--batch-size expects a positive integer"
}

@test "ignores a line with no kind and reports it as skipped" {
    {
      meta /mnt/nas
      entry file /data/a.pdf /data/b.pdf
      entry dir  /data/x    /data/y
    } > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_output --partial "2 (1 file, 1 dir)"
    assert_output --partial "1 lines without a kind"
}

@test "aborts on an unknown kind" {
    bats_require_minimum_version 1.5.0

    entry symlink /data/a.pdf /data/b.pdf > "$MANIFEST"
    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_output --partial "unknown kind"
}

@test "aborts when an entry is not under the --map host prefix" {
    bats_require_minimum_version 1.5.0

    entry file /elsewhere/a.pdf /elsewhere/b.pdf > "$MANIFEST"
    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --map /mnt/nas=/data --dry-run
    assert_output --partial "not under"
}

@test "aborts when two entries canonicalise to the same old path" {
    bats_require_minimum_version 1.5.0

    {
      entry file "$(printf '/data/caf\xe9.pdf')" /data/cafe1.pdf utf8
      entry file "$(printf '/data/caf\xea.pdf')" /data/cafe2.pdf utf8
    } > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_output --partial "collides"
}

@test "aborts on a rename chain" {
    bats_require_minimum_version 1.5.0

    {
      entry file /data/a.pdf /data/b.pdf
      entry file /data/b.pdf /data/c.pdf
    } > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_output --partial "chain"
}

@test "applies the --map prefix to the reported paths" {
    entry file /mnt/nas/a.pdf /mnt/nas/b.pdf > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --map /mnt/nas=/data --dry-run
    assert_success
    assert_output --partial "/mnt/nas -> /data"
}

@test "groups the report by rules" {
    {
      entry file /data/a.pdf /data/b.pdf nfc
      entry file /data/c.pdf /data/d.pdf nfc
      entry file "$(printf '/data/e\xe9.pdf')" /data/e.pdf utf8
      entry file "$(printf '/data/f\tg.pdf')" /data/fg.pdf control,punct
    } > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_output --partial "nfc"
    assert_output --partial "utf8"
    assert_output --partial "control,punct"
}

@test "a dry run writes nothing" {
    seed keep '{"type":"Document","path":"/data/a.pdf","dirname":"/data"}'
    entry file /data/a.pdf /data/b.pdf > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field keep path)" "/data/a.pdf"
}
