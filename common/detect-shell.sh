#!/usr/bin/env bash
# detect-shell.sh - Shell and configuration file detection utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/detect-os.sh"

# Get the user's home directory (handles sudo correctly)
get_home() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        eval echo "~${SUDO_USER}"
    else
        echo "$HOME"
    fi
}

# Detect the current shell
detect_current_shell() {
    local shell_path shell_name

    # Try SHELL environment variable first
    shell_path="${SHELL:-}"

    # Fall back to /etc/passwd if SHELL not set
    if [[ -z "$shell_path" ]]; then
        shell_path=$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7)
    fi

    # Extract shell name from path
    shell_name=$(basename "$shell_path" 2>/dev/null || echo "unknown")

    echo "$shell_name"
}

# Detect the login shell (may differ from current shell)
detect_login_shell() {
    local shell_path

    # Check /etc/passwd
    shell_path=$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f7)

    if [[ -n "$shell_path" ]]; then
        basename "$shell_path"
    else
        detect_current_shell
    fi
}

# Get shell configuration file for interactive sessions
# Returns the most appropriate config file for the given shell
get_shell_config() {
    local shell="${1:-$(detect_current_shell)}"
    local home
    home=$(get_home)

    case "$shell" in
        zsh)
            # zsh load order for interactive: .zshenv, .zprofile (login), .zshrc, .zlogin (login)
            if [[ -f "$home/.zshrc" ]]; then
                echo "$home/.zshrc"
            elif [[ -f "$home/.zshenv" ]]; then
                echo "$home/.zshenv"
            else
                echo "$home/.zshrc"  # Create .zshrc if nothing exists
            fi
            ;;
        bash)
            # bash load order: .bash_profile/.bash_login/.profile (login), .bashrc (non-login interactive)
            if [[ -f "$home/.bashrc" ]]; then
                echo "$home/.bashrc"
            elif [[ -f "$home/.bash_profile" ]]; then
                echo "$home/.bash_profile"
            elif [[ -f "$home/.profile" ]]; then
                echo "$home/.profile"
            else
                echo "$home/.bashrc"  # Create .bashrc if nothing exists
            fi
            ;;
        fish)
            echo "$home/.config/fish/config.fish"
            ;;
        ksh)
            if [[ -f "$home/.kshrc" ]]; then
                echo "$home/.kshrc"
            else
                echo "$home/.profile"
            fi
            ;;
        sh)
            echo "$home/.profile"
            ;;
        *)
            # Default to .profile for unknown shells
            echo "$home/.profile"
            ;;
    esac
}

# Get shell configuration file for login sessions
get_login_config() {
    local shell="${1:-$(detect_current_shell)}"
    local home
    home=$(get_home)

    case "$shell" in
        zsh)
            if [[ -f "$home/.zprofile" ]]; then
                echo "$home/.zprofile"
            elif [[ -f "$home/.zshenv" ]]; then
                echo "$home/.zshenv"
            else
                echo "$home/.zprofile"
            fi
            ;;
        bash)
            if [[ -f "$home/.bash_profile" ]]; then
                echo "$home/.bash_profile"
            elif [[ -f "$home/.bash_login" ]]; then
                echo "$home/.bash_login"
            elif [[ -f "$home/.profile" ]]; then
                echo "$home/.profile"
            else
                echo "$home/.bash_profile"
            fi
            ;;
        fish)
            echo "$home/.config/fish/config.fish"
            ;;
        *)
            echo "$home/.profile"
            ;;
    esac
}

# Get all shell config files that might need updating
get_all_shell_configs() {
    local home
    home=$(get_home)

    local configs=()

    # Check for each common config file
    local files=(
        "$home/.profile"
        "$home/.bash_profile"
        "$home/.bashrc"
        "$home/.zshrc"
        "$home/.zshenv"
        "$home/.zprofile"
        "$home/.config/fish/config.fish"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            configs+=("$file")
        fi
    done

    printf '%s\n' "${configs[@]}"
}

# Check if a file is sourced by another file
# Usage: is_sourced_by ".bashrc" ".bash_profile"
is_sourced_by() {
    local target="$1"
    local source_file="$2"
    local home
    home=$(get_home)

    if [[ ! -f "$home/$source_file" ]]; then
        return 1
    fi

    # Look for source/. commands
    if grep -qE "^[[:space:]]*(source|\.)[[:space:]]+.*${target}" "$home/$source_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Get the recommended config file for adding environment variables
# This considers which files are sourced by others
get_recommended_config() {
    local shell
    shell=$(detect_current_shell)
    local home
    home=$(get_home)

    case "$shell" in
        zsh)
            # For zsh, .zshrc is usually best as it's always loaded for interactive shells
            echo "$home/.zshrc"
            ;;
        bash)
            # For bash, check if .bashrc is sourced by .bash_profile
            if [[ -f "$home/.bash_profile" ]]; then
                if is_sourced_by ".bashrc" ".bash_profile"; then
                    echo "$home/.bashrc"
                else
                    echo "$home/.bash_profile"
                fi
            elif [[ -f "$home/.bashrc" ]]; then
                echo "$home/.bashrc"
            else
                echo "$home/.profile"
            fi
            ;;
        fish)
            mkdir -p "$home/.config/fish"
            echo "$home/.config/fish/config.fish"
            ;;
        *)
            echo "$home/.profile"
            ;;
    esac
}

# Get shell config info as JSON
get_shell_info_json() {
    local shell config login_config all_configs
    shell=$(detect_current_shell)
    config=$(get_shell_config "$shell")
    login_config=$(get_login_config "$shell")

    cat <<EOF
{
  "current_shell": "$shell",
  "login_shell": "$(detect_login_shell)",
  "interactive_config": "$config",
  "login_config": "$login_config",
  "recommended_config": "$(get_recommended_config)",
  "existing_configs": [
$(get_all_shell_configs | while read -r f; do
    echo "    \"$f\","
done | sed '$ s/,$//')
  ]
}
EOF
}

# Show human-readable summary
show_shell_summary() {
    echo "Shell Configuration Detection:"
    echo ""
    echo "  Current Shell:      $(detect_current_shell)"
    echo "  Login Shell:        $(detect_login_shell)"
    echo ""
    echo "  Recommended Config: $(get_recommended_config)"
    echo ""
    echo "  Existing Config Files:"
    get_all_shell_configs | while read -r f; do
        echo "    - $f"
    done

    if [[ $(get_all_shell_configs | wc -l) -eq 0 ]]; then
        echo "    (none found)"
    fi
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --json|-j)
            get_shell_info_json
            ;;
        --config|-c)
            shell="${2:-$(detect_current_shell)}"
            get_shell_config "$shell"
            ;;
        --recommended|-r)
            get_recommended_config
            ;;
        --shell|-s)
            detect_current_shell
            ;;
        --all|-a)
            get_all_shell_configs
            ;;
        --help|-h)
            cat <<EOF
Shell Detection Utility

Usage: $0 [OPTIONS]

Options:
  --json, -j           Output shell info as JSON
  --config, -c [SHELL] Get config file for shell (default: current)
  --recommended, -r    Get recommended config file for env vars
  --shell, -s          Get current shell name
  --all, -a            List all existing config files
  --help, -h           Show this help message

Examples:
  $0                   # Show summary
  $0 --recommended     # Get best file for adding env vars
  $0 --config bash     # Get bash config file
EOF
            ;;
        *)
            show_shell_summary
            ;;
    esac
fi
