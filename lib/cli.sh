check_usage() {
  # Get the number of arguments passed to the main program
  local main_args=${#BASH_ARGV[@]}
  
  # Check if the number of arguments is less than the expected number
  if [[ $main_args -lt $1 ]]; then
    echo "Usage: $0 $2"
    exit 1
  fi
}

check_elasticsearch_url() {
  # Check if the ELASTICSEARCH_URL environment variable is not defined
  if [[ -z "${ELASTICSEARCH_URL}" ]]; then
    echo "Error: ELASTICSEARCH_URL is not defined. You can use a .env file."
    exit 1
  fi
}

check_redis_url() {
  # Check if the REDIS_URL environment variable is not defined
  if [[ -z "${REDIS_URL}" ]]; then
    echo "Error: REDIS_URL is not defined. You can use a .env file."
    exit 1
  fi
}

check_bins() {
  # Define the required dependencies as an array
  local dependencies=("curl" "jq" "watch")

  # Iterate over each dependency and check if it is installed
  for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      echo "Error: $dependency is not installed. Please install it before running this script."
      exit 1
    fi
  done
}

check_inotifywait() {
  # Check if inotifywait is installed through inotify-tools
  if ! command -v "inotifywait" >/dev/null 2>&1; then
    echo "Error: inotify-tools is not installed. Please install it before running this script."
    exit 1
  fi
}

check_redis_cli() {
  # Check if redis-cli is installed through inotify-tools
  if ! command -v "redis-cli" >/dev/null 2>&1; then
    echo "Error: redis-tools is not installed. Please install it before running this script."
    exit 1
  fi
}

check_rsync() {
  # Check if rsync is installed 
  if ! command -v "rsync" >/dev/null 2>&1; then
    echo "Error: rsync is not installed. Please install it before running this script."
    exit 1
  fi
}

check_env() {
  # Get the directory of the script
  local script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

  # Calculate the path to the .env file based on the script directory
  local envpath=${script_dir%%/}/../.env

  # Check if the .env file exists and load its contents
  if [[ -f $envpath ]]; then
    source $envpath
  fi
}
