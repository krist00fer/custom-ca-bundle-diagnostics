#!/usr/bin/env bash
# error-classify.sh - Error classification and categorization utilities

set -euo pipefail

# Guard against multiple sourcing
if [[ -n "${_ERROR_CLASSIFY_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_ERROR_CLASSIFY_LOADED=1

# Error types
ERROR_TYPE_NONE="none"
ERROR_TYPE_SSL="ssl_error"
ERROR_TYPE_NETWORK="network_error"
ERROR_TYPE_TIMEOUT="timeout"
ERROR_TYPE_DNS="dns_error"
ERROR_TYPE_RUNTIME_MISSING="runtime_missing"
ERROR_TYPE_PERMISSION="permission_error"
ERROR_TYPE_UNKNOWN="unknown"

# SSL error sub-types for more specific diagnosis
SSL_CERT_VERIFY_FAILED="cert_verify_failed"
SSL_CERT_EXPIRED="cert_expired"
SSL_CERT_SELF_SIGNED="cert_self_signed"
SSL_CERT_HOSTNAME_MISMATCH="hostname_mismatch"
SSL_CERT_UNTRUSTED_ROOT="untrusted_root"
SSL_CERT_CHAIN_INCOMPLETE="chain_incomplete"
SSL_PROTOCOL_ERROR="protocol_error"
SSL_HANDSHAKE_FAILED="handshake_failed"

# SSL error patterns (case-insensitive matching)
declare -a SSL_ERROR_PATTERNS=(
    "certificate verify failed"
    "ssl certificate problem"
    "unable to get local issuer certificate"
    "unable to get issuer certificate"
    "self.signed certificate"
    "self-signed certificate"
    "certificate has expired"
    "certificate is not yet valid"
    "hostname .* doesn't match"
    "hostname mismatch"
    "ssl_error"
    "ssl error"
    "tlsv1"
    "ssl23"
    "certificate_verify_failed"
    "sslcertverificationerror"
    "ssl.sslerror"
    "x509"
    "unable to verify"
    "certificate chain"
    "depth lookup"
    "verify return"
    "handshake failure"
    "handshake failed"
    "ssl handshake"
    "alert handshake"
    "no peer certificate"
    "peer certificate cannot be authenticated"
)

# Network error patterns
declare -a NETWORK_ERROR_PATTERNS=(
    "connection refused"
    "connection reset"
    "no route to host"
    "network is unreachable"
    "network unreachable"
    "host unreachable"
    "connection failed"
    "failed to connect"
    "couldn't connect"
    "could not connect"
    "socket error"
    "broken pipe"
    "connection closed"
    "connection aborted"
    "connect error"
)

# DNS error patterns
declare -a DNS_ERROR_PATTERNS=(
    "could not resolve"
    "couldn't resolve"
    "name or service not known"
    "no such host"
    "host not found"
    "name resolution"
    "dns"
    "getaddrinfo"
    "nodename nor servname"
    "temporary failure in name resolution"
    "unknown host"
    "resolve host"
)

# Timeout patterns
declare -a TIMEOUT_PATTERNS=(
    "timed out"
    "timeout"
    "operation timed out"
    "connection timed out"
    "read timed out"
    "deadline exceeded"
)

# Missing runtime/command patterns
declare -a MISSING_PATTERNS=(
    "command not found"
    "not found"
    "not installed"
    "no such file or directory"
    "is not recognized"
    "cannot find"
)

# Permission patterns
declare -a PERMISSION_PATTERNS=(
    "permission denied"
    "access denied"
    "operation not permitted"
    "forbidden"
    "unauthorized"
)

# Classify an error message
# Usage: classify_error "error message text"
# Returns: error type constant
classify_error() {
    local error_message="${1,,}"  # Convert to lowercase

    # Check for runtime missing first (highest priority)
    for pattern in "${MISSING_PATTERNS[@]}"; do
        if [[ "$error_message" == *"$pattern"* ]]; then
            echo "$ERROR_TYPE_RUNTIME_MISSING"
            return
        fi
    done

    # Check for SSL errors
    for pattern in "${SSL_ERROR_PATTERNS[@]}"; do
        if [[ "$error_message" == *"$pattern"* ]]; then
            echo "$ERROR_TYPE_SSL"
            return
        fi
    done

    # Check for DNS errors
    for pattern in "${DNS_ERROR_PATTERNS[@]}"; do
        if [[ "$error_message" == *"$pattern"* ]]; then
            echo "$ERROR_TYPE_DNS"
            return
        fi
    done

    # Check for timeout
    for pattern in "${TIMEOUT_PATTERNS[@]}"; do
        if [[ "$error_message" == *"$pattern"* ]]; then
            echo "$ERROR_TYPE_TIMEOUT"
            return
        fi
    done

    # Check for network errors
    for pattern in "${NETWORK_ERROR_PATTERNS[@]}"; do
        if [[ "$error_message" == *"$pattern"* ]]; then
            echo "$ERROR_TYPE_NETWORK"
            return
        fi
    done

    # Check for permission errors
    for pattern in "${PERMISSION_PATTERNS[@]}"; do
        if [[ "$error_message" == *"$pattern"* ]]; then
            echo "$ERROR_TYPE_PERMISSION"
            return
        fi
    done

    echo "$ERROR_TYPE_UNKNOWN"
}

# Get more specific SSL error sub-type
# Usage: classify_ssl_error "error message text"
classify_ssl_error() {
    local error_message="${1,,}"

    # Self-signed certificate
    if [[ "$error_message" == *"self.signed"* ]] || [[ "$error_message" == *"self-signed"* ]]; then
        echo "$SSL_CERT_SELF_SIGNED"
        return
    fi

    # Expired certificate
    if [[ "$error_message" == *"expired"* ]] || [[ "$error_message" == *"not yet valid"* ]]; then
        echo "$SSL_CERT_EXPIRED"
        return
    fi

    # Hostname mismatch
    if [[ "$error_message" == *"hostname"* ]] && [[ "$error_message" == *"match"* ]]; then
        echo "$SSL_CERT_HOSTNAME_MISMATCH"
        return
    fi

    # Unable to get local issuer (untrusted root / incomplete chain)
    if [[ "$error_message" == *"unable to get local issuer"* ]] || \
       [[ "$error_message" == *"unable to get issuer"* ]]; then
        echo "$SSL_CERT_UNTRUSTED_ROOT"
        return
    fi

    # Certificate chain issues
    if [[ "$error_message" == *"certificate chain"* ]] || \
       [[ "$error_message" == *"depth lookup"* ]]; then
        echo "$SSL_CERT_CHAIN_INCOMPLETE"
        return
    fi

    # Handshake failures
    if [[ "$error_message" == *"handshake"* ]]; then
        echo "$SSL_HANDSHAKE_FAILED"
        return
    fi

    # Protocol errors
    if [[ "$error_message" == *"protocol"* ]] || \
       [[ "$error_message" == *"tlsv1"* ]] || \
       [[ "$error_message" == *"ssl23"* ]]; then
        echo "$SSL_PROTOCOL_ERROR"
        return
    fi

    # Generic verify failed
    echo "$SSL_CERT_VERIFY_FAILED"
}

# Check if error is SSL-related
# Usage: is_ssl_error "error message"
is_ssl_error() {
    local error_type
    error_type=$(classify_error "$1")
    [[ "$error_type" == "$ERROR_TYPE_SSL" ]]
}

# Check if error is network-related (including DNS)
# Usage: is_network_error "error message"
is_network_error() {
    local error_type
    error_type=$(classify_error "$1")
    [[ "$error_type" == "$ERROR_TYPE_NETWORK" ]] || \
    [[ "$error_type" == "$ERROR_TYPE_DNS" ]] || \
    [[ "$error_type" == "$ERROR_TYPE_TIMEOUT" ]]
}

# Classify curl exit code
# Usage: classify_curl_exit_code 60
classify_curl_exit_code() {
    local code="$1"

    case "$code" in
        0)
            echo "$ERROR_TYPE_NONE"
            ;;
        6)
            echo "$ERROR_TYPE_DNS"
            ;;
        7)
            echo "$ERROR_TYPE_NETWORK"
            ;;
        28)
            echo "$ERROR_TYPE_TIMEOUT"
            ;;
        35|51|53|54|58|59|60|66|77|80|82|83|90|91)
            echo "$ERROR_TYPE_SSL"
            ;;
        *)
            echo "$ERROR_TYPE_UNKNOWN"
            ;;
    esac
}

