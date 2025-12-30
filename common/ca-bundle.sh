#!/usr/bin/env bash
# ca-bundle.sh - CA bundle detection and management utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/detect-os.sh"

# Common CA bundle paths by operating system
# macOS paths
MACOS_CA_PATHS=(
    "/etc/ssl/cert.pem"
    "/private/etc/ssl/cert.pem"
    "/usr/local/etc/openssl/cert.pem"
    "/usr/local/etc/openssl@1.1/cert.pem"
    "/opt/homebrew/etc/openssl/cert.pem"
    "/opt/homebrew/etc/openssl@3/cert.pem"
)

# Linux (Debian/Ubuntu) paths
DEBIAN_CA_PATHS=(
    "/etc/ssl/certs/ca-certificates.crt"
    "/etc/ssl/certs"
)

# Linux (RHEL/CentOS/Fedora) paths
RHEL_CA_PATHS=(
    "/etc/pki/tls/certs/ca-bundle.crt"
    "/etc/pki/tls/certs/ca-bundle.trust.crt"
    "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
    "/etc/pki/tls/certs"
)

# Linux (Alpine) paths
ALPINE_CA_PATHS=(
    "/etc/ssl/certs/ca-certificates.crt"
    "/etc/ssl/cert.pem"
)

# Linux (Arch) paths
ARCH_CA_PATHS=(
    "/etc/ssl/certs/ca-certificates.crt"
    "/etc/ca-certificates/extracted/tls-ca-bundle.pem"
)

# Linux (SUSE) paths
SUSE_CA_PATHS=(
    "/etc/ssl/ca-bundle.pem"
    "/var/lib/ca-certificates/ca-bundle.pem"
)

# Generic Linux paths (fallback)
GENERIC_LINUX_CA_PATHS=(
    "/etc/ssl/certs/ca-certificates.crt"
    "/etc/pki/tls/certs/ca-bundle.crt"
    "/etc/ssl/cert.pem"
    "/etc/ssl/certs"
)

# Get CA bundle paths for current system
get_ca_paths_for_system() {
    local os distro

    os="$(detect_os)"
    distro="$(detect_distro)"

    case "$os" in
        darwin)
            printf '%s\n' "${MACOS_CA_PATHS[@]}"
            ;;
        linux|wsl)
            case "$distro" in
                ubuntu|debian|raspbian|mint|pop)
                    printf '%s\n' "${DEBIAN_CA_PATHS[@]}"
                    ;;
                rhel|centos|fedora|rocky|alma|oracle)
                    printf '%s\n' "${RHEL_CA_PATHS[@]}"
                    ;;
                alpine)
                    printf '%s\n' "${ALPINE_CA_PATHS[@]}"
                    ;;
                arch|manjaro)
                    printf '%s\n' "${ARCH_CA_PATHS[@]}"
                    ;;
                opensuse*|suse|sles)
                    printf '%s\n' "${SUSE_CA_PATHS[@]}"
                    ;;
                *)
                    printf '%s\n' "${GENERIC_LINUX_CA_PATHS[@]}"
                    ;;
            esac
            ;;
        *)
            printf '%s\n' "${GENERIC_LINUX_CA_PATHS[@]}"
            ;;
    esac
}

# Find the system's default CA bundle file
# Returns the first existing CA bundle path
find_system_ca_bundle() {
    local path

    # Read paths and check each one
    while IFS= read -r path; do
        # Check if it's a file (not directory)
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done < <(get_ca_paths_for_system)

    # Try common environment variables
    if [[ -n "${SSL_CERT_FILE:-}" && -f "$SSL_CERT_FILE" ]]; then
        echo "$SSL_CERT_FILE"
        return 0
    fi

    if [[ -n "${CURL_CA_BUNDLE:-}" && -f "$CURL_CA_BUNDLE" ]]; then
        echo "$CURL_CA_BUNDLE"
        return 0
    fi

    if [[ -n "${REQUESTS_CA_BUNDLE:-}" && -f "$REQUESTS_CA_BUNDLE" ]]; then
        echo "$REQUESTS_CA_BUNDLE"
        return 0
    fi

    # Not found
    return 1
}

# Find the system's CA certificate directory
find_ca_cert_dir() {
    local path

    while IFS= read -r path; do
        if [[ -d "$path" ]]; then
            echo "$path"
            return 0
        fi
    done < <(get_ca_paths_for_system)

    # Check SSL_CERT_DIR
    if [[ -n "${SSL_CERT_DIR:-}" && -d "$SSL_CERT_DIR" ]]; then
        echo "$SSL_CERT_DIR"
        return 0
    fi

    return 1
}

