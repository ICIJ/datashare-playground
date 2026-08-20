#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 2 '<index> <manifest> [--map <host>=<index>] [--dry-run] [--verify] [--batch-size <n>]'
check_bins
check_env
check_elasticsearch_url

index=$1
manifest=$2
shift 2

host_prefix=
index_prefix=
dry_run=false
verify=false
batch_size=1000

while [[ $# -gt 0 ]]; do
  case $1 in
    --map)
      if [[ ${2:-} != *=* ]]; then
        log_error "--map expects <host_prefix>=<index_prefix>"
        exit 1
      fi
      host_prefix=${2%%=*}
      index_prefix=${2#*=}
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --verify)
      verify=true
      shift
      ;;
    --batch-size)
      if [[ ${2:-} != +([0-9]) || ${2:-0} -eq 0 ]]; then
        log_error "--batch-size expects a positive integer"
        exit 1
      fi
      batch_size=$((10#$2))
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ ! -f $manifest ]]; then
  log_error "Manifest not found: $manifest"
  exit 1
fi

if [[ $dry_run == true && $verify == true ]]; then
  log_error "--dry-run and --verify are mutually exclusive"
  exit 1
fi

# base64 -d via a global, because $(...) strips a filename's trailing newline
decode() {
  REPLY=$(printf %s "$1" | base64 -d; printf x)
  REPLY=${REPLY%x}
}

file_old=(); file_new=()
dir_old=(); dir_new=()
entry_rules=(); entry_kind=()
declare -A seen_canon
declare -A modes_seen
n=0

