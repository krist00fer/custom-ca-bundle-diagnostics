#!/usr/bin/env bash
# detect-versions.sh - Detect installed .NET versions

set -euo pipefail

# Known .NET versions
DOTNET_VERSIONS=("9" "8" "7" "6")

# Check if dotnet is installed
check_dotnet_installed() {
    command -v dotnet >/dev/null 2>&1
}

# Get dotnet CLI version
get_dotnet_version() {
    if check_dotnet_installed; then
        dotnet --version 2>/dev/null || echo "unknown"
    else
        echo "not_installed"
    fi
}

# List installed SDKs
list_dotnet_sdks() {
    if check_dotnet_installed; then
        dotnet --list-sdks 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# List installed runtimes
list_dotnet_runtimes() {
    if check_dotnet_installed; then
        dotnet --list-runtimes 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Check if a specific .NET version is available
# Usage: is_dotnet_version_available "8"
is_dotnet_version_available() {
    local target_version="$1"

    if ! check_dotnet_installed; then
        return 1
    fi

    # Check SDKs
    local sdks
    sdks=$(list_dotnet_sdks)

    if echo "$sdks" | grep -q "^${target_version}\."; then
        return 0
    fi

    # Check runtimes
    local runtimes
    runtimes=$(list_dotnet_runtimes)

    if echo "$runtimes" | grep -q "${target_version}\."; then
        return 0
    fi

    return 1
}

# Get all installed .NET versions as JSON
detect_dotnet_versions() {
    if ! check_dotnet_installed; then
        echo '{"installed": false, "sdks": [], "runtimes": []}'
        return
    fi

    local cli_version sdks runtimes

    cli_version=$(get_dotnet_version)
    sdks=$(list_dotnet_sdks | awk '{print "\"" $1 "\""}' | paste -sd, -)
    runtimes=$(list_dotnet_runtimes | awk '{print "\"" $1 " " $2 "\""}' | paste -sd, -)

    cat <<EOF
{
  "installed": true,
  "cli_version": "$cli_version",
  "sdks": [${sdks}],
  "runtimes": [${runtimes}],
  "path": "$(command -v dotnet)"
}
EOF
}

# Get the major version of the installed SDK
get_dotnet_major_version() {
    if ! check_dotnet_installed; then
        echo ""
        return
    fi

    get_dotnet_version | cut -d. -f1
}

# Show human-readable summary
show_dotnet_summary() {
    echo "Installed .NET Versions:"
    echo ""

    if ! check_dotnet_installed; then
        echo "  .NET is not installed"
        echo ""
        echo "To install .NET:"
        echo "  macOS:   brew install dotnet"
        echo "  Linux:   See https://dot.net/download"
        return
    fi

    local cli_version
    cli_version=$(get_dotnet_version)

    echo "  CLI Version: $cli_version"
    echo "  Path: $(command -v dotnet)"
    echo ""

    echo "  Installed SDKs:"
    local sdks
    sdks=$(list_dotnet_sdks)
    if [[ -n "$sdks" ]]; then
        echo "$sdks" | while read -r line; do
            echo "    - $line"
        done
    else
        echo "    (none)"
    fi

    echo ""
    echo "  Installed Runtimes:"
    local runtimes
    runtimes=$(list_dotnet_runtimes)
    if [[ -n "$runtimes" ]]; then
        echo "$runtimes" | while read -r line; do
            echo "    - $line"
        done
    else
        echo "    (none)"
    fi

    echo ""
    echo "  Available major versions:"
    for ver in "${DOTNET_VERSIONS[@]}"; do
        if is_dotnet_version_available "$ver"; then
            echo "    - .NET $ver: available"
        else
            echo "    - .NET $ver: not installed"
        fi
    done
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --json|-j)
            detect_dotnet_versions
            ;;
        --check|-c)
            version="${2:-}"
            if [[ -z "$version" ]]; then
                if check_dotnet_installed; then
                    echo ".NET is installed"
                    exit 0
                else
                    echo ".NET is not installed"
                    exit 1
                fi
            else
                if is_dotnet_version_available "$version"; then
                    echo ".NET $version is available"
                    exit 0
                else
                    echo ".NET $version is not available"
                    exit 1
                fi
            fi
            ;;
        --version|-v)
            get_dotnet_version
            ;;
        --help|-h)
            cat <<EOF
.NET Version Detection Utility

Usage: $0 [OPTIONS]

Options:
  --json, -j           Output all found versions as JSON
  --check, -c [VER]    Check if .NET (or specific version) is available
  --version, -v        Get .NET CLI version
  --help, -h           Show this help message

Examples:
  $0                   # Show summary
  $0 --json            # JSON output
  $0 --check 8         # Check if .NET 8 is available
EOF
            ;;
        *)
            show_dotnet_summary
            ;;
    esac
fi
