# Logging functions
# Requires colors.sh to be sourced first

log_info() {
    echo -e "${Green}[INFO]${Color_Off} $1"
}

log_warn() {
    echo -e "${BYellow}[WARN]${Color_Off} $1"
}

log_error() {
    echo -e "${Red}[ERROR]${Color_Off} $1"
}
