#!/usr/bin/env bash
# python/check.sh - Python SSL connectivity diagnostic module runner

set -euo pipefail

PYTHON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$PYTHON_SCRIPT_DIR/.." && pwd)"

# Source common utilities
source "${PROJECT_ROOT}/common/detect-os.sh"
source "${PROJECT_ROOT}/common/json-utils.sh"
source "${PROJECT_ROOT}/common/error-classify.sh"
source "${PROJECT_ROOT}/common/ca-bundle.sh"
source "${PYTHON_SCRIPT_DIR}/detect-versions.sh"

# Default timeout
TIMEOUT="${TIMEOUT:-10}"

# Determine the Python command to use
get_python_cmd() {
    local requested="${1:-}"

    if [[ -n "$requested" ]]; then
        # Use requested version/command
        if [[ -x "$requested" ]]; then
            # It's a path
            echo "$requested"
        elif command -v "$requested" >/dev/null 2>&1; then
            # It's a command name
            echo "$requested"
        elif command -v "python${requested}" >/dev/null 2>&1; then
            # Try with python prefix
            echo "python${requested}"
        else
            # Try to find via detect-versions
            local path
            path=$(get_python_path "$requested")
            if [[ -n "$path" ]]; then
                echo "$path"
            else
                echo ""
            fi
        fi
    else
        # Use default: prefer python3
        if command -v python3 >/dev/null 2>&1; then
            echo "python3"
        elif command -v python >/dev/null 2>&1; then
            echo "python"
        else
            echo ""
        fi
    fi
}

# Get Python version string
get_python_version() {
    local python_cmd="$1"

    if [[ -z "$python_cmd" ]]; then
        echo "not_installed"
        return
    fi

    "$python_cmd" --version 2>&1 | awk '{print $2}'
}

# Run Python SSL check
run_python_check() {
    local url="$1"
    local python_cmd="$2"
    local timeout="${3:-$TIMEOUT}"

    # Run the Python check script
    "$python_cmd" "${PYTHON_SCRIPT_DIR}/check.py" "$url" "$timeout" 2>&1
}

# Generate fix suggestions for Python SSL errors
generate_python_fix() {
    local error_type="$1"
    local error_message="$2"
    local ca_bundle

    ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

    if [[ "$error_type" != "ssl_error" ]]; then
        echo "null"
        return
    fi

    local description="Set SSL environment variables to point to your CA certificate bundle"
    local env_vars="{}"
    local commands="[]"

    if [[ -n "$ca_bundle" ]]; then
        env_vars=$(cat <<EOF
{
  "SSL_CERT_FILE": "$ca_bundle",
  "REQUESTS_CA_BUNDLE": "$ca_bundle",
  "CURL_CA_BUNDLE": "$ca_bundle"
}
EOF
)
        commands=$(cat <<EOF
[
  "# For Python's ssl module and urllib:",
  "export SSL_CERT_FILE=\"$ca_bundle\"",
  "",
  "# For the requests library:",
  "export REQUESTS_CA_BUNDLE=\"$ca_bundle\"",
  "",
  "# For pip:",
  "export PIP_CERT=\"$ca_bundle\""
]
EOF
)
    else
        description="$description. No system CA bundle found - you may need to obtain certificates from your IT department."
        env_vars=$(cat <<EOF
{
  "SSL_CERT_FILE": "/path/to/ca-bundle.crt",
  "REQUESTS_CA_BUNDLE": "/path/to/ca-bundle.crt"
}
EOF
)
        commands=$(cat <<EOF
[
  "# First, obtain your corporate CA certificate bundle",
  "# Then set these environment variables:",
  "export SSL_CERT_FILE=/path/to/ca-bundle.crt",
  "export REQUESTS_CA_BUNDLE=/path/to/ca-bundle.crt"
]
EOF
)
    fi

    create_fix_json "$description" "$env_vars" "$commands"
}

