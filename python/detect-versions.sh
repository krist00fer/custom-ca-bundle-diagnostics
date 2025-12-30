#!/usr/bin/env bash
# detect-versions.sh - Detect installed Python versions

set -euo pipefail

# Known Python version patterns to search for
PYTHON_VERSIONS=("3.13" "3.12" "3.11" "3.10" "3.9" "3.8" "3.7")

# Detect all installed Python versions
# Returns JSON array of found versions
detect_python_versions() {
    local found_versions=()
    local checked_paths=()

    # Check common python commands
    local commands=(
        "python"
        "python3"
    )

    # Add version-specific commands
    for ver in "${PYTHON_VERSIONS[@]}"; do
        commands+=("python${ver}")
        commands+=("python${ver%.*}")  # e.g., python3 for python3.12
    done

    # Check pyenv versions if pyenv is available
    if command -v pyenv >/dev/null 2>&1; then
        while IFS= read -r ver; do
            if [[ "$ver" =~ ^[0-9]+\.[0-9]+ ]]; then
                commands+=("pyenv:$ver")
            fi
        done < <(pyenv versions --bare 2>/dev/null || true)
    fi

    # Check each command
    for cmd in "${commands[@]}"; do
        local python_path version_str

        # Handle pyenv versions differently
        if [[ "$cmd" == pyenv:* ]]; then
            local pyenv_ver="${cmd#pyenv:}"
            python_path="$(pyenv prefix "$pyenv_ver" 2>/dev/null)/bin/python"
            if [[ ! -x "$python_path" ]]; then
                continue
            fi
        else
            python_path=$(command -v "$cmd" 2>/dev/null || echo "")
            if [[ -z "$python_path" ]]; then
                continue
            fi
        fi

        # Get real path to avoid duplicates
        local real_path
        real_path=$(readlink -f "$python_path" 2>/dev/null || echo "$python_path")

        # Skip if we've already checked this path
        local already_checked=false
        for checked in "${checked_paths[@]:-}"; do
            if [[ "$checked" == "$real_path" ]]; then
                already_checked=true
                break
            fi
        done

        if [[ "$already_checked" == true ]]; then
            continue
        fi
        checked_paths+=("$real_path")

        # Get version string
        version_str=$("$python_path" --version 2>&1 | awk '{print $2}')

        if [[ -z "$version_str" ]]; then
            continue
        fi

        # Extract major.minor version
        local major_minor
        major_minor=$(echo "$version_str" | cut -d. -f1-2)

        # Only include Python 3.x
        if [[ ! "$major_minor" =~ ^3\. ]]; then
            continue
        fi

        # Build version info JSON
        local version_info
        version_info=$(cat <<EOF
{
  "version": "$version_str",
  "major_minor": "$major_minor",
  "path": "$python_path",
  "real_path": "$real_path",
  "command": "$cmd"
}
EOF
)
        found_versions+=("$version_info")
    done

    # Output as JSON array
    echo "["
    local first=true
    for ver_json in "${found_versions[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi
        echo "$ver_json"
    done
    echo "]"
}

# Get the path to a specific Python version
# Usage: get_python_path "3.12"
get_python_path() {
    local target_version="$1"
    local python_path=""

    # Try exact version first
    if command -v "python${target_version}" >/dev/null 2>&1; then
        python_path=$(command -v "python${target_version}")
    # Try major.minor without patch
    elif command -v "python${target_version%.*}" >/dev/null 2>&1; then
        local candidate
        candidate=$(command -v "python${target_version%.*}")
        local version
        version=$("$candidate" --version 2>&1 | awk '{print $2}')
        if [[ "$version" == "${target_version}"* ]]; then
            python_path="$candidate"
        fi
    # Try pyenv
    elif command -v pyenv >/dev/null 2>&1; then
        local pyenv_versions
        pyenv_versions=$(pyenv versions --bare 2>/dev/null || true)
        for ver in $pyenv_versions; do
            if [[ "$ver" == "${target_version}"* ]]; then
                python_path="$(pyenv prefix "$ver" 2>/dev/null)/bin/python"
                break
            fi
        done
    fi

    echo "$python_path"
}

# Check if a specific Python version is available
# Usage: is_python_available "3.12"
is_python_available() {
    local target_version="$1"
    local path
    path=$(get_python_path "$target_version")
    [[ -n "$path" && -x "$path" ]]
}

# Get human-readable summary of installed Python versions
show_python_summary() {
    echo "Installed Python Versions:"
    echo ""

    local found=false

    # Check python command
    if command -v python >/dev/null 2>&1; then
        local version
        version=$(python --version 2>&1 | awk '{print $2}')
        echo "  python:   $version ($(command -v python))"
        found=true
    fi

    # Check python3 command
    if command -v python3 >/dev/null 2>&1; then
        local version
        version=$(python3 --version 2>&1 | awk '{print $2}')
        echo "  python3:  $version ($(command -v python3))"
        found=true
    fi

    # Check version-specific commands
    for ver in "${PYTHON_VERSIONS[@]}"; do
        if command -v "python${ver}" >/dev/null 2>&1; then
            local version path
            path=$(command -v "python${ver}")
            version=$("$path" --version 2>&1 | awk '{print $2}')
            echo "  python${ver}: $version ($path)"
            found=true
        fi
    done

    # Check pyenv
    if command -v pyenv >/dev/null 2>&1; then
        echo ""
        echo "  pyenv versions:"
        pyenv versions --bare 2>/dev/null | while read -r ver; do
            echo "    - $ver"
        done
    fi

    if [[ "$found" == false ]]; then
        echo "  No Python installations found"
    fi
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --json|-j)
            detect_python_versions
            ;;
        --path|-p)
            version="${2:-3}"
            path=$(get_python_path "$version")
            if [[ -n "$path" ]]; then
                echo "$path"
            else
                echo "Python $version not found" >&2
                exit 1
            fi
            ;;
        --check|-c)
            version="${2:-3}"
            if is_python_available "$version"; then
                echo "Python $version is available"
                exit 0
            else
                echo "Python $version is not available"
                exit 1
            fi
            ;;
        --help|-h)
            cat <<EOF
Python Version Detection Utility

Usage: $0 [OPTIONS]

Options:
  --json, -j           Output all found versions as JSON
  --path, -p VERSION   Get path to specific Python version
  --check, -c VERSION  Check if specific version is available
  --help, -h           Show this help message

Examples:
  $0                   # Show summary
  $0 --json            # JSON output
  $0 --path 3.12       # Get path to Python 3.12
  $0 --check 3.11      # Check if Python 3.11 is available
EOF
            ;;
        *)
            show_python_summary
            ;;
    esac
fi
