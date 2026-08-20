setup() {
  load ../../../test_helper/bats-assert/load
  load ../../../test_helper/bats-support/load

  if [[ -f .env ]]; then
    source .env
  fi
  export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://elasticsearch:9200}

  TEST_INDEX="bats.document.rename.$$"
  H_CONTENT_TYPE="Content-Type: application/json"
  MANIFEST="$BATS_TEST_TMPDIR/manifest.jsonl"

  curl -sXDELETE "$ELASTICSEARCH_URL/$TEST_INDEX" > /dev/null 2>&1 || true

  local resources_dir="./elasticsearch/index/resources"
  local body=$(jq --slurpfile mappings $resources_dir/datashare_index_mappings.json \
    '{ "mappings": $mappings[0], "settings": . }' $resources_dir/datashare_index_settings.json)
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX" -H "$H_CONTENT_TYPE" -d "$body" > /dev/null
}

teardown() {
  curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX/_settings" -H "$H_CONTENT_TYPE" \
    -d '{"index":{"blocks.write":false}}' > /dev/null 2>&1 || true
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

@test "renames a file and leaves its title alone" {
    seed doc '{"type":"Document","path":"/data/plain.pdf","dirname":"/data","title":"Q3 budget"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    assert_success
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field doc path)" "/data/clean.pdf"
    assert_equal "$(field doc title)" "Q3 budget"
    assert_equal "$(field doc dirname)" "/data"
}

@test "a successful refresh prints nothing extra" {
    seed doc '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    assert_success
    refute_output --partial "Failed to refresh"
    refute_output --partial "Refresh Index"
}

@test "renames Duplicate documents sharing the renamed path" {
    seed doc '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    seed dup '{"type":"Duplicate","path":"/data/plain.pdf","documentId":"doc"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field dup path)" "/data/clean.pdf"
}

@test "renames every embedded document sharing the container path" {
    seed root  '{"type":"Document","path":"/data/mail.eml","dirname":"/data","title":"Subject"}'
    seed child '{"type":"Document","path":"/data/mail.eml","dirname":"/data","title":"attach.xls","extractionLevel":1,"parentDocument":"root"}'
    entry file /data/mail.eml /data/mail-clean.eml > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field root path)" "/data/mail-clean.eml"
    assert_equal "$(field child path)" "/data/mail-clean.eml"
    assert_equal "$(field child title)" "attach.xls"
}

@test "renames a document whose indexed path holds a replacement character" {
    # what Java stored after decoding a non-UTF-8 filename
    seed lossy "$(jq -nc '{type:"Document", path:"/data/caf�.pdf", dirname:"/data"}')"
    # what pystou recorded: the raw byte
    entry file "$(printf '/data/caf\xe9.pdf')" /data/cafe.pdf utf8 > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field lossy path)" "/data/cafe.pdf"
}

@test "renames a path containing a quote and a tab" {
    seed weird "$(jq -nc '{type:"Document", path:"/data/we\"ird\tname.pdf", dirname:"/data"}')"
    entry file "$(printf '/data/we"ird\tname.pdf')" /data/weird-name.pdf control,punct > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field weird path)" "/data/weird-name.pdf"
}

@test "renames a path ending in a newline" {
    seed nl "$(jq -nc '{type:"Document", path:"/data/trailing\n", dirname:"/data"}')"

    # $(...) strips trailing newlines, so the same printf x guard the production
    # decode() uses is needed here or this test silently checks nothing
    local nl_path
    nl_path=$(printf '/data/trailing\n'; printf x)
    nl_path=${nl_path%x}

    entry file "$nl_path" /data/trailing control > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    # compared as base64: field() captures through $(...), which strips a trailing
    # newline and would make this assertion pass against an unrenamed document
    local got want
    got=$(curl -s "$ELASTICSEARCH_URL/$TEST_INDEX/_doc/nl" | jq -r '._source.path | @base64')
    want=$(printf %s '/data/trailing' | base64 -w0)
    assert_equal "$got" "$want"
}

@test "spans more than one batch" {
    for i in 1 2 3 4; do
      seed "b$i" "$(jq -nc --arg p "/data/b$i.pdf" '{type:"Document", path:$p, dirname:"/data"}')"
    done
    {
      entry file /data/b1.pdf /data/c1.pdf
      entry file /data/b2.pdf /data/c2.pdf
      entry file /data/b3.pdf /data/c3.pdf
      entry file /data/b4.pdf /data/c4.pdf
    } > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --batch-size 2
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field b1 path)" "/data/c1.pdf"
    assert_equal "$(field b4 path)" "/data/c4.pdf"
}

@test "is idempotent when run twice" {
    seed doc '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    assert_success
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field doc path)" "/data/clean.pdf"
}

@test "does not rename a document whose path only shares a prefix" {
    seed exact  '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    seed longer '{"type":"Document","path":"/data/plain.pdf.bak","dirname":"/data"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field exact path)" "/data/clean.pdf"
    assert_equal "$(field longer path)" "/data/plain.pdf.bak"
}

