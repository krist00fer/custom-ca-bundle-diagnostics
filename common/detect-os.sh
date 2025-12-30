#!/usr/bin/env bash
# detect-os.sh - OS/platform/architecture detection utilities

set -euo pipefail

# Detect the operating system
# Returns: darwin, linux, windows (for WSL)
detect_os() {
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    case "$os" in
        darwin)
            echo "darwin"
            ;;
        linux)
            # Check if running in WSL
            if is_wsl; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        msys*|mingw*|cygwin*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if running inside WSL (Windows Subsystem for Linux)
is_wsl() {
    if [[ -f /proc/version ]]; then
        if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
            return 0
        fi
    fi
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]]; then
        return 0
    fi
    return 1
}

# Detect Linux distribution
# Returns: ubuntu, debian, fedora, centos, rhel, alpine, arch, opensuse, unknown
detect_distro() {
    if [[ "$(detect_os)" != "linux" && "$(detect_os)" != "wsl" ]]; then
        echo "none"
        return
    fi

    local distro="unknown"

    # Check /etc/os-release (modern standard)
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        distro="${ID:-unknown}"
    # Fallback to /etc/lsb-release
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck source=/dev/null
        source /etc/lsb-release
        distro="${DISTRIB_ID:-unknown}"
        distro="$(echo "$distro" | tr '[:upper:]' '[:lower:]')"
    # Fallback to specific files
    elif [[ -f /etc/debian_version ]]; then
        distro="debian"
    elif [[ -f /etc/redhat-release ]]; then
        if grep -qi "centos" /etc/redhat-release; then
            distro="centos"
        elif grep -qi "fedora" /etc/redhat-release; then
            distro="fedora"
        else
            distro="rhel"
        fi
    elif [[ -f /etc/alpine-release ]]; then
        distro="alpine"
    elif [[ -f /etc/arch-release ]]; then
        distro="arch"
    fi

    echo "$distro"
}

# Detect system architecture
# Returns: x86_64, arm64, armv7l, i686, etc.
detect_arch() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armv7)
            echo "armv7"
            ;;
        i686|i386)
            echo "i686"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Get a human-readable platform string
# Returns: "macOS (arm64)", "Linux/Ubuntu (x86_64)", "WSL/Ubuntu (x86_64)", etc.
get_platform_string() {
    local os arch distro result
    os="$(detect_os)"
    arch="$(detect_arch)"

    case "$os" in
        darwin)
            result="macOS"
            ;;
        linux)
            distro="$(detect_distro)"
            if [[ "$distro" != "unknown" && "$distro" != "none" ]]; then
                # Capitalize first letter
                distro="$(echo "${distro:0:1}" | tr '[:lower:]' '[:upper:]')${distro:1}"
                result="Linux/${distro}"
            else
                result="Linux"
            fi
            ;;
        wsl)
            distro="$(detect_distro)"
            if [[ "$distro" != "unknown" && "$distro" != "none" ]]; then
                distro="$(echo "${distro:0:1}" | tr '[:lower:]' '[:upper:]')${distro:1}"
                result="WSL/${distro}"
            else
                result="WSL"
            fi
            ;;
        *)
            result="Unknown OS"
            ;;
    esac

    echo "${result} (${arch})"
}

# Get platform info as JSON
get_platform_json() {
    local os arch distro
    os="$(detect_os)"
    arch="$(detect_arch)"
    distro="$(detect_distro)"

    printf '{"os":"%s","arch":"%s","distro":"%s","is_wsl":%s}' \
        "$os" \
        "$arch" \
        "$distro" \
        "$(is_wsl && echo "true" || echo "false")"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
    [[ "$(id -u)" -eq 0 ]]
}

# Get the home directory (handles sudo correctly)
get_home_dir() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        eval echo "~${SUDO_USER}"
    else
        echo "$HOME"
    fi
}

# If sourced, export functions; if run directly, show info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Platform Detection Results:"
    echo "  OS:       $(detect_os)"
    echo "  Distro:   $(detect_distro)"
    echo "  Arch:     $(detect_arch)"
    echo "  WSL:      $(is_wsl && echo "yes" || echo "no")"
    echo "  Platform: $(get_platform_string)"
    echo ""
    echo "JSON: $(get_platform_json)"
fi