# Main check function
check_python() {
    local url="${1:-https://www.google.com}"
    local requested_version="${2:-}"

    # Get Python command
    local python_cmd
    python_cmd=$(get_python_cmd "$requested_version")

    local platform_json
    platform_json=$(get_platform_json)

    # Check if Python is available
    if [[ -z "$python_cmd" ]]; then
        local version_str="${requested_version:-Python}"
        create_result_json \
            "python" \
            "not_installed" \
            "$url" \
            "false" \
            "runtime_missing" \
            "$version_str is not installed" \
            "127" \
            "0" \
            "$platform_json" \
            "$(create_fix_json "Install Python using your package manager or pyenv" "{}" "[\"# On macOS:\",\"brew install python\",\"# Or use pyenv:\",\"curl https://pyenv.run | bash\",\"pyenv install 3.12\"]")"
        return
    fi

    local version
    version=$(get_python_version "$python_cmd")

    # Run the Python check (capture stdout and stderr separately)
    local result
    result=$(run_python_check "$url" "$python_cmd" "$TIMEOUT" 2>/dev/null) || true

    # If result is empty, try again capturing stderr for error info
    if [[ -z "$result" ]]; then
        result=$(run_python_check "$url" "$python_cmd" "$TIMEOUT" 2>&1) || true
    fi

    # Extract JSON from output (in case there are warnings before/after)
    local json_result
    json_result=$(echo "$result" | grep -E '^\{' | head -1)
    if [[ -n "$json_result" ]] && echo "$json_result" | "$python_cmd" -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        # Found valid JSON, output it
        echo "$json_result"
    elif echo "$result" | "$python_cmd" -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        # Full result is valid JSON
        echo "$result"
    else
        # Something went wrong, create error result
        local error_type
        error_type=$(classify_error "$result")

        create_result_json \
            "python" \
            "$version" \
            "$url" \
            "false" \
            "$error_type" \
            "Python check failed: $result" \
            "1" \
            "0" \
            "$platform_json" \
            "$(generate_python_fix "$error_type" "$result")"
    fi
}

# Human-readable output mode
check_python_human() {
    local url="${1:-https://www.google.com}"
    local requested_version="${2:-}"

    echo "=== Python SSL Connectivity Check ==="
    echo ""
    echo "URL: $url"

    # Get Python command
    local python_cmd
    python_cmd=$(get_python_cmd "$requested_version")

    if [[ -z "$python_cmd" ]]; then
        echo "Status: FAILED"
        echo "Error: Python${requested_version:+ $requested_version} is not installed"
        echo ""
        echo "To install Python:"
        echo "  macOS:   brew install python"
        echo "  Ubuntu:  sudo apt-get install python3"
        echo "  pyenv:   pyenv install 3.12"
        return 1
    fi

    local version
    version=$(get_python_version "$python_cmd")

    echo "Python: $version ($python_cmd)"
    echo ""

    # Show SSL configuration
    echo "SSL Configuration:"
    "$python_cmd" -c "
import ssl
paths = ssl.get_default_verify_paths()
print(f'  OpenSSL: {ssl.OPENSSL_VERSION}')
print(f'  CA File: {paths.cafile or \"not set\"}')
print(f'  CA Path: {paths.capath or \"not set\"}')
"
    echo ""

    echo "Testing connection..."
    echo ""

    # Run the check
    local result
    result=$(run_python_check "$url" "$python_cmd" "$TIMEOUT" 2>&1) || true

    # Parse and display result
    local success error_type error_message

    if echo "$result" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        success=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))")
        error_type=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error_type', 'unknown'))")
        error_message=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error_message', ''))")

        if [[ "$success" == "True" ]]; then
            echo "Status: SUCCESS"
            echo ""

            # Show environment variables status for awareness
            echo "Environment Variables:"
            "$python_cmd" -c "
import os

GREEN = '\033[0;32m'
YELLOW = '\033[0;33m'
RESET = '\033[0m'

env_vars = {
    'SSL_CERT_FILE': os.environ.get('SSL_CERT_FILE'),
    'SSL_CERT_DIR': os.environ.get('SSL_CERT_DIR'),
    'REQUESTS_CA_BUNDLE': os.environ.get('REQUESTS_CA_BUNDLE'),
    'CURL_CA_BUNDLE': os.environ.get('CURL_CA_BUNDLE')
}

for var, val in env_vars.items():
    if val:
        if os.path.exists(val):
            print(f'  {var}: {GREEN}Set{RESET} ({val})')
        else:
            print(f'  {var}: {YELLOW}Set but invalid{RESET} ({val})')
    else:
        print(f'  {var}: Not set (using system defaults)')
"
            echo ""

            # Show detailed results
            echo "Results by method:"
            "$python_cmd" -c "
import sys, json

# Color codes
GREEN = '\033[0;32m'
RED = '\033[0;31m'
RESET = '\033[0m'

data = json.load(sys.stdin)
details = data.get('details', {})
for method in ['urllib_result', 'requests_result', 'ssl_socket_result']:
    r = details.get(method, {})
    if r.get('success'):
        status = f'{GREEN}OK{RESET}'
    else:
        status = f'{RED}FAIL{RESET}'
    print(f'  {r.get(\"method\", method)}: {status}')
" <<< "$result"
            return 0
        else
            echo "Status: FAILED"
            echo ""
            
            # Show detailed results with error information and colors
            echo "Results by method:"
            "$python_cmd" -c "
import sys, json
import os

