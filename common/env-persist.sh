#!/usr/bin/env bash
# env-persist.sh - Environment variable persistence utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/detect-shell.sh"
source "${SCRIPT_DIR}/detect-os.sh"

# Marker comment for our additions
MARKER_START="# SSL Diagnostics - Environment Variables (auto-generated)"
MARKER_END="# End SSL Diagnostics"

# Create a backup of a config file
create_backup() {
    local file="$1"
    local backup_dir="${2:-$(dirname "$file")}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local backup_file="${backup_dir}/$(basename "$file").backup.${timestamp}"

    if [[ -f "$file" ]]; then
        cp "$file" "$backup_file"
        echo "$backup_file"
    else
        echo ""
    fi
}

# Check if an environment variable is already set in a config file
# Usage: is_env_var_in_file "SSL_CERT_FILE" "/path/to/config"
is_env_var_in_file() {
    local var_name="$1"
    local file="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Look for export VAR_NAME= pattern
    if grep -qE "^[[:space:]]*export[[:space:]]+${var_name}=" "$file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Get the current value of an env var from a config file
get_env_var_from_file() {
    local var_name="$1"
    local file="$2"

    if [[ ! -f "$file" ]]; then
        return
    fi

    # Extract value (handles both quoted and unquoted)
    grep -E "^[[:space:]]*export[[:space:]]+${var_name}=" "$file" 2>/dev/null | \
        sed -E "s/^[[:space:]]*export[[:space:]]+${var_name}=[\"']?([^\"']*)[\"']?.*/\1/" | \
        tail -1
}

# Add environment variable to config file
# Usage: add_env_var "SSL_CERT_FILE" "/path/to/ca-bundle.crt" ["/path/to/config"]
add_env_var() {
    local var_name="$1"
    local var_value="$2"
    local config_file="${3:-$(get_recommended_config)}"

    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        touch "$config_file"
    fi

    # Check if already set
    if is_env_var_in_file "$var_name" "$config_file"; then
        local current_value
        current_value=$(get_env_var_from_file "$var_name" "$config_file")

        if [[ "$current_value" == "$var_value" ]]; then
            echo "Already set: $var_name=$var_value"
            return 0
        else
            echo "Updating: $var_name (was: $current_value)"
            # Remove old value and add new one
            remove_env_var "$var_name" "$config_file"
        fi
    fi

    # Create backup
    local backup
    backup=$(create_backup "$config_file")
    if [[ -n "$backup" ]]; then
        echo "Backup: $backup"
    fi

    # Add the variable
    {
        echo ""
        echo "export ${var_name}=\"${var_value}\""
    } >> "$config_file"

    echo "Added: export ${var_name}=\"${var_value}\""
    echo "File: $config_file"
}

# Add multiple SSL-related environment variables at once
# Usage: add_ssl_env_vars "/path/to/ca-bundle.crt" ["/path/to/config"]
add_ssl_env_vars() {
    local ca_bundle="$1"
    local config_file="${2:-$(get_recommended_config)}"

    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        touch "$config_file"
    fi

    # Create backup
    local backup
    backup=$(create_backup "$config_file")
    if [[ -n "$backup" ]]; then
        echo "Backup created: $backup"
    fi

    # Check if our block already exists
    if grep -q "$MARKER_START" "$config_file" 2>/dev/null; then
        echo "Removing existing SSL Diagnostics configuration..."
        remove_ssl_env_vars "$config_file"
    fi

    # Add the block
    {
        echo ""
        echo "$MARKER_START"
        echo "export SSL_CERT_FILE=\"${ca_bundle}\""
        echo "export SSL_CERT_DIR=\"$(dirname "$ca_bundle")\""
        echo "export CURL_CA_BUNDLE=\"${ca_bundle}\""
        echo "export REQUESTS_CA_BUNDLE=\"${ca_bundle}\""
        echo "export GIT_SSL_CAINFO=\"${ca_bundle}\""
        echo "export PIP_CERT=\"${ca_bundle}\""
        echo "export NODE_EXTRA_CA_CERTS=\"${ca_bundle}\""
        echo "$MARKER_END"
    } >> "$config_file"

    echo ""
    echo "Added SSL environment variables to: $config_file"
    echo ""
    echo "Variables set:"
    echo "  SSL_CERT_FILE=$ca_bundle"
    echo "  CURL_CA_BUNDLE=$ca_bundle"
    echo "  REQUESTS_CA_BUNDLE=$ca_bundle"
    echo "  GIT_SSL_CAINFO=$ca_bundle"
    echo "  PIP_CERT=$ca_bundle"
    echo "  NODE_EXTRA_CA_CERTS=$ca_bundle"
    echo ""
    echo "To apply changes, run: source $config_file"
}

# Remove an environment variable from config file
# Usage: remove_env_var "SSL_CERT_FILE" ["/path/to/config"]
remove_env_var() {
    local var_name="$1"
    local config_file="${2:-$(get_recommended_config)}"

    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    # Create backup
    local backup
    backup=$(create_backup "$config_file")

    # Remove lines matching the export statement
    local temp_file
    temp_file=$(mktemp)

    grep -vE "^[[:space:]]*export[[:space:]]+${var_name}=" "$config_file" > "$temp_file" || true
    mv "$temp_file" "$config_file"

    echo "Removed: $var_name from $config_file"
    if [[ -n "$backup" ]]; then
        echo "Backup: $backup"
    fi
}

# Remove SSL Diagnostics block from config file
remove_ssl_env_vars() {
    local config_file="${1:-$(get_recommended_config)}"

    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    # Create backup
    local backup
    backup=$(create_backup "$config_file")

    # Remove the block between markers
    local temp_file
    temp_file=$(mktemp)

    sed "/${MARKER_START}/,/${MARKER_END}/d" "$config_file" > "$temp_file"
    mv "$temp_file" "$config_file"

    echo "Removed SSL Diagnostics configuration from: $config_file"
    if [[ -n "$backup" ]]; then
        echo "Backup: $backup"
    fi
}

# List current SSL-related environment variables
list_ssl_env_vars() {
    echo "Current SSL-related environment variables:"
    echo ""

    local vars=(
        "SSL_CERT_FILE"
        "SSL_CERT_DIR"
        "CURL_CA_BUNDLE"
        "REQUESTS_CA_BUNDLE"
        "GIT_SSL_CAINFO"
        "GIT_SSL_CAPATH"
        "PIP_CERT"
        "NODE_EXTRA_CA_CERTS"
    )

    for var in "${vars[@]}"; do
        local value="${!var:-}"
        if [[ -n "$value" ]]; then
            echo "  $var=$value"
        else
            echo "  $var=(not set)"
        fi
    done
}

# Interactive configuration
interactive_config() {
    echo "SSL Environment Variable Configuration"
    echo "======================================="
    echo ""

    # Show current state
    list_ssl_env_vars
    echo ""

    # Detect shell and recommend config file
    local shell config_file
    shell=$(detect_current_shell)
    config_file=$(get_recommended_config)

    echo "Detected shell: $shell"
    echo "Recommended config file: $config_file"
    echo ""

    # Find CA bundle
    local ca_bundle
    ca_bundle=$(bash "${SCRIPT_DIR}/ca-bundle.sh" 2>/dev/null || echo "")

    if [[ -n "$ca_bundle" ]]; then
        echo "Found system CA bundle: $ca_bundle"
        echo ""
        echo "Options:"
        echo "  1) Add SSL environment variables using this CA bundle"
        echo "  2) Specify a different CA bundle path"
        echo "  3) Remove SSL environment variables"
        echo "  4) Cancel"
        echo ""
        echo -n "Choice [1-4]: "
        read -r choice

        case "$choice" in
            1)
                add_ssl_env_vars "$ca_bundle" "$config_file"
                ;;
            2)
                echo -n "Enter CA bundle path: "
                read -r custom_path
                if [[ -f "$custom_path" ]]; then
                    add_ssl_env_vars "$custom_path" "$config_file"
                else
                    echo "Error: File not found: $custom_path"
                    return 1
                fi
                ;;
            3)
                remove_ssl_env_vars "$config_file"
                ;;
            *)
                echo "Cancelled"
                ;;
        esac
    else
        echo "No system CA bundle found."
        echo ""
        echo "You can either:"
        echo "  1) Extract certificates from a server:"
        echo "     bash common/ca-extract.sh https://your-server.com"
        echo ""
        echo "  2) Obtain certificates from your IT department"
        echo ""
        echo -n "Enter CA bundle path (or press Enter to cancel): "
        read -r custom_path

        if [[ -n "$custom_path" && -f "$custom_path" ]]; then
            add_ssl_env_vars "$custom_path" "$config_file"
        elif [[ -n "$custom_path" ]]; then
            echo "Error: File not found: $custom_path"
            return 1
        else
            echo "Cancelled"
        fi
    fi
}

