#!/usr/bin/env bash
# config.sh - Configuration and defaults for the SSL diagnostics tool

set -euo pipefail

# Get the root directory of the project
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Go up one level from runner/
    echo "$(cd "$script_dir/.." && pwd)"
}

# Project paths
PROJECT_ROOT="$(get_project_root)"
COMMON_DIR="${PROJECT_ROOT}/common"
RUNNER_DIR="${PROJECT_ROOT}/runner"
OUTPUT_DIR="${PROJECT_ROOT}/output"
CURL_DIR="${PROJECT_ROOT}/curl"
WGET_DIR="${PROJECT_ROOT}/wget"
PYTHON_DIR="${PROJECT_ROOT}/python"
DOTNET_DIR="${PROJECT_ROOT}/dotnet"
DOCKER_DIR="${PROJECT_ROOT}/docker"

# Default URL to test if none specified
# Google is highly available and uses standard SSL certificates
DEFAULT_URL="https://www.google.com"

# Alternative default URLs (for fallback or testing)
FALLBACK_URLS=(
    "https://www.cloudflare.com"
    "https://www.microsoft.com"
    "https://github.com"
)

# Test URLs for specific SSL scenarios (from badssl.com)
TEST_URL_SELF_SIGNED="https://self-signed.badssl.com/"
TEST_URL_EXPIRED="https://expired.badssl.com/"
TEST_URL_WRONG_HOST="https://wrong.host.badssl.com/"
TEST_URL_UNTRUSTED_ROOT="https://untrusted-root.badssl.com/"

# Connection timeout in seconds
TIMEOUT_SECONDS=10

# DNS timeout (some tools support separate DNS timeout)
DNS_TIMEOUT_SECONDS=5

# Maximum time for entire operation
MAX_TIME_SECONDS=30

# Verbosity level (0=quiet, 1=normal, 2=verbose, 3=debug)
VERBOSE=1

# Whether to output JSON (vs human-readable)
JSON_OUTPUT=false

# Colors for terminal output (will be disabled if not a tty)
if [[ -t 1 ]]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_BOLD='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_CYAN=''
    COLOR_BOLD=''
    COLOR_RESET=''
fi

# Supported tools for this version
SUPPORTED_TOOLS=("curl" "wget" "python" "dotnet")

# Python versions to check (in order of preference)
PYTHON_VERSIONS=("3.13" "3.12" "3.11" "3.10" "3.9" "3.8")

# .NET versions to check (in order of preference)
DOTNET_VERSIONS=("9" "8" "7" "6")

# Get environment variable names by tool
# Usage: get_env_vars_for_tool "curl"
get_env_vars_for_tool() {
    local tool="$1"
    case "$tool" in
        curl)
            echo "CURL_CA_BUNDLE"
            ;;
        wget)
            echo "SSL_CERT_FILE"
            ;;
        python_requests|python-requests)
            echo "REQUESTS_CA_BUNDLE CURL_CA_BUNDLE"
            ;;
        python_ssl|python-ssl|python)
            echo "SSL_CERT_FILE SSL_CERT_DIR"
            ;;
        python_pip|pip)
            echo "PIP_CERT"
            ;;
        dotnet)
            echo "SSL_CERT_FILE SSL_CERT_DIR"
            ;;
        openssl)
            echo "SSL_CERT_FILE SSL_CERT_DIR"
            ;;
        git)
            echo "GIT_SSL_CAINFO GIT_SSL_CAPATH"
            ;;
        node|nodejs|npm)
            echo "NODE_EXTRA_CA_CERTS"
            ;;
        *)
            echo "SSL_CERT_FILE"
            ;;
    esac
}

# Docker image names
DOCKER_IMAGE_PREFIX="ssl-check"

# Parse command line arguments
# Usage: parse_args "$@"
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--url)
                TARGET_URL="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=2
                shift
                ;;
            -q|--quiet)
                VERBOSE=0
                shift
                ;;
            --debug)
                VERBOSE=3
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                show_help
                exit 1
                ;;
            *)
                # Assume it's the URL if it starts with http
                if [[ "$1" == http* ]]; then
                    TARGET_URL="$1"
                fi
                shift
                ;;
        esac
    done

    # Set default URL if not specified
    TARGET_URL="${TARGET_URL:-$DEFAULT_URL}"
}

# Show help message
show_help() {
    cat <<EOF
HTTPS/SSL Connectivity Diagnostics Tool

Usage: check [OPTIONS] [URL]

Options:
  -u, --url URL      Target URL to test (default: $DEFAULT_URL)
  -t, --timeout SEC  Connection timeout in seconds (default: $TIMEOUT_SECONDS)
  -v, --verbose      Enable verbose output
  -q, --quiet        Suppress non-essential output
  --debug            Enable debug output
  --json             Output results as JSON
  -h, --help         Show this help message

Examples:
  check                                    # Test default URL
  check https://internal.company.com       # Test specific URL
  check --json https://example.com         # Output JSON results
  check -t 30 https://slow-server.com      # Custom timeout

EOF
}

# Validate URL format
# Usage: validate_url "https://example.com"
validate_url() {
    local url="$1"

    # Check if URL starts with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        # Try to auto-prepend https://
        url="https://${url}"
    fi

    # Basic URL validation
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})(:[0-9]+)?(/.*)?$ ]]; then
        return 1
    fi

    echo "$url"
}

# Extract host and port from URL
# Usage: get_host_port "https://example.com:8443/path"
get_host_port() {
    local url="$1"
    local host port

    # Remove protocol
    url="${url#*://}"
    # Remove path
    url="${url%%/*}"

    # Extract port if present
    if [[ "$url" == *:* ]]; then
        host="${url%:*}"
        port="${url##*:}"
    else
        host="$url"
        # Default port based on protocol
        if [[ "$1" == https://* ]]; then
            port="443"
        else
            port="80"
        fi
    fi

    echo "$host:$port"
}

# Create output directory if it doesn't exist
ensure_output_dir() {
    mkdir -p "$OUTPUT_DIR"
}

# Get timestamp for filenames
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Log message based on verbosity
# Usage: log_info "message"
log_info() {
    if [[ "$VERBOSE" -ge 1 ]]; then
        echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $1"
    fi
}

log_success() {
    if [[ "$VERBOSE" -ge 1 ]]; then
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $1"
    fi
}

log_warning() {
    if [[ "$VERBOSE" -ge 1 ]]; then
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
    fi
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" -ge 3 ]]; then
        echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $1"
    fi
}

# If run directly, show configuration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "SSL Diagnostics Tool Configuration"
    echo "==================================="
    echo ""
    echo "Paths:"
    echo "  Project Root:  $PROJECT_ROOT"
    echo "  Common Dir:    $COMMON_DIR"
    echo "  Output Dir:    $OUTPUT_DIR"
    echo ""
    echo "Defaults:"
    echo "  Default URL:   $DEFAULT_URL"
    echo "  Timeout:       ${TIMEOUT_SECONDS}s"
    echo "  Verbosity:     $VERBOSE"
    echo ""
    echo "Supported Tools: ${SUPPORTED_TOOLS[*]}"
    echo "Python Versions: ${PYTHON_VERSIONS[*]}"
    echo ".NET Versions:   ${DOTNET_VERSIONS[*]}"
fi