@test "accepts --batch-size with leading zeros" {
    for i in 1 2 3 4; do
      seed "z$i" "$(jq -nc --arg p "/data/z$i.pdf" '{type:"Document", path:$p, dirname:"/data"}')"
    done
    {
      entry file /data/z1.pdf /data/y1.pdf
      entry file /data/z2.pdf /data/y2.pdf
      entry file /data/z3.pdf /data/y3.pdf
      entry file /data/z4.pdf /data/y4.pdf
    } > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --batch-size 008
    assert_success
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field z1 path)" "/data/y1.pdf"
    assert_equal "$(field z4 path)" "/data/y4.pdf"
}

@test "renames a directory, rewriting path and dirname" {
    seed inside '{"type":"Document","path":"/data/old/x.pdf","dirname":"/data/old"}'
    entry dir /data/old /data/new > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field inside path)" "/data/new/x.pdf"
    assert_equal "$(field inside dirname)" "/data/new"
}

@test "applies nested directory renames deepest-first regardless of manifest order" {
    seed deep '{"type":"Document","path":"/data/a/b/x.pdf","dirname":"/data/a/b"}'
    # shallowest first, the opposite of the order it must be applied in
    {
      entry dir /data/a   /data/z
      entry dir /data/a/b /data/a/c
    } > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field deep path)" "/data/z/c/x.pdf"
    assert_equal "$(field deep dirname)" "/data/z/c"
}

@test "applies file renames before directory renames" {
    seed both '{"type":"Document","path":"/data/old/a.pdf","dirname":"/data/old"}'
    # manifest order is bottom-up: the file entry precedes its containing dir
    {
      entry file /data/old/a.pdf /data/old/b.pdf
      entry dir  /data/old       /data/new
    } > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field both path)" "/data/new/b.pdf"
    assert_equal "$(field both dirname)" "/data/new"
}

@test "a directory rename moves Duplicate documents beneath it" {
    seed dup '{"type":"Duplicate","path":"/data/old/x.pdf","documentId":"gone"}'
    entry dir /data/old /data/new > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field dup path)" "/data/new/x.pdf"
}

@test "a directory rename does not touch a sibling sharing a name prefix" {
    seed inside  '{"type":"Document","path":"/data/old/x.pdf","dirname":"/data/old"}'
    seed sibling '{"type":"Document","path":"/data/oldish/y.pdf","dirname":"/data/oldish"}'
    entry dir /data/old /data/new > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field inside path)" "/data/new/x.pdf"
    assert_equal "$(field sibling path)" "/data/oldish/y.pdf"
}

@test "a directory rename is idempotent when run twice" {
    seed inside '{"type":"Document","path":"/data/old/x.pdf","dirname":"/data/old"}'
    entry dir /data/old /data/new > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    assert_success
    curl -sXPOST "$ELASTICSEARCH_URL/$TEST_INDEX/_refresh" > /dev/null

    assert_equal "$(field inside path)" "/data/new/x.pdf"
    assert_equal "$(field inside dirname)" "/data/new"
}

@test "a dry run counts documents matching the old paths" {
    seed present '{"type":"Document","path":"/data/here.pdf","dirname":"/data"}'
    {
      entry file /data/here.pdf   /data/here-clean.pdf   nfc
      entry file /data/absent.pdf /data/absent-clean.pdf nfc
    } > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    # nfc: 2 entries, 1 matched, 1 document, 1 missing
    assert_line --regexp 'nfc +2 +1 +1 +1'
}

@test "a dry run counts every embedded document sharing a path" {
    seed root  '{"type":"Document","path":"/data/mail.eml","dirname":"/data"}'
    seed child '{"type":"Document","path":"/data/mail.eml","dirname":"/data","extractionLevel":1}'
    entry file /data/mail.eml /data/mail-clean.eml nfc > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    # 1 entry, 1 matched, 2 documents, 0 missing
    assert_line --regexp 'nfc +1 +1 +2 +0'
}

@test "a dry run separates a utf8 bucket with no documents from a matching nfc bucket" {
    seed present '{"type":"Document","path":"/data/here.pdf","dirname":"/data"}'
    {
      entry file /data/here.pdf                    /data/here-clean.pdf nfc
      entry file "$(printf '/data/gone\xe9.pdf')"   /data/gone.pdf       utf8
    } > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_line --regexp 'nfc +1 +1 +1 +0'
    assert_line --regexp 'utf8 +1 +0 +0 +1'
}

@test "a dry run lists the entries that match nothing" {
    entry file /data/absent.pdf /data/absent-clean.pdf > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_output --partial "/data/absent.pdf"
}

@test "a dry run counts documents under a renamed directory" {
    seed a '{"type":"Document","path":"/data/old/a.pdf","dirname":"/data/old"}'
    seed b '{"type":"Document","path":"/data/old/b.pdf","dirname":"/data/old"}'
    entry dir /data/old /data/new punct > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_line --regexp 'punct +1 +1 +2 +0'
}