# Show configuration status
show_status() {
    echo "Environment Persistence Status"
    echo "==============================="
    echo ""

    local config_file
    config_file=$(get_recommended_config)

    echo "Shell: $(detect_current_shell)"
    echo "Config file: $config_file"
    echo ""

    if [[ -f "$config_file" ]]; then
        if grep -q "$MARKER_START" "$config_file" 2>/dev/null; then
            echo "SSL Diagnostics configuration: INSTALLED"
            echo ""
            echo "Configured variables:"
            sed -n "/${MARKER_START}/,/${MARKER_END}/p" "$config_file" | \
                grep -E "^export" | \
                sed 's/^/  /'
        else
            echo "SSL Diagnostics configuration: NOT INSTALLED"
        fi
    else
        echo "Config file does not exist"
    fi

    echo ""
    list_ssl_env_vars
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --interactive|-i)
            interactive_config
            ;;
        --add|-a)
            var_name="${2:-}"
            var_value="${3:-}"
            config_file="${4:-}"
            if [[ -z "$var_name" || -z "$var_value" ]]; then
                echo "Usage: $0 --add VAR_NAME VAR_VALUE [CONFIG_FILE]"
                exit 1
            fi
            add_env_var "$var_name" "$var_value" "$config_file"
            ;;
        --add-ssl)
            ca_bundle="${2:-}"
            config_file="${3:-}"
            if [[ -z "$ca_bundle" ]]; then
                echo "Usage: $0 --add-ssl CA_BUNDLE_PATH [CONFIG_FILE]"
                exit 1
            fi
            add_ssl_env_vars "$ca_bundle" "$config_file"
            ;;
        --remove|-r)
            var_name="${2:-}"
            config_file="${3:-}"
            if [[ -z "$var_name" ]]; then
                echo "Usage: $0 --remove VAR_NAME [CONFIG_FILE]"
                exit 1
            fi
            remove_env_var "$var_name" "$config_file"
            ;;
        --remove-ssl)
            config_file="${2:-}"
            remove_ssl_env_vars "$config_file"
            ;;
        --list|-l)
            list_ssl_env_vars
            ;;
        --status|-s)
            show_status
            ;;
        --help|-h)
            cat <<EOF
Environment Variable Persistence Utility

Usage: $0 [OPTIONS]

Options:
  --interactive, -i      Interactive configuration wizard
  --add VAR VALUE [FILE] Add environment variable
  --add-ssl CA_BUNDLE    Add all SSL-related env vars with given CA bundle
  --remove VAR [FILE]    Remove environment variable
  --remove-ssl [FILE]    Remove SSL Diagnostics configuration block
  --list, -l             List current SSL-related env vars
  --status, -s           Show configuration status
  --help, -h             Show this help message

Examples:
  $0 --interactive
  $0 --add-ssl /etc/ssl/cert.pem
  $0 --remove SSL_CERT_FILE
  $0 --status
EOF
            ;;
        *)
            show_status
            ;;
    esac
fi