# Get human-readable description of curl exit code
# Usage: describe_curl_exit_code 60
describe_curl_exit_code() {
    local code="$1"

    case "$code" in
        0)  echo "Success" ;;
        6)  echo "Could not resolve host" ;;
        7)  echo "Failed to connect to host" ;;
        28) echo "Operation timed out" ;;
        35) echo "SSL connect error" ;;
        51) echo "SSL peer certificate or SSH remote key was not OK" ;;
        53) echo "SSL crypto engine not found" ;;
        54) echo "SSL failed setting default crypto engine" ;;
        58) echo "Problem with the local client SSL certificate" ;;
        59) echo "Could not use specified SSL cipher" ;;
        60) echo "SSL certificate problem: unable to get local issuer certificate" ;;
        66) echo "SSL failed to initialize" ;;
        77) echo "Problem reading the SSL CA cert" ;;
        80) echo "Failed to shut down the SSL connection" ;;
        82) echo "Could not load CRL file" ;;
        83) echo "Issuer check failed" ;;
        90) echo "SSL public key does not match pinned public key" ;;
        91) echo "SSL certificate status verification failed" ;;
        *)  echo "Unknown error (code: $code)" ;;
    esac
}

# Classify wget exit code
# Usage: classify_wget_exit_code 5
classify_wget_exit_code() {
    local code="$1"

    case "$code" in
        0)
            echo "$ERROR_TYPE_NONE"
            ;;
        4)
            echo "$ERROR_TYPE_NETWORK"
            ;;
        5)
            echo "$ERROR_TYPE_SSL"
            ;;
        *)
            echo "$ERROR_TYPE_UNKNOWN"
            ;;
    esac
}

# Get human-readable error type description
# Usage: describe_error_type "ssl_error"
describe_error_type() {
    local error_type="$1"

    case "$error_type" in
        "$ERROR_TYPE_NONE")
            echo "No error - connection successful"
            ;;
        "$ERROR_TYPE_SSL")
            echo "SSL/TLS certificate verification error"
            ;;
        "$ERROR_TYPE_NETWORK")
            echo "Network connection error"
            ;;
        "$ERROR_TYPE_DNS")
            echo "DNS resolution error"
            ;;
        "$ERROR_TYPE_TIMEOUT")
            echo "Connection timeout"
            ;;
        "$ERROR_TYPE_RUNTIME_MISSING")
            echo "Required tool/runtime not installed"
            ;;
        "$ERROR_TYPE_PERMISSION")
            echo "Permission denied"
            ;;
        *)
            echo "Unknown error type"
            ;;
    esac
}

# If run directly, demonstrate with examples
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error Classification Examples:"
    echo ""

    test_messages=(
        "SSL certificate problem: unable to get local issuer certificate"
        "curl: (60) SSL certificate problem: unable to get local issuer certificate"
        "Connection refused"
        "Could not resolve host: example.com"
        "Operation timed out"
        "bash: python: command not found"
        "Permission denied"
        "SSLError: [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed"
        "Some random error message"
    )

    for msg in "${test_messages[@]}"; do
        error_type=$(classify_error "$msg")
        echo "Message: $msg"
        echo "  Type: $error_type"
        echo "  Description: $(describe_error_type "$error_type")"
        if [[ "$error_type" == "$ERROR_TYPE_SSL" ]]; then
            ssl_subtype=$(classify_ssl_error "$msg")
            echo "  SSL Sub-type: $ssl_subtype"
        fi
        echo ""
    done

    echo ""
    echo "Curl Exit Code Classification:"
    for code in 0 6 7 28 35 60; do
        echo "  Code $code: $(classify_curl_exit_code "$code") - $(describe_curl_exit_code "$code")"
    done
fi
