#!/usr/bin/env bash
# wget/check.sh - wget SSL connectivity diagnostic module

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common utilities
source "${PROJECT_ROOT}/common/detect-os.sh"
source "${PROJECT_ROOT}/common/json-utils.sh"
source "${PROJECT_ROOT}/common/error-classify.sh"
source "${PROJECT_ROOT}/common/ca-bundle.sh"

# Default timeout
TIMEOUT="${TIMEOUT:-10}"

# Check if wget is installed
check_wget_installed() {
    if command -v wget >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get wget version
get_wget_version() {
    if check_wget_installed; then
        wget --version 2>/dev/null | head -1 | awk '{print $3}'
    else
        echo "not_installed"
    fi
}

# Get wget SSL/TLS library info
get_wget_ssl_info() {
    if check_wget_installed; then
        wget --version 2>/dev/null | grep -i "ssl\|tls\|openssl\|gnutls" | head -1
    else
        echo "not_available"
    fi
}

# Run wget check against URL
# Returns: exit_code, output (stderr), duration_ms
run_wget_check() {
    local url="$1"
    local timeout="${2:-$TIMEOUT}"
    local start_time end_time duration_ms
    local exit_code=0
    local output=""

    # Get current time in milliseconds (cross-platform)
    if [[ "$(uname)" == "Darwin" ]]; then
        start_time=$(($(date +%s) * 1000))
    else
        start_time=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
    fi

    # Run wget with SSL verification
    # -q: quiet mode
    # --spider: don't download, just check
    # -T: timeout
    # -t 1: only try once
    output=$(wget -q --spider \
        -T "$timeout" \
        -t 1 \
        "$url" 2>&1) || exit_code=$?

    # Get end time in milliseconds (cross-platform)
    if [[ "$(uname)" == "Darwin" ]]; then
        end_time=$(($(date +%s) * 1000))
    else
        end_time=$(date +%s%3N 2>/dev/null || echo "$(($(date +%s) * 1000))")
    fi
    duration_ms=$((end_time - start_time))

    echo "$exit_code"
    echo "$output"
    echo "$duration_ms"
}

# Classify wget exit codes
classify_wget_exit_code() {
    local code="$1"

    case "$code" in
        0)
            echo "none"
            ;;
        1)
            echo "unknown"  # Generic error
            ;;
        2)
            echo "unknown"  # Parse error
            ;;
        3)
            echo "permission_error"  # File I/O error
            ;;
        4)
            echo "network_error"  # Network failure
            ;;
        5)
            echo "ssl_error"  # SSL verification failure
            ;;
        6)
            echo "unknown"  # Username/password auth failure
            ;;
        7)
            echo "unknown"  # Protocol error
            ;;
        8)
            echo "network_error"  # Server error response
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get human-readable description of wget exit code
describe_wget_exit_code() {
    local code="$1"

    case "$code" in
        0)  echo "Success" ;;
        1)  echo "Generic error" ;;
        2)  echo "Parse error" ;;
        3)  echo "File I/O error" ;;
        4)  echo "Network failure" ;;
        5)  echo "SSL certificate verification failure" ;;
        6)  echo "Authentication failure" ;;
        7)  echo "Protocol error" ;;
        8)  echo "Server error response" ;;
        *)  echo "Unknown error (code: $code)" ;;
    esac
}

# Generate fix suggestions for wget errors
generate_wget_fix() {
    local error_type="$1"
    local error_message="$2"
    local ca_bundle

    ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

    case "$error_type" in
        ssl_error)
            local description="Set SSL_CERT_FILE environment variable to point to your CA certificate bundle"
            local env_vars="{}"
            local commands="[]"

            if [[ -n "$ca_bundle" ]]; then
                env_vars="{\"SSL_CERT_FILE\":\"$ca_bundle\"}"
                commands="[\"export SSL_CERT_FILE=\\\"$ca_bundle\\\"\"]"
            else
                env_vars="{\"SSL_CERT_FILE\":\"/path/to/your/ca-bundle.crt\"}"
                commands="[\"# First, locate or create your CA bundle\",\"export SSL_CERT_FILE=/path/to/ca-bundle.crt\"]"
                description="$description. No system CA bundle was found."
            fi

            # Alternative: use --no-check-certificate (not recommended for production)
            commands=$(echo "$commands" | sed 's/]$/,"# Or temporarily disable verification (NOT RECOMMENDED):","wget --no-check-certificate URL"]/')

            # Check for specific SSL sub-errors
            local ssl_subtype
            ssl_subtype=$(classify_ssl_error "$error_message")

            case "$ssl_subtype" in
                cert_self_signed)
                    description="The server is using a self-signed certificate. Add the certificate to your trust store or set SSL_CERT_FILE."
                    ;;
                cert_expired)
                    description="The server's SSL certificate has expired. Contact the server administrator."
                    ;;
                untrusted_root)
                    description="The certificate chain leads to an untrusted root CA. Set SSL_CERT_FILE to include your corporate CA certificate."
                    ;;
            esac

            create_fix_json "$description" "$env_vars" "$commands"
            ;;
        dns_error)
            create_fix_json \
                "DNS resolution failed. Check that the hostname is correct and your DNS settings are configured." \
                "{}" \
                "[\"# Check DNS resolution:\",\"nslookup hostname\"]"
            ;;
        network_error)
            create_fix_json \
                "Network connection failed. Check your network connectivity and firewall settings." \
                "{}" \
                "[\"# Test basic connectivity:\",\"ping hostname\"]"
            ;;
        timeout)
            create_fix_json \
                "Connection timed out. The server may be slow or unreachable." \
                "{}" \
                "[\"# Increase timeout:\",\"wget -T 30 URL\"]"
            ;;
        *)
            echo "null"
            ;;
    esac
}

