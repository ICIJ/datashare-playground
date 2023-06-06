#!/bin/bash -e

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $script_dir/../../lib/cli.sh

check_usage 1 '<queue> [<batch_size>]'
check_env
check_redis_cli
check_redis_url

redis_cli="redis-cli -u $REDIS_URL --pipe"
queue_name=$1
batch_size=${2:-100}

rpush () {
  local key_name=$1
  # Get all remaining arguments as an array of values
  shift 1
  local values=("$@")
  # Concatenates all values into a space separated list of quoted value
  local joined_values=$(printf '"%s" ' "${values[@]}")
  # Finally, use pipe to RPUSH the bash all at once
  echo "RPUSH $key_name ${joined_values}" | $redis_cli
}

if [ -t 0 ]; then
  echo "No standard input provided, the queue was unchanged."
else
  batch=()
  batch_count=0

  while IFS= read -r line; do
    batch+=("$line")
    batch_count=$((batch_count + 1))

    if ((batch_count % batch_size == 0)); then
      # Push the batch to Redis using Redis CLI
      rpush $queue_name "${batch[@]}"
      # Clear the batch
      batch=()
    fi
  done < /dev/stdin

  # Push the remaining items in the last batch, if any
  if ((batch_count % batch_size > 0)); then
    rpush $queue_name "${batch[@]}"
  fi
fi