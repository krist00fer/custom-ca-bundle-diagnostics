#!/usr/bin/env bash
# ca-extract.sh - Extract CA certificates from server certificate chains

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/detect-os.sh"

# Default timeout for connections
CONNECT_TIMEOUT=10

# Check if openssl is available
check_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: openssl is required but not installed" >&2
        return 1
    fi
    return 0
}

# Extract host and port from URL
# Usage: parse_url "https://example.com:8443/path"
parse_url() {
    local url="$1"
    local host port

    # Remove protocol
    url="${url#*://}"
    # Remove path
    url="${url%%/*}"
    # Remove username:password if present
    url="${url##*@}"

    # Extract port if present
    if [[ "$url" == *:* ]]; then
        host="${url%:*}"
        port="${url##*:}"
    else
        host="$url"
        port="443"  # Default HTTPS port
    fi

    echo "$host:$port"
}

# Get the full certificate chain from a server
# Usage: get_certificate_chain "example.com" "443"
get_certificate_chain() {
    local host="$1"
    local port="${2:-443}"

    check_openssl || return 1

    # Use openssl s_client to connect and get the certificate chain
    openssl s_client \
        -connect "${host}:${port}" \
        -showcerts \
        -servername "$host" \
        </dev/null 2>/dev/null
}

# Extract all certificates from the chain
# Usage: echo "$chain_output" | extract_all_certs
extract_all_certs() {
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/'
}

# Extract just the server certificate (first in chain)
# Usage: echo "$chain_output" | extract_server_cert
extract_server_cert() {
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{print; if(/-----END CERTIFICATE-----/) exit}'
}

# Extract the root CA certificate (last in chain)
# Usage: echo "$chain_output" | extract_root_cert
extract_root_cert() {
    local cert=""
    local in_cert=false
    local last_cert=""

    while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            in_cert=true
            cert="$line"$'\n'
        elif [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            cert+="$line"$'\n'
            last_cert="$cert"
            in_cert=false
            cert=""
        elif [[ "$in_cert" == true ]]; then
            cert+="$line"$'\n'
        fi
    done

    echo -n "$last_cert"
}

# Extract intermediate certificates (everything except first and last)
# Usage: echo "$chain_output" | extract_intermediate_certs
extract_intermediate_certs() {
    local certs=()
    local cert=""
    local in_cert=false

    while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            in_cert=true
            cert="$line"$'\n'
        elif [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            cert+="$line"$'\n'
            certs+=("$cert")
            in_cert=false
            cert=""
        elif [[ "$in_cert" == true ]]; then
            cert+="$line"$'\n'
        fi
    done

    # Output all except first and last
    local count=${#certs[@]}
    if [[ $count -gt 2 ]]; then
        for ((i=1; i<count-1; i++)); do
            echo -n "${certs[$i]}"
        done
    fi
}

# Get certificate information
# Usage: get_cert_info "$certificate_pem"
get_cert_info() {
    local cert="$1"

    check_openssl || return 1

    echo "$cert" | openssl x509 -noout -text 2>/dev/null | head -20
}

# Get certificate subject
# Usage: get_cert_subject "$certificate_pem"
get_cert_subject() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject= //'
}

# Get certificate issuer
# Usage: get_cert_issuer "$certificate_pem"
get_cert_issuer() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer= //'
}

# Get certificate validity dates
# Usage: get_cert_dates "$certificate_pem"
get_cert_dates() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -dates 2>/dev/null
}

# Check if certificate is expired
# Usage: is_cert_expired "$certificate_pem"
is_cert_expired() {
    local cert="$1"

    if echo "$cert" | openssl x509 -noout -checkend 0 2>/dev/null; then
        return 1  # Not expired
    else
        return 0  # Expired
    fi
}

# Check if certificate is self-signed
# Usage: is_self_signed "$certificate_pem"
is_self_signed() {
    local cert="$1"
    local subject issuer

    subject=$(get_cert_subject "$cert")
    issuer=$(get_cert_issuer "$cert")

    [[ "$subject" == "$issuer" ]]
}