@test "verify succeeds after a successful rename" {
    seed doc '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_success
}

@test "verify fails when the rename never happened" {
    bats_require_minimum_version 1.5.0

    seed doc '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_output --partial "Old path still has 1 documents: /data/plain.pdf"
}

@test "verify fails when an old path still has documents" {
    bats_require_minimum_version 1.5.0

    # both paths present: the new one exists but the old one was never cleared
    seed old '{"type":"Document","path":"/data/plain.pdf","dirname":"/data"}'
    seed new '{"type":"Document","path":"/data/clean.pdf","dirname":"/data"}'
    entry file /data/plain.pdf /data/clean.pdf > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_output --partial "/data/plain.pdf"
}

@test "verify accepts a directory rename" {
    seed inside '{"type":"Document","path":"/data/old/x.pdf","dirname":"/data/old"}'
    entry dir /data/old /data/new > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_success
}

@test "attributes per-rule counts to the right directory entry" {
    seed b1 '{"type":"Document","path":"/data/bb/f1.pdf","dirname":"/data/bb"}'
    seed b2 '{"type":"Document","path":"/data/bb/f2.pdf","dirname":"/data/bb"}'
    seed a1 '{"type":"Document","path":"/data/aaa/g1.pdf","dirname":"/data/aaa"}'

    # shortest first, so a descending-length sort permutes the two entries
    {
      entry dir /data/bb  /data/yy  nfc
      entry dir /data/aaa /data/xxx punct
    } > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_line --regexp 'nfc +1 +1 +2 +0'
    assert_line --regexp 'punct +1 +1 +1 +0'
}

@test "rejects a --map with an empty prefix" {
    bats_require_minimum_version 1.5.0

    entry file /data/a.pdf /data/b.pdf > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --map =/data
    assert_output --partial "--map expects"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --map /mnt/nas=
    assert_output --partial "--map expects"
}

@test "reads an entry whose rules list is empty" {
    jq -nc --arg o "$(printf %s /data/a.pdf | base64 -w0)" \
           --arg n "$(printf %s /data/b.pdf | base64 -w0)" \
      '{kind:"file", old_b64:$o, new_b64:$n, rules:[], mode:"clean"}' > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_line --regexp '^none +1 +0 +0 +1'
    refute_line --regexp '^clean +1'
}

@test "aborts when the reader drops a malformed entry" {
    bats_require_minimum_version 1.5.0

    {
      entry file /data/a.pdf /data/b.pdf
      jq -nc --arg o "$(printf %s /data/c.pdf | base64 -w0)" \
             --arg n "$(printf %s /data/d.pdf | base64 -w0)" \
        '{kind:"file", old_b64:$o, new_b64:$n, rules:"nfc", mode:"clean"}'
    } > "$MANIFEST"

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_output --partial "malformed entry"
}

@test "a dry run counts a document whose path ends in a newline" {
    seed nl "$(jq -nc '{type:"Document", path:"/data/trailing\n", dirname:"/data"}')"

    # $(...) strips trailing newlines, so the same printf x guard the production
    # decode() uses is needed here or this test silently checks nothing
    local nl_path
    nl_path=$(printf '/data/trailing\n'; printf x)
    nl_path=${nl_path%x}

    entry file "$nl_path" /data/trailing control > "$MANIFEST"

    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --dry-run
    assert_success
    assert_line --regexp '^control +1 +1 +1 +0'
}

@test "reports a failed directory move when stdout is not a terminal" {
    bats_require_minimum_version 1.5.0

    seed inside '{"type":"Document","path":"/data/old/x.pdf","dirname":"/data/old"}'
    entry dir /data/old /data/new > "$MANIFEST"
    curl -sXPUT "$ELASTICSEARCH_URL/$TEST_INDEX/_settings" -H "$H_CONTENT_TYPE" \
      -d '{"index":{"blocks.write":true}}' > /dev/null

    run ! ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    assert_output --partial "Move documents failed"
}

@test "verify accepts a file rename composed with a directory rename" {
    seed both '{"type":"Document","path":"/data/old/a.pdf","dirname":"/data/old"}'
    {
      entry file /data/old/a.pdf /data/old/b.pdf
      entry dir  /data/old       /data/new
    } > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_success
}

@test "verify accepts nested directory renames" {
    seed deep '{"type":"Document","path":"/data/a/b/x.pdf","dirname":"/data/a/b"}'
    {
      entry dir /data/a   /data/z
      entry dir /data/a/b /data/a/c
    } > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_success
}

@test "verify accepts a directory entry that matches no document" {
    entry dir /data/empty /data/empty-clean > "$MANIFEST"

    ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST"
    run ./elasticsearch/document/rename.sh $TEST_INDEX "$MANIFEST" --verify
    assert_success
}
