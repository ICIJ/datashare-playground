# Get the directory of this script
_cli_lib_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $_cli_lib_dir/colors.sh
source $_cli_lib_dir/format.sh
source $_cli_lib_dir/logging.sh
source $_cli_lib_dir/prompt.sh
source $_cli_lib_dir/table.sh
source $_cli_lib_dir/progress.sh

check_usage() {
  # Get the number of arguments passed to the main program
  local main_args=${#BASH_ARGV[@]}

  # Check if the number of arguments is less than the expected number
  if [[ $main_args -lt $1 ]]; then
    log_error "Usage: $0 $2"
    exit 1
  fi
}

check_elasticsearch_url() {
  # Check if the ELASTICSEARCH_URL environment variable is not defined
  if [[ -z "${ELASTICSEARCH_URL}" ]]; then
    log_error "ELASTICSEARCH_URL is not defined. You can use a .env file."
    exit 1
  fi
}

check_redis_url() {
  # Check if the REDIS_URL environment variable is not defined
  if [[ -z "${REDIS_URL}" ]]; then
    log_error "REDIS_URL is not defined. You can use a .env file."
    exit 1
  fi
}

check_bins() {
  # Define the required dependencies as an array
  local dependencies=("curl" "jq" "watch")

  # Iterate over each dependency and check if it is installed
  for dependency in "${dependencies[@]}"; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      log_error "$dependency is not installed. Please install it before running this script."
      exit 1
    fi
  done
}

check_inotifywait() {
  # Check if inotifywait is installed through inotify-tools
  if ! command -v "inotifywait" >/dev/null 2>&1; then
    log_error "inotify-tools is not installed. Please install it before running this script."
    exit 1
  fi
}

check_redis_cli() {
  # Check if redis-cli is installed through inotify-tools
  if ! command -v "redis-cli" >/dev/null 2>&1; then
    log_error "redis-tools is not installed. Please install it before running this script."
    exit 1
  fi
}

check_rsync() {
  # Check if rsync is installed
  if ! command -v "rsync" >/dev/null 2>&1; then
    log_error "rsync is not installed. Please install it before running this script."
    exit 1
  fi
}

check_env() {
  # Get the directory of the script
  local script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
  # Calculate the path to the .env file based on the script directory
  local default_envpath=${script_dir%%/}/../.env
  # Then get the env from argument or use the default
  local envpath=${1:-$default_envpath}
  # Check if the .env file exists and load its contents
  if [[ -f $envpath ]]; then
    source $envpath
  fi
}