# Save certificate to file
# Usage: save_cert_to_file "$certificate_pem" "/path/to/output.crt"
save_cert_to_file() {
    local cert="$1"
    local output_path="$2"

    echo "$cert" > "$output_path"
    echo "Certificate saved to: $output_path"
}

# Extract and save certificates from a URL
# Usage: extract_certs_from_url "https://example.com" "/output/dir"
extract_certs_from_url() {
    local url="$1"
    local output_dir="${2:-.}"
    local host_port chain

    # Parse the URL
    host_port=$(parse_url "$url")
    local host="${host_port%:*}"
    local port="${host_port#*:}"

    echo "Connecting to $host:$port..."

    # Get the certificate chain
    chain=$(get_certificate_chain "$host" "$port")

    if [[ -z "$chain" ]]; then
        echo "Error: Failed to retrieve certificates from $host:$port" >&2
        return 1
    fi

    # Create output directory
    mkdir -p "$output_dir"

    # Extract and save certificates
    local all_certs
    all_certs=$(echo "$chain" | extract_all_certs)

    if [[ -z "$all_certs" ]]; then
        echo "Error: No certificates found in response" >&2
        return 1
    fi

    # Count certificates
    local cert_count
    cert_count=$(echo "$all_certs" | grep -c "BEGIN CERTIFICATE" || echo "0")
    echo "Found $cert_count certificate(s) in chain"

    # Save the full chain
    local chain_file="${output_dir}/${host}-chain.pem"
    echo "$all_certs" > "$chain_file"
    echo "  Full chain saved to: $chain_file"

    # Save individual certificates
    local cert=""
    local in_cert=false
    local cert_num=0

    while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            in_cert=true
            cert="$line"$'\n'
        elif [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            cert+="$line"$'\n'
            ((cert_num++))

            local subject
            subject=$(get_cert_subject "$cert" | sed 's/.*CN = //' | sed 's/,.*//' | tr ' ' '_' | tr -cd '[:alnum:]_.-')

            if [[ -z "$subject" ]]; then
                subject="cert${cert_num}"
            fi

            local cert_file="${output_dir}/${host}-${cert_num}-${subject}.pem"
            echo "$cert" > "$cert_file"

            # Show certificate info
            local issuer
            issuer=$(get_cert_issuer "$cert" | sed 's/.*CN = //' | sed 's/,.*//')
            echo "  [$cert_num] $subject (issued by: $issuer)"

            if is_cert_expired "$cert"; then
                echo "      WARNING: Certificate is expired!"
            fi

            if is_self_signed "$cert"; then
                echo "      Note: Self-signed certificate"
            fi

            in_cert=false
            cert=""
        elif [[ "$in_cert" == true ]]; then
            cert+="$line"$'\n'
        fi
    done <<< "$all_certs"

    # Save just the root CA if present
    if [[ $cert_num -gt 1 ]]; then
        local root_cert
        root_cert=$(echo "$all_certs" | extract_root_cert)
        local root_file="${output_dir}/${host}-root-ca.pem"
        echo "$root_cert" > "$root_file"
        echo "  Root CA saved to: $root_file"
    fi

    echo ""
    echo "To use these certificates:"
    echo "  export SSL_CERT_FILE=\"$chain_file\""
    echo "  export CURL_CA_BUNDLE=\"$chain_file\""
}

# Verify server certificate against a CA bundle
# Usage: verify_server_cert "example.com" "443" "/path/to/ca-bundle.crt"
verify_server_cert() {
    local host="$1"
    local port="${2:-443}"
    local ca_bundle="${3:-}"

    check_openssl || return 1

    local verify_opts=""
    if [[ -n "$ca_bundle" ]]; then
        verify_opts="-CAfile $ca_bundle"
    fi

    echo "Verifying certificate for $host:$port..."

    # shellcheck disable=SC2086
    local result
    result=$(openssl s_client \
        -connect "${host}:${port}" \
        -servername "$host" \
        $verify_opts \
        </dev/null 2>&1)

    # Check verification result
    if echo "$result" | grep -q "Verify return code: 0"; then
        echo "Certificate verification: SUCCESS"
        return 0
    else
        local error
        error=$(echo "$result" | grep "Verify return code:" | head -1)
        echo "Certificate verification: FAILED"
        echo "  $error"
        return 1
    fi
}

# Get detailed certificate chain info as JSON
# Usage: get_chain_info_json "example.com" "443"
get_chain_info_json() {
    local host="$1"
    local port="${2:-443}"
    local chain all_certs

    check_openssl || return 1

    chain=$(get_certificate_chain "$host" "$port")
    all_certs=$(echo "$chain" | extract_all_certs)

    local cert_count
    cert_count=$(echo "$all_certs" | grep -c "BEGIN CERTIFICATE" || echo "0")

    echo "{"
    echo "  \"host\": \"$host\","
    echo "  \"port\": $port,"
    echo "  \"certificate_count\": $cert_count,"
    echo "  \"certificates\": ["

    local cert=""
    local in_cert=false
    local cert_num=0
    local first=true

    while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            in_cert=true
            cert="$line"$'\n'
        elif [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            cert+="$line"$'\n'
            ((cert_num++))

            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi

            local subject issuer not_before not_after expired self_signed
            subject=$(get_cert_subject "$cert")
            issuer=$(get_cert_issuer "$cert")
            not_before=$(echo "$cert" | openssl x509 -noout -startdate 2>/dev/null | sed 's/notBefore=//')
            not_after=$(echo "$cert" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
            expired=$(is_cert_expired "$cert" && echo "true" || echo "false")
            self_signed=$(is_self_signed "$cert" && echo "true" || echo "false")

            cat <<CERT_JSON
    {
      "index": $cert_num,
      "subject": "$subject",
      "issuer": "$issuer",
      "not_before": "$not_before",
      "not_after": "$not_after",
      "expired": $expired,
      "self_signed": $self_signed
    }
CERT_JSON

            in_cert=false
            cert=""
        elif [[ "$in_cert" == true ]]; then
            cert+="$line"$'\n'
        fi
    done <<< "$all_certs"

    echo ""
    echo "  ]"
    echo "}"
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --extract|-e)
            url="${2:-}"
            output_dir="${3:-.}"
            if [[ -z "$url" ]]; then
                echo "Usage: $0 --extract URL [OUTPUT_DIR]"
                exit 1
            fi
            extract_certs_from_url "$url" "$output_dir"
            ;;
        --verify|-v)
            url="${2:-}"
            ca_bundle="${3:-}"
            if [[ -z "$url" ]]; then
                echo "Usage: $0 --verify URL [CA_BUNDLE]"
                exit 1
            fi
            host_port=$(parse_url "$url")
            verify_server_cert "${host_port%:*}" "${host_port#*:}" "$ca_bundle"
            ;;
        --info|-i)
            url="${2:-}"
            if [[ -z "$url" ]]; then
                echo "Usage: $0 --info URL"
                exit 1
            fi
            host_port=$(parse_url "$url")
            get_chain_info_json "${host_port%:*}" "${host_port#*:}"
            ;;
        --help|-h)
            cat <<EOF
CA Certificate Extraction Utility

Usage: $0 [OPTIONS] URL

Options:
  --extract, -e URL [DIR]  Extract certificates from server and save to directory
  --verify, -v URL [CA]    Verify server certificate against CA bundle
  --info, -i URL           Get certificate chain info as JSON
  --help, -h               Show this help message

Examples:
  $0 --extract https://example.com ./certs
  $0 --verify https://example.com /etc/ssl/cert.pem
  $0 --info https://internal.company.com

The extracted certificates can be used with:
  export SSL_CERT_FILE=/path/to/chain.pem
  export CURL_CA_BUNDLE=/path/to/chain.pem
EOF
            ;;
        *)
            if [[ -n "${1:-}" ]]; then
                # Default: extract certificates
                extract_certs_from_url "$1" "${2:-.}"
            else
                echo "Usage: $0 [--extract|--verify|--info] URL"
                echo "Try '$0 --help' for more information."
                exit 1
            fi
            ;;
    esac
fi