# Main check function
# Outputs JSON result to stdout
check_wget() {
    local url="${1:-https://www.google.com}"

    # Check if wget is installed
    if ! check_wget_installed; then
        local platform_json
        platform_json=$(get_platform_json)

        create_result_json \
            "wget" \
            "not_installed" \
            "$url" \
            "false" \
            "runtime_missing" \
            "wget is not installed" \
            "127" \
            "0" \
            "$platform_json" \
            "$(create_fix_json "Install wget using your package manager" "{}" "[\"# On macOS:\",\"brew install wget\",\"# On Ubuntu/Debian:\",\"sudo apt-get install wget\",\"# On RHEL/CentOS:\",\"sudo yum install wget\"]")"
        return
    fi

    local version
    version=$(get_wget_version)

    local platform_json
    platform_json=$(get_platform_json)

    # Run the check
    local result
    result=$(run_wget_check "$url" "$TIMEOUT")

    # Parse result (three lines: exit_code, output, duration_ms)
    local exit_code output duration_ms
    exit_code=$(echo "$result" | sed -n '1p')
    output=$(echo "$result" | sed -n '2p')
    duration_ms=$(echo "$result" | sed -n '3p')

    # Determine success and error classification
    local success error_type error_message fix_json

    if [[ "$exit_code" -eq 0 ]]; then
        success="true"
        error_type="none"
        error_message=""
        fix_json="null"
    else
        success="false"
        error_type=$(classify_wget_exit_code "$exit_code")

        # If we couldn't classify by exit code, try the output
        if [[ "$error_type" == "unknown" ]]; then
            error_type=$(classify_error "$output")
        fi

        error_message=$(describe_wget_exit_code "$exit_code")
        if [[ -n "$output" ]]; then
            error_message="$error_message - $output"
        fi

        fix_json=$(generate_wget_fix "$error_type" "$error_message")
    fi

    # Output the result
    create_result_json \
        "wget" \
        "$version" \
        "$url" \
        "$success" \
        "$error_type" \
        "$error_message" \
        "$exit_code" \
        "$duration_ms" \
        "$platform_json" \
        "$fix_json"
}

# Human-readable output mode
check_wget_human() {
    local url="${1:-https://www.google.com}"

    echo "=== wget SSL Connectivity Check ==="
    echo ""
    echo "URL: $url"

    if ! check_wget_installed; then
        echo "Status: FAILED"
        echo "Error: wget is not installed"
        echo ""
        echo "To install wget:"
        echo "  macOS:        brew install wget"
        echo "  Ubuntu/Debian: sudo apt-get install wget"
        echo "  RHEL/CentOS:  sudo yum install wget"
        return 1
    fi

    echo "wget version: $(get_wget_version)"
    echo "SSL info: $(get_wget_ssl_info)"
    echo ""
    echo "Testing connection..."

    local result exit_code output duration_ms
    result=$(run_wget_check "$url" "$TIMEOUT")
    exit_code=$(echo "$result" | sed -n '1p')
    output=$(echo "$result" | sed -n '2p')
    duration_ms=$(echo "$result" | sed -n '3p')

    if [[ "$exit_code" -eq 0 ]]; then
        echo "Status: SUCCESS"
        echo "Duration: ${duration_ms}ms"
        return 0
    else
        echo "Status: FAILED"
        echo "Exit code: $exit_code"
        echo "Error: $(describe_wget_exit_code "$exit_code")"
        if [[ -n "$output" ]]; then
            echo "Details: $output"
        fi
        echo ""
        echo "Suggested fix:"

        local error_type
        error_type=$(classify_wget_exit_code "$exit_code")

        if [[ "$error_type" == "ssl_error" ]]; then
            local ca_bundle
            ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

            if [[ -n "$ca_bundle" ]]; then
                echo "  export SSL_CERT_FILE=\"$ca_bundle\""
            else
                echo "  # No system CA bundle found"
                echo "  export SSL_CERT_FILE=/path/to/your/ca-bundle.crt"
            fi
            echo ""
            echo "  # Or temporarily (NOT RECOMMENDED for production):"
            echo "  wget --no-check-certificate URL"
        fi

        return 1
    fi
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    url="${1:-https://www.google.com}"
    mode="${2:-json}"

    case "$mode" in
        --human|-h|human)
            check_wget_human "$url"
            ;;
        --json|-j|json|*)
            check_wget "$url"
            ;;
    esac
fi