# @base64d is deliberate and correct only here: its lossy UTF-8 decoding reproduces
# exactly what Java did to the filename, and @base64 re-encodes so bash only ever
# handles ASCII. Every path below this loop is canonical UTF-8.
while IFS=$'\t' read -r kind old_b64 new_b64 rules mode; do
  n=$((n + 1))

  case $kind in
    file|dir) ;;
    *)
      log_error "Entry $n has unknown kind '$kind' (expected 'file' or 'dir')"
      exit 1
      ;;
  esac

  if [[ -v seen_canon[$old_b64] ]]; then
    log_error "Entry $n collides with entry ${seen_canon[$old_b64]}: both old paths canonicalise to the same value"
    exit 1
  fi
  seen_canon[$old_b64]=$n

  decode "$old_b64"; old=$REPLY
  decode "$new_b64"; new=$REPLY

  if [[ -n $host_prefix ]]; then
    if [[ $old != "$host_prefix"* ]]; then
      log_error "Entry $n old path is not under $host_prefix: $old"
      exit 1
    fi
    if [[ $new != "$host_prefix"* ]]; then
      log_error "Entry $n new path is not under $host_prefix: $new"
      exit 1
    fi
    old=$index_prefix${old#"$host_prefix"}
    new=$index_prefix${new#"$host_prefix"}
  fi

  entry_kind+=("$kind")
  entry_rules+=("${rules:-none}")
  modes_seen[${mode:-none}]=1

  if [[ $kind == file ]]; then
    file_old+=("$old")
    file_new+=("$new")
  else
    dir_old+=("$old")
    dir_new+=("$new")
  fi
done < <(jq -r 'select(.kind) | [
           .kind,
           (.old_b64 | @base64d | @base64),
           (.new_b64 | @base64d | @base64),
           (.rules // [] | join(",")),
           (.mode // "")
         ] | @tsv' "$manifest")

total_objects=$(jq -rs 'length' "$manifest")
skipped=$((total_objects - n))

# A new path that is also another entry's old path would double-apply on replay,
# which is what makes a full re-run safe. Exact equality only: a file entry
# legitimately sits under a dir entry's old path.
declare -A old_set
for p in "${file_old[@]}" "${dir_old[@]}"; do
  old_set[$p]=1
done
for p in "${file_new[@]}" "${dir_new[@]}"; do
  if [[ -v old_set[$p] ]]; then
    log_error "Rename chain: '$p' is both a new path and another entry's old path"
    exit 1
  fi
done

# Deepest-first, because a descendant path is always longer than its ancestor.
# Only length/index pairs go through sort, never a path, so a path containing a
# newline cannot corrupt the ordering.
if (( ${#dir_old[@]} > 1 )); then
  sorted_old=(); sorted_new=()
  while IFS=$'\t' read -r _ i; do
    sorted_old+=("${dir_old[i]}")
    sorted_new+=("${dir_new[i]}")
  done < <(
    for i in "${!dir_old[@]}"; do
      printf '%s\t%s\n' "${#dir_old[i]}" "$i"
    done | sort -rn -k1,1
  )
  dir_old=("${sorted_old[@]}")
  dir_new=("${sorted_new[@]}")
fi

# Per-path document counts in one request per batch. A requested path absent from
# the buckets matched nothing. Populates the COUNT_OF associative array.
declare -A COUNT_OF

count_file_paths() {
  local body buckets
  while (( $# > 0 )); do
    local chunk=("${@:1:batch_size}")
    shift $(( ${#chunk[@]} ))

    body=$(jq -nc --args '{
      size: 0,
      query: { terms: { path: $ARGS.positional } },
      aggs: { by_path: { terms: { field: "path", size: ($ARGS.positional | length) } } }
    }' "${chunk[@]}")

    buckets=$(curl -s "$ELASTICSEARCH_URL/$index/_search" \
      -H 'Content-Type: application/json' -d "$body" \
      | jq -r '.aggregations.by_path.buckets[] | "\(.doc_count)\t\(.key)"')

    while IFS=$'\t' read -r c k; do
      [[ -n $k ]] && COUNT_OF[$k]=$c
    done <<< "$buckets"
  done
  # An empty last batch leaves $k unset on the final read, so the loop's own
  # exit status would be false; under bash -e that aborts the caller.
  return 0
}

# Document counts beneath each directory prefix. Filters are named by ordinal
# because naming them after the paths breaks on the first path containing a dot.
count_dir_prefixes() {
  local body counts i=0
  local dirs=("$@")
  while (( i < ${#dirs[@]} )); do
    local chunk=("${dirs[@]:i:200}")

    body=$(jq -nc --args '{
      size: 0,
      aggs: { dirs: { filters: { filters: (
        [ $ARGS.positional | to_entries[]
          | { key: (.key | tostring), value: { prefix: { path: (.value + "/") } } } ]
        | from_entries
      ) } } }
    }' "${chunk[@]}")

    counts=$(curl -s "$ELASTICSEARCH_URL/$index/_search" \
      -H 'Content-Type: application/json' -d "$body" \
      | jq -r '.aggregations.dirs.buckets | to_entries[] | "\(.key)\t\(.value.doc_count)"')

    while IFS=$'\t' read -r ord c; do
      [[ -n $ord ]] && COUNT_OF[${chunk[ord]}]=$c
    done <<< "$counts"

    i=$(( i + 200 ))
  done
}

# Fill COUNT_OF for one side of the rename. $1 is 'old' or 'new'.
count_side() {
  COUNT_OF=()
  if [[ $1 == old ]]; then
    (( ${#file_old[@]} > 0 )) && count_file_paths "${file_old[@]}"
    (( ${#dir_old[@]} > 0 ))  && count_dir_prefixes "${dir_old[@]}"
  else
    (( ${#file_new[@]} > 0 )) && count_file_paths "${file_new[@]}"
    (( ${#dir_new[@]} > 0 ))  && count_dir_prefixes "${dir_new[@]}"
  fi
  return 0
}

# The path an entry is keyed on, per side. Entries are stored split by kind, so
# walk them in the same order the reader appended them.
path_of_entry() {
  local i=$1 side=$2 f=0 d=0 j
  for (( j = 0; j < i; j++ )); do
    if [[ ${entry_kind[j]} == file ]]; then f=$(( f + 1 )); else d=$(( d + 1 )); fi
  done
  if [[ ${entry_kind[i]} == file ]]; then
    [[ $side == old ]] && REPLY=${file_old[f]} || REPLY=${file_new[f]}
  else
    [[ $side == old ]] && REPLY=${dir_old[d]} || REPLY=${dir_new[d]}
  fi
}

log_title "Rename Documents: $index"

log_kv "Manifest" "$manifest"
log_kv "Entries" "$n (${#file_old[@]} file, ${#dir_old[@]} dir)"
log_kv "Skipped" "$skipped lines without a kind"
if [[ -n $host_prefix ]]; then
  log_kv "Mapping" "$host_prefix -> $index_prefix"
fi

count_side old

declare -A rules_entries rules_matched rules_docs
missing=()

for i in "${!entry_rules[@]}"; do
  r=${entry_rules[i]}
  path_of_entry "$i" old
  c=${COUNT_OF[$REPLY]:-0}

  rules_entries[$r]=$(( ${rules_entries[$r]:-0} + 1 ))
  rules_docs[$r]=$(( ${rules_docs[$r]:-0} + c ))
  if (( c > 0 )); then
    rules_matched[$r]=$(( ${rules_matched[$r]:-0} + 1 ))
  else
    missing+=("$REPLY")
  fi
done

echo
table_header "RULES:30" "ENTRIES:10" "MATCHED:10" "DOCS:10" "MISSING:10"
for r in "${!rules_entries[@]}"; do
  table_row "$r" \
    "${rules_entries[$r]}" \
    "${rules_matched[$r]:-0}" \
    "${rules_docs[$r]:-0}" \
    "$(( ${rules_entries[$r]} - ${rules_matched[$r]:-0} ))" \
    -- 30 10 10 10 10
done

if (( ${#missing[@]} > 0 )); then
  echo
  log_warn "${#missing[@]} entries match no document:"
  for p in "${missing[@]:0:20}"; do
    log_info "  $p"
  done
  if (( ${#missing[@]} > 20 )); then
    log_info "  ... and $(( ${#missing[@]} - 20 )) more"
  fi
fi

echo
log_kv "Modes seen" "$(printf '%s ' "${!modes_seen[@]}")"

if [[ $dry_run == true ]]; then
  exit 0
fi

if [[ $verify == true ]]; then
  problems=0

  count_side new
  for i in "${!entry_kind[@]}"; do
    path_of_entry "$i" new
    # at least one, not exactly one: embedded documents share their container's path
    if (( ${COUNT_OF[$REPLY]:-0} < 1 )); then
      log_error "New path has no document: $REPLY"
      problems=$(( problems + 1 ))
    fi
  done

  count_side old
  for i in "${!entry_kind[@]}"; do
    path_of_entry "$i" old
    if (( ${COUNT_OF[$REPLY]:-0} > 0 )); then
      log_error "Old path still has ${COUNT_OF[$REPLY]} documents: $REPLY"
      problems=$(( problems + 1 ))
    fi
  done

  echo
  if (( problems > 0 )); then
    log_error "Verification failed with $problems problems"
    exit 1
  fi
  log_info "Verified $n entries"
  exit 0
fi

TOTAL_UPDATED=0

# Start an async _update_by_query, wait for it, then read the stored task response.
# monitor_es_task discards that response, and the failure and conflict counts are
# the only evidence that a batch actually landed.
run_update() {
  local body=$1 label=$2
  local result task_id response failures conflicts

  result=$(curl -sXPOST "$ELASTICSEARCH_URL/$index/_update_by_query?wait_for_completion=false&refresh=true" \
    -H 'Content-Type: application/json' -d "$body")
  task_id=$(printf %s "$result" | jq -r '.task')

  if [[ "$task_id" == "null" || -z "$task_id" ]]; then
    log_error "Failed to start $label"
    printf %s "$result" | jq -r '.error.reason // empty'
    exit 1
  fi

  # returns non-zero on failures, which we report ourselves with more detail
  monitor_es_task "$task_id" "$label" || true

  response=$(curl -s "$ELASTICSEARCH_URL/_tasks/$task_id" | jq -c '.response')
  failures=$(printf %s "$response" | jq -r '.failures | length')
  conflicts=$(printf %s "$response" | jq -r '.version_conflicts')

  if [[ "$failures" != "0" || "$conflicts" != "0" ]]; then
    log_error "$label: $failures failures, $conflicts version conflicts"
    printf %s "$response" | jq -r '.failures[0] // empty'
    log_error "Re-run the same command to retry. Both passes match on old paths, so a full replay is idempotent."
    exit 1
  fi

  UPDATED=$(printf %s "$response" | jq -r '.updated')
  TOTAL_UPDATED=$((TOTAL_UPDATED + UPDATED))
}

# One _update_by_query per batch. Arguments are a flat old new old new list.
update_files() {
  local body
  body=$(jq -nc --args '
    ($ARGS.positional | length) as $n
    | [ range(0; $n; 2) ] as $ix
    | {
        query: { terms: { path: [ $ix[] | $ARGS.positional[.] ] } },
        script: {
          lang: "painless",
          source: "ctx._source.path = params.map.get(ctx._source.path)",
          params: { map: ( [ $ix[] | { ($ARGS.positional[.]): $ARGS.positional[.+1] } ] | add ) }
        }
      }' "$@")
  run_update "$body" "Rename files"
}

if (( ${#file_old[@]} > 0 )); then
  echo
  batch=()
  for i in "${!file_old[@]}"; do
    batch+=("${file_old[i]}" "${file_new[i]}")
    if (( ${#batch[@]} / 2 == batch_size )); then
      update_files "${batch[@]}"
      batch=()
    fi
  done
  if (( ${#batch[@]} > 0 )); then
    update_files "${batch[@]}"
  fi
fi

if (( ${#dir_old[@]} > 0 )); then
  for i in "${!dir_old[@]}"; do
    echo
    $script_dir/move.sh "$index" "${dir_old[i]}" "${dir_new[i]}"
  done
fi

$script_dir/../index/refresh.sh "$index" > /dev/null

echo
log_info "Updated $TOTAL_UPDATED documents in the file pass"
if (( ${#dir_old[@]} > 0 )); then
  log_info "Processed ${#dir_old[@]} directories"
fi
