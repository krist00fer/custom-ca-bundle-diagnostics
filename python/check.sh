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

            # Show detailed results
            echo "Results by method:"
            "$python_cmd" -c "
import sys, json
data = json.load(sys.stdin)
details = data.get('details', {})
for method in ['urllib_result', 'requests_result', 'ssl_socket_result']:
    r = details.get(method, {})
    status = 'OK' if r.get('success') else 'FAIL'
    print(f'  {r.get(\"method\", method)}: {status}')
" <<< "$result"
            return 0
        else
            echo "Status: FAILED"
            echo "Error Type: $error_type"
            echo "Error: $error_message"
            echo ""

            # Show fix suggestions
            local ca_bundle
            ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

            echo "Suggested fix:"
            if [[ -n "$ca_bundle" ]]; then
                echo "  export SSL_CERT_FILE=\"$ca_bundle\""
                echo "  export REQUESTS_CA_BUNDLE=\"$ca_bundle\""
            else
                echo "  # No system CA bundle found"
                echo "  # Obtain your corporate CA certificate and set:"
                echo "  export SSL_CERT_FILE=/path/to/ca-bundle.crt"
                echo "  export REQUESTS_CA_BUNDLE=/path/to/ca-bundle.crt"
            fi
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