# List all existing CA bundle locations on the system
list_all_ca_bundles() {
    local all_paths=()
    local found=()

    # Collect all possible paths
    all_paths+=(
        "${MACOS_CA_PATHS[@]}"
        "${DEBIAN_CA_PATHS[@]}"
        "${RHEL_CA_PATHS[@]}"
        "${ALPINE_CA_PATHS[@]}"
        "${ARCH_CA_PATHS[@]}"
        "${SUSE_CA_PATHS[@]}"
    )

    # Add environment variable paths
    [[ -n "${SSL_CERT_FILE:-}" ]] && all_paths+=("$SSL_CERT_FILE")
    [[ -n "${SSL_CERT_DIR:-}" ]] && all_paths+=("$SSL_CERT_DIR")
    [[ -n "${CURL_CA_BUNDLE:-}" ]] && all_paths+=("$CURL_CA_BUNDLE")
    [[ -n "${REQUESTS_CA_BUNDLE:-}" ]] && all_paths+=("$REQUESTS_CA_BUNDLE")

    # Check which ones exist
    for path in "${all_paths[@]}"; do
        if [[ -e "$path" ]]; then
            # Avoid duplicates
            local is_dup=false
            for f in "${found[@]:-}"; do
                if [[ "$f" == "$path" ]]; then
                    is_dup=true
                    break
                fi
            done
            if [[ "$is_dup" == false ]]; then
                found+=("$path")
            fi
        fi
    done

    printf '%s\n' "${found[@]}"
}

# Verify that a CA bundle file is valid
# Usage: verify_ca_bundle "/path/to/ca-bundle.crt"
verify_ca_bundle() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        echo "error: File does not exist"
        return 1
    fi

    if [[ ! -r "$path" ]]; then
        echo "error: File is not readable"
        return 1
    fi

    # Check if it contains at least one certificate
    if ! grep -q "BEGIN CERTIFICATE" "$path" 2>/dev/null; then
        echo "error: File does not contain any certificates"
        return 1
    fi

    # Try to parse with openssl if available
    if command -v openssl >/dev/null 2>&1; then
        local cert_count
        cert_count=$(grep -c "BEGIN CERTIFICATE" "$path" 2>/dev/null || echo "0")

        if [[ "$cert_count" -eq 0 ]]; then
            echo "error: No valid certificates found"
            return 1
        fi

        echo "valid: Contains $cert_count certificate(s)"
        return 0
    fi

    echo "valid: File contains certificate data"
    return 0
}

# Get CA bundle info as JSON
get_ca_bundle_info_json() {
    local bundle_path dir_path bundle_valid=""
    local found_bundles=()

    # Find primary bundle
    if bundle_path=$(find_system_ca_bundle 2>/dev/null); then
        bundle_valid=$(verify_ca_bundle "$bundle_path" 2>/dev/null || echo "unknown")
    else
        bundle_path="null"
        bundle_valid="not_found"
    fi

    # Find directory
    dir_path=$(find_ca_cert_dir 2>/dev/null || echo "null")

    # Build JSON
    echo "{"
    if [[ "$bundle_path" != "null" ]]; then
        echo "  \"primary_bundle\": \"$bundle_path\","
    else
        echo "  \"primary_bundle\": null,"
    fi
    echo "  \"bundle_valid\": \"$bundle_valid\","
    if [[ "$dir_path" != "null" ]]; then
        echo "  \"cert_directory\": \"$dir_path\","
    else
        echo "  \"cert_directory\": null,"
    fi
    echo "  \"all_bundles\": ["
    local first=true
    list_all_ca_bundles | while IFS= read -r bundle; do
        if [[ "$first" == true ]]; then
            first=false
            echo -n "    \"$bundle\""
        else
            echo ","
            echo -n "    \"$bundle\""
        fi
    done
    echo ""
    echo "  ],"
    echo "  \"env_vars\": {"
    if [[ -n "${SSL_CERT_FILE:-}" ]]; then
        echo "    \"SSL_CERT_FILE\": \"$SSL_CERT_FILE\","
    else
        echo "    \"SSL_CERT_FILE\": null,"
    fi
    if [[ -n "${SSL_CERT_DIR:-}" ]]; then
        echo "    \"SSL_CERT_DIR\": \"$SSL_CERT_DIR\","
    else
        echo "    \"SSL_CERT_DIR\": null,"
    fi
    if [[ -n "${CURL_CA_BUNDLE:-}" ]]; then
        echo "    \"CURL_CA_BUNDLE\": \"$CURL_CA_BUNDLE\","
    else
        echo "    \"CURL_CA_BUNDLE\": null,"
    fi
    if [[ -n "${REQUESTS_CA_BUNDLE:-}" ]]; then
        echo "    \"REQUESTS_CA_BUNDLE\": \"$REQUESTS_CA_BUNDLE\""
    else
        echo "    \"REQUESTS_CA_BUNDLE\": null"
    fi
    echo "  }"
    echo "}"
}

# Suggest the best CA bundle path for a specific tool
# Usage: suggest_ca_bundle_for_tool "curl"
suggest_ca_bundle_for_tool() {
    local tool="$1"
    local bundle_path

    bundle_path=$(find_system_ca_bundle 2>/dev/null || echo "")

    if [[ -z "$bundle_path" ]]; then
        echo "No system CA bundle found"
        return 1
    fi

    case "$tool" in
        curl)
            echo "export CURL_CA_BUNDLE=\"$bundle_path\""
            ;;
        wget)
            echo "export SSL_CERT_FILE=\"$bundle_path\""
            ;;
        python|pip)
            echo "export REQUESTS_CA_BUNDLE=\"$bundle_path\""
            echo "export SSL_CERT_FILE=\"$bundle_path\""
            echo "export PIP_CERT=\"$bundle_path\""
            ;;
        node|npm)
            echo "export NODE_EXTRA_CA_CERTS=\"$bundle_path\""
            ;;
        git)
            echo "export GIT_SSL_CAINFO=\"$bundle_path\""
            ;;
        dotnet)
            echo "export SSL_CERT_FILE=\"$bundle_path\""
            ;;
        *)
            echo "export SSL_CERT_FILE=\"$bundle_path\""
            ;;
    esac
}

# Create a custom CA bundle by combining system bundle with additional certs
# Usage: create_custom_bundle "/path/to/output.pem" "/path/to/extra1.crt" "/path/to/extra2.crt"
create_custom_bundle() {
    local output_path="$1"
    shift
    local extra_certs=("$@")

    local system_bundle
    system_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")

    # Create/clear output file
    : > "$output_path"

    # Add system bundle if found
    if [[ -n "$system_bundle" && -f "$system_bundle" ]]; then
        cat "$system_bundle" >> "$output_path"
        echo "" >> "$output_path"
    fi

    # Add extra certificates
    for cert in "${extra_certs[@]}"; do
        if [[ -f "$cert" ]]; then
            echo "# Added from: $cert" >> "$output_path"
            cat "$cert" >> "$output_path"
            echo "" >> "$output_path"
        else
            echo "Warning: Certificate file not found: $cert" >&2
        fi
    done

    # Verify the result
    if verify_ca_bundle "$output_path" >/dev/null 2>&1; then
        echo "Created custom CA bundle at: $output_path"
        return 0
    else
        echo "Error: Failed to create valid CA bundle" >&2
        return 1
    fi
}

# Interactive mode handler
handle_find_flag() {
    echo "Searching for CA bundles on your system..."
    echo ""

    local bundle_path dir_path
    bundle_path=$(find_system_ca_bundle 2>/dev/null || echo "")
    dir_path=$(find_ca_cert_dir 2>/dev/null || echo "")

    echo "Primary CA Bundle:"
    if [[ -n "$bundle_path" ]]; then
        echo "  $bundle_path"
        echo "  $(verify_ca_bundle "$bundle_path")"
    else
        echo "  Not found"
    fi

    echo ""
    echo "CA Certificate Directory:"
    if [[ -n "$dir_path" ]]; then
        echo "  $dir_path"
    else
        echo "  Not found"
    fi

    echo ""
    echo "All CA bundles found:"
    list_all_ca_bundles | while read -r path; do
        local type
        if [[ -f "$path" ]]; then
            type="file"
        else
            type="dir"
        fi
        echo "  [$type] $path"
    done

    echo ""
    echo "Environment variables:"
    echo "  SSL_CERT_FILE:     ${SSL_CERT_FILE:-<not set>}"
    echo "  SSL_CERT_DIR:      ${SSL_CERT_DIR:-<not set>}"
    echo "  CURL_CA_BUNDLE:    ${CURL_CA_BUNDLE:-<not set>}"
    echo "  REQUESTS_CA_BUNDLE: ${REQUESTS_CA_BUNDLE:-<not set>}"
}

# Main entry point when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --find|-f)
            handle_find_flag
            ;;
        --json|-j)
            get_ca_bundle_info_json
            ;;
        --suggest)
            tool="${2:-generic}"
            suggest_ca_bundle_for_tool "$tool"
            ;;
        --verify)
            path="${2:-}"
            if [[ -z "$path" ]]; then
                echo "Usage: $0 --verify /path/to/ca-bundle.crt"
                exit 1
            fi
            verify_ca_bundle "$path"
            ;;
        --help|-h)
            cat <<EOF
CA Bundle Detection Utility

Usage: $0 [OPTIONS]

Options:
  --find, -f           Find and list all CA bundles on the system
  --json, -j           Output CA bundle info as JSON
  --suggest TOOL       Suggest environment variables for a specific tool
  --verify PATH        Verify a CA bundle file is valid
  --help, -h           Show this help message

Examples:
  $0 --find
  $0 --suggest curl
  $0 --verify /etc/ssl/cert.pem
EOF
            ;;
        *)
            # Default: show primary bundle
            bundle=$(find_system_ca_bundle 2>/dev/null || echo "")
            if [[ -n "$bundle" ]]; then
                echo "$bundle"
            else
                echo "No CA bundle found" >&2
                exit 1
            fi
            ;;
    esac
fi