# Color codes
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[0;33m'
CYAN = '\033[0;36m'
BOLD = '\033[1m'
RESET = '\033[0m'

data = json.load(sys.stdin)
details = data.get('details', {})
fixes = data.get('fixes', {})
ssl_info = details.get('ssl_info', {})

method_names = {
    'urllib': 'urllib (Python standard library)',
    'requests': 'requests (third-party HTTP library)',
    'ssl_socket': 'ssl_socket (low-level SSL module)'
}

# Check environment variables
env_vars_checked = {
    'SSL_CERT_FILE': os.environ.get('SSL_CERT_FILE'),
    'SSL_CERT_DIR': os.environ.get('SSL_CERT_DIR'),
    'REQUESTS_CA_BUNDLE': os.environ.get('REQUESTS_CA_BUNDLE'),
    'CURL_CA_BUNDLE': os.environ.get('CURL_CA_BUNDLE')
}

for method_key in ['urllib_result', 'requests_result', 'ssl_socket_result']:
    r = details.get(method_key, {})
    method = r.get('method', method_key.replace('_result', ''))
    
    if r.get('success'):
        status = f'{GREEN}OK{RESET}'
    else:
        status = f'{RED}FAIL{RESET}'
    
    print(f'  {method}: {status}')
    
    # If failed, show error details
    if not r.get('success'):
        error_type = r.get('error_type', 'unknown')
        error_msg = r.get('error_message', 'No error message')
        
        # Show what this method is
        method_desc = method_names.get(method, method)
        print(f'    {BOLD}What:{RESET} {method_desc}')
        
        if error_type == 'runtime_missing':
            print(f'    {BOLD}Why:{RESET}  {error_msg}')
        elif error_type == 'ssl_error':
            print(f'    {BOLD}Why:{RESET}  {RED}SSL certificate verification failed{RESET}')
            print(f'    {BOLD}Details:{RESET} {error_msg}')
            print()
            
            # Show relevant environment variables for this method
            print(f'    {BOLD}Environment Variables Status:{RESET}')
            if method == 'requests':
                relevant_vars = ['REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE']
            else:
                relevant_vars = ['SSL_CERT_FILE', 'SSL_CERT_DIR']
            
            for var in relevant_vars:
                val = env_vars_checked.get(var)
                if val:
                    if os.path.exists(val):
                        print(f'      {var}: {GREEN}Set{RESET} ({val})')
                    else:
                        print(f'      {var}: {YELLOW}Set but path does not exist{RESET} ({val})')
                else:
                    print(f'      {var}: {RED}Not set{RESET}')
            print()
            
            # Show fix for this specific method
            if method in fixes:
                fix = fixes[method]
                print(f'    {BOLD}{CYAN}Action Required:{RESET}')
                print(f'      {fix.get(\"description\", \"\")}')
                print()
                
                env_vars = fix.get('env_vars', {})
                if env_vars:
                    print(f'      {BOLD}Set the following environment variable(s):{RESET}')
                    for var, val in env_vars.items():
                        print(f'        {CYAN}export {var}=\"{val}\"{RESET}')
        elif error_type == 'dns_error':
            print(f'    {BOLD}Why:{RESET}  {YELLOW}DNS resolution failed - network/connectivity issue{RESET}')
            print(f'    {BOLD}Details:{RESET} {error_msg}')
            print()
            print(f'    {BOLD}{CYAN}Action Required:{RESET}')
            print(f'      This is not an SSL certificate issue.')
            print(f'      Check your network connection and DNS settings.')
        elif error_type == 'timeout':
            print(f'    {BOLD}Why:{RESET}  {YELLOW}Connection timed out{RESET}')
            print(f'    {BOLD}Details:{RESET} {error_msg}')
            print()
            print(f'    {BOLD}{CYAN}Action Required:{RESET}')
            print(f'      This is not an SSL certificate issue.')
            print(f'      The server may be slow or unreachable. Try increasing timeout.')
        elif error_type == 'network_error':
            print(f'    {BOLD}Why:{RESET}  {YELLOW}Network connection error{RESET}')
            print(f'    {BOLD}Details:{RESET} {error_msg}')
            print()
            print(f'    {BOLD}{CYAN}Action Required:{RESET}')
            print(f'      Check network connectivity and firewall settings.')
        else:
            print(f'    {BOLD}Why:{RESET}  {error_msg}')
        print()
" <<< "$result"
            
            echo ""
            echo "Overall error: $error_type"
            echo "Message: $error_message"
            return 1
        fi
    else
        echo "Status: FAILED"
        echo "Error: Python check script failed"
        echo "Details: $result"
        return 1
    fi
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    url="${1:-https://www.google.com}"
    version="${2:-}"
    mode="${3:-json}"

    # Handle argument variations
    if [[ "$version" == "--human" || "$version" == "-h" || "$version" == "human" ]]; then
        mode="human"
        version=""
    fi

    if [[ "$url" == "--human" || "$url" == "-h" ]]; then
        mode="human"
        url="https://www.google.com"
    fi

    case "$mode" in
        --human|-h|human)
            check_python_human "$url" "$version"
            ;;
        --json|-j|json|*)
            check_python "$url" "$version"
            ;;
    esac
fi
