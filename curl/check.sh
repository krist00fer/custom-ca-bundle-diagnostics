#!/usr/bin/env bash
# curl/check.sh - curl SSL connectivity diagnostic module

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

# Check if curl is installed
check_curl_installed() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get curl version
get_curl_version() {
    if check_curl_installed; then
        curl --version | head -1 | awk '{print $2}'
    else
        echo "not_installed"
    fi
}

# Get curl SSL backend info
get_curl_ssl_info() {
    if check_curl_installed; then
        curl --version | grep -i "ssl\|tls" | head -1
    else
        echo "not_available"
    fi
}

# Run curl check against URL
# Returns: exit_code, output (stderr), duration_ms
run_curl_check() {
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

    # Run curl with SSL verification
    # -s: silent mode (no progress)
    # -S: show errors
    # -f: fail on HTTP errors
    # -o /dev/null: discard output
    # --connect-timeout: connection timeout
    # -m: max time for entire operation
    output=$(curl -sS -f -o /dev/null \
        --connect-timeout "$timeout" \
        -m "$((timeout * 2))" \
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

# Generate fix suggestions for curl errors
generate_curl_fix() {
    local error_type="$1"
    local error_message="$2"
    local ca_bundle

    ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

    case "$error_type" in
        ssl_error)
            local description="Set CURL_CA_BUNDLE environment variable to point to your CA certificate bundle"
            local env_vars="{}"
            local commands="[]"

            if [[ -n "$ca_bundle" ]]; then
                env_vars="{\"CURL_CA_BUNDLE\":\"$ca_bundle\"}"
                commands="[\"export CURL_CA_BUNDLE=\\\"$ca_bundle\\\"\"]"
            else
                env_vars="{\"CURL_CA_BUNDLE\":\"/path/to/your/ca-bundle.crt\"}"
                commands="[\"# First, locate or create your CA bundle\",\"export CURL_CA_BUNDLE=/path/to/ca-bundle.crt\"]"
                description="$description. No system CA bundle was found - you may need to extract certificates from your corporate proxy or obtain them from your IT department."
            fi

            # Check for specific SSL sub-errors
            local ssl_subtype
            ssl_subtype=$(classify_ssl_error "$error_message")

            case "$ssl_subtype" in
                cert_self_signed)
                    description="The server is using a self-signed certificate. You need to add this certificate to your trust store or use CURL_CA_BUNDLE."
                    ;;
                cert_expired)
                    description="The server's SSL certificate has expired. Contact the server administrator to renew the certificate."
                    ;;
                hostname_mismatch)
                    description="The server's SSL certificate doesn't match the hostname. This could indicate a man-in-the-middle attack or a server misconfiguration."
                    ;;
                untrusted_root)
                    description="The certificate chain leads to an untrusted root CA. This is common in corporate environments with SSL inspection. Set CURL_CA_BUNDLE to include your corporate CA certificate."
                    ;;
            esac

            create_fix_json "$description" "$env_vars" "$commands"
            ;;
        dns_error)
            create_fix_json \
                "DNS resolution failed. Check that the hostname is correct and your DNS settings are properly configured." \
                "{}" \
                "[\"# Check DNS resolution:\",\"nslookup \$(echo URL | sed 's|https://||' | cut -d'/' -f1)\"]"
            ;;
        network_error)
            create_fix_json \
                "Network connection failed. Check your network connectivity and firewall settings." \
                "{}" \
                "[\"# Test basic connectivity:\",\"ping -c 3 \$(echo URL | sed 's|https://||' | cut -d'/' -f1)\"]"
            ;;
        timeout)
            create_fix_json \
                "Connection timed out. The server may be slow or unreachable. Try increasing the timeout or check network connectivity." \
                "{}" \
                "[\"# Increase timeout:\",\"curl --connect-timeout 30 URL\"]"
            ;;
        *)
            echo "null"
            ;;
    esac
}

# Main check function
# Outputs JSON result to stdout
check_curl() {
    local url="${1:-https://www.google.com}"

    # Check if curl is installed
    if ! check_curl_installed; then
        local platform_json
        platform_json=$(get_platform_json)

        create_result_json \
            "curl" \
            "not_installed" \
            "$url" \
            "false" \
            "runtime_missing" \
            "curl is not installed" \
            "127" \
            "0" \
            "$platform_json" \
            "$(create_fix_json "Install curl using your package manager" "{}" "[\"# On macOS:\",\"brew install curl\",\"# On Ubuntu/Debian:\",\"sudo apt-get install curl\",\"# On RHEL/CentOS:\",\"sudo yum install curl\"]")"
        return
    fi

    local version
    version=$(get_curl_version)

    local platform_json
    platform_json=$(get_platform_json)

    # Run the check
    local result
    result=$(run_curl_check "$url" "$TIMEOUT")

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
        error_type=$(classify_curl_exit_code "$exit_code")

        # If we couldn't classify by exit code, try the output
        if [[ "$error_type" == "unknown" ]]; then
            error_type=$(classify_error "$output")
        fi

        error_message=$(describe_curl_exit_code "$exit_code")
        if [[ -n "$output" ]]; then
            error_message="$error_message - $output"
        fi

        fix_json=$(generate_curl_fix "$error_type" "$error_message")
    fi

    # Output the result
    create_result_json \
        "curl" \
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
check_curl_human() {
    local url="${1:-https://www.google.com}"

    echo "=== curl SSL Connectivity Check ==="
    echo ""
    echo "URL: $url"

    if ! check_curl_installed; then
        echo "Status: FAILED"
        echo "Error: curl is not installed"
        echo ""
        echo "To install curl:"
        echo "  macOS:        brew install curl"
        echo "  Ubuntu/Debian: sudo apt-get install curl"
        echo "  RHEL/CentOS:  sudo yum install curl"
        return 1
    fi

    echo "curl version: $(get_curl_version)"
    echo "SSL backend: $(get_curl_ssl_info)"
    echo ""
    echo "Testing connection..."

    local result exit_code output duration_ms
    result=$(run_curl_check "$url" "$TIMEOUT")
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
        echo "Error: $(describe_curl_exit_code "$exit_code")"
        if [[ -n "$output" ]]; then
            echo "Details: $output"
        fi
        echo ""
        echo "Suggested fix:"

        local error_type
        error_type=$(classify_curl_exit_code "$exit_code")

        if [[ "$error_type" == "ssl_error" ]]; then
            local ca_bundle
            ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

            if [[ -n "$ca_bundle" ]]; then
                echo "  export CURL_CA_BUNDLE=\"$ca_bundle\""
            else
                echo "  # No system CA bundle found"
                echo "  # You may need to obtain your corporate CA certificate"
                echo "  export CURL_CA_BUNDLE=/path/to/your/ca-bundle.crt"
            fi
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
            check_curl_human "$url"
            ;;
        --json|-j|json|*)
            check_curl "$url"
            ;;
    esac
fi
