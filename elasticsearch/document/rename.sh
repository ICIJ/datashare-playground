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
      batch_size=$2
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

log_title "Rename Documents: $index"

log_kv "Manifest" "$manifest"
log_kv "Entries" "$n (${#file_old[@]} file, ${#dir_old[@]} dir)"
log_kv "Skipped" "$skipped lines without a kind"
if [[ -n $host_prefix ]]; then
  log_kv "Mapping" "$host_prefix -> $index_prefix"
fi

# Report grouped by the rules that fired
declare -A rules_entries
for r in "${entry_rules[@]}"; do
  rules_entries[$r]=$(( ${rules_entries[$r]:-0} + 1 ))
done

echo
table_header "RULES:30" "ENTRIES:10"
for r in "${!rules_entries[@]}"; do
  table_row "$r" "${rules_entries[$r]}" -- 30 10
done

echo
log_kv "Modes seen" "$(printf '%s ' "${!modes_seen[@]}")"

if [[ $dry_run == true ]]; then
  exit 0
fi
