#!/usr/bin/env bash
# dotnet/check.sh - .NET SSL connectivity diagnostic module runner

set -euo pipefail

DOTNET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DOTNET_SCRIPT_DIR/.." && pwd)"

# Source common utilities
source "${PROJECT_ROOT}/common/detect-os.sh"
source "${PROJECT_ROOT}/common/json-utils.sh"
source "${PROJECT_ROOT}/common/error-classify.sh"
source "${PROJECT_ROOT}/common/ca-bundle.sh"
source "${DOTNET_SCRIPT_DIR}/detect-versions.sh"

# Default timeout
TIMEOUT="${TIMEOUT:-10}"

# Build directory for compiled code
BUILD_DIR="${DOTNET_SCRIPT_DIR}/.build"

# Ensure the .NET project is built
ensure_built() {
    local target_framework="${1:-net8.0}"

    mkdir -p "$BUILD_DIR"

    # Check if we need to rebuild
    local cs_file="${DOTNET_SCRIPT_DIR}/CheckSsl.cs"
    local csproj_file="${DOTNET_SCRIPT_DIR}/CheckSsl.csproj"
    local dll_file="${BUILD_DIR}/bin/Release/${target_framework}/CheckSsl.dll"

    # Rebuild if source is newer than dll or dll doesn't exist
    if [[ ! -f "$dll_file" ]] || \
       [[ "$cs_file" -nt "$dll_file" ]] || \
       [[ "$csproj_file" -nt "$dll_file" ]]; then

        log_debug "Building .NET SSL checker..."

        # Create a temporary project with the correct target framework
        local temp_csproj="${BUILD_DIR}/CheckSsl.csproj"
        cat > "$temp_csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>${target_framework}</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>
</Project>
EOF

        # Copy source file
        cp "$cs_file" "$BUILD_DIR/"

        # Build (from the build directory)
        if ! (cd "$BUILD_DIR" && dotnet build CheckSsl.csproj -c Release --nologo -v q 2>&1 >/dev/null); then
            return 1
        fi
    fi

    return 0
}

# Run .NET SSL check
run_dotnet_check() {
    local url="$1"
    local timeout="${2:-$TIMEOUT}"
    local target_framework="$3"

    # Find the DLL in the build output directory
    local dll_path="${BUILD_DIR}/bin/Release/${target_framework}/CheckSsl.dll"

    # Run the compiled checker
    dotnet "$dll_path" "$url" "$timeout" 2>&1
}

# Generate fix suggestions for .NET SSL errors
generate_dotnet_fix() {
    local error_type="$1"
    local error_message="$2"
    local ca_bundle os

    ca_bundle=$(find_system_ca_bundle 2>/dev/null || echo "")
    os=$(detect_os)

    if [[ "$error_type" != "ssl_error" ]]; then
        echo "null"
        return
    fi

    local description=".NET uses the platform's certificate store. You need to add your CA certificate to the system trust store."
    local env_vars="{}"
    local commands="[]"

    case "$os" in
        darwin)
            description="On macOS, add your CA certificate to the System Keychain"
            commands=$(cat <<'EOF'
[
  "# Add certificate to macOS System Keychain:",
  "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/cert.crt",
  "",
  "# Or set environment variable:",
  "export SSL_CERT_FILE=/path/to/ca-bundle.crt"
]
EOF
)
            ;;
        linux|wsl)
            local distro
            distro=$(detect_distro)
            case "$distro" in
                ubuntu|debian|mint|pop)
                    commands=$(cat <<'EOF'
[
  "# On Ubuntu/Debian, copy certificate and update:",
  "sudo cp /path/to/cert.crt /usr/local/share/ca-certificates/",
  "sudo update-ca-certificates",
  "",
  "# Or set environment variable:",
  "export SSL_CERT_FILE=/path/to/ca-bundle.crt"
]
EOF
)
                    ;;
                rhel|centos|fedora|rocky|alma)
                    commands=$(cat <<'EOF'
[
  "# On RHEL/CentOS/Fedora:",
  "sudo cp /path/to/cert.crt /etc/pki/ca-trust/source/anchors/",
  "sudo update-ca-trust",
  "",
  "# Or set environment variable:",
  "export SSL_CERT_FILE=/path/to/ca-bundle.crt"
]
EOF
)
                    ;;
                *)
                    commands=$(cat <<'EOF'
[
  "# Add certificate to system trust store (method varies by distro)",
  "# Then set environment variable:",
  "export SSL_CERT_FILE=/path/to/ca-bundle.crt"
]
EOF
)
                    ;;
            esac
            ;;
        *)
            commands='["export SSL_CERT_FILE=/path/to/ca-bundle.crt"]'
            ;;
    esac

    if [[ -n "$ca_bundle" ]]; then
        env_vars="{\"SSL_CERT_FILE\":\"$ca_bundle\"}"
    else
        env_vars="{\"SSL_CERT_FILE\":\"/path/to/ca-bundle.crt\"}"
    fi

    create_fix_json "$description" "$env_vars" "$commands"
}

# Debug logging (only when VERBOSE >= 3)
log_debug() {
    if [[ "${VERBOSE:-1}" -ge 3 ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Main check function
check_dotnet() {
    local url="${1:-https://www.google.com}"
    local requested_version="${2:-}"

    local platform_json
    platform_json=$(get_platform_json)

    # Check if .NET is available
    if ! check_dotnet_installed; then
        create_result_json \
            "dotnet" \
            "not_installed" \
            "$url" \
            "false" \
            "runtime_missing" \
            ".NET SDK is not installed" \
            "127" \
            "0" \
            "$platform_json" \
            "$(create_fix_json "Install .NET SDK" "{}" "[\"# On macOS:\",\"brew install dotnet\",\"# On Linux:\",\"# See https://dot.net/download\"]")"
        return
    fi

    local version
    version=$(get_dotnet_version)

    # Determine target framework
    local target_framework="net8.0"
    local major_version
    major_version=$(get_dotnet_major_version)

    if [[ -n "$requested_version" ]]; then
        target_framework="net${requested_version}.0"
        # Check if requested version is available
        if ! is_dotnet_version_available "$requested_version"; then
            create_result_json \
                "dotnet" \
                "$version" \
                "$url" \
                "false" \
                "runtime_missing" \
                ".NET $requested_version is not installed (have: $version)" \
                "1" \
                "0" \
                "$platform_json" \
                "$(create_fix_json "Install .NET $requested_version" "{}" "[\"dotnet --list-sdks\",\"# Visit https://dot.net/download to install .NET $requested_version\"]")"
            return
        fi
    elif [[ -n "$major_version" ]]; then
        target_framework="net${major_version}.0"
    fi

    # Build the checker
    if ! ensure_built "$target_framework" 2>/dev/null; then
        create_result_json \
            "dotnet" \
            "$version" \
            "$url" \
            "false" \
            "unknown" \
            "Failed to build .NET SSL checker" \
            "1" \
            "0" \
            "$platform_json" \
            "null"
        return
    fi

    # Run the check
    local result
    result=$(run_dotnet_check "$url" "$TIMEOUT" "$target_framework" 2>&1) || true

    # Check if result is valid JSON
    if echo "$result" | head -1 | grep -q "^{"; then
        # Result appears to be JSON, output directly
        echo "$result"
    else
        # Parse as error
        local error_type
        error_type=$(classify_error "$result")

        create_result_json \
            "dotnet" \
            "$version" \
            "$url" \
            "false" \
            "$error_type" \
            ".NET check failed: $result" \
            "1" \
            "0" \
            "$platform_json" \
            "$(generate_dotnet_fix "$error_type" "$result")"
    fi
}

# Human-readable output mode
check_dotnet_human() {
    local url="${1:-https://www.google.com}"
    local requested_version="${2:-}"

    echo "=== .NET SSL Connectivity Check ==="
    echo ""
    echo "URL: $url"

    if ! check_dotnet_installed; then
        echo "Status: FAILED"
        echo "Error: .NET SDK is not installed"
        echo ""
        echo "To install .NET:"
        echo "  macOS:  brew install dotnet"
        echo "  Linux:  See https://dot.net/download"
        return 1
    fi

    local version
    version=$(get_dotnet_version)

    echo ".NET Version: $version"
    echo ""

    # Show SDK info
    echo "Installed SDKs:"
    dotnet --list-sdks 2>/dev/null | head -5 | while read -r line; do
        echo "  - $line"
    done
    echo ""

    echo "Building checker..."

    # Build
    local target_framework="net8.0"
    local major_version
    major_version=$(get_dotnet_major_version)
    if [[ -n "$major_version" ]]; then
        target_framework="net${major_version}.0"
    fi

    if ! ensure_built "$target_framework" 2>/dev/null; then
        echo "Status: FAILED"
        echo "Error: Failed to build .NET SSL checker"
        return 1
    fi

    echo "Testing connection..."
    echo ""

    # Run the check
    local result
    result=$(run_dotnet_check "$url" "$TIMEOUT" "$target_framework" 2>&1) || true

    # Try to parse JSON result
    if command -v python3 >/dev/null 2>&1 && \
       echo "$result" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then

        local success error_type error_message

        success=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))")
        error_type=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('errorType', 'unknown'))")
        error_message=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('errorMessage', ''))")

        if [[ "$success" == "True" ]]; then
            echo "Status: SUCCESS"
            return 0
        else
            echo "Status: FAILED"
            echo "Error Type: $error_type"
            echo "Error: $error_message"
            echo ""
            echo "Suggested fix:"

            local os
            os=$(detect_os)

            case "$os" in
                darwin)
                    echo "  # Add certificate to macOS System Keychain:"
                    echo "  sudo security add-trusted-cert -d -r trustRoot \\"
                    echo "    -k /Library/Keychains/System.keychain /path/to/cert.crt"
                    ;;
                linux)
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo cp /path/to/cert.crt /usr/local/share/ca-certificates/"
                    echo "  sudo update-ca-certificates"
                    echo ""
                    echo "  # RHEL/CentOS:"
                    echo "  sudo cp /path/to/cert.crt /etc/pki/ca-trust/source/anchors/"
                    echo "  sudo update-ca-trust"
                    ;;
            esac

            return 1
        fi
    else
        echo "Status: FAILED"
        echo "Output: $result"
        return 1
    fi
}

# Clean up build artifacts
clean() {
    rm -rf "$BUILD_DIR"
    echo "Cleaned .NET build artifacts"
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --clean)
            clean
            exit 0
            ;;
        *)
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
                    check_dotnet_human "$url" "$version"
                    ;;
                --json|-j|json|*)
                    check_dotnet "$url" "$version"
                    ;;
            esac
            ;;
    esac
fi
