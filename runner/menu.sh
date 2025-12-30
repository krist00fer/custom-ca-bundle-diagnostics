#!/usr/bin/env bash
# menu.sh - Interactive menu system for SSL diagnostics tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/output.sh"
source "${SCRIPT_DIR}/../common/detect-os.sh"

# Menu state
CURRENT_URL="${DEFAULT_URL}"
MENU_RUNNING=true

# Read a single menu choice with validation
# Usage: read_choice "Enter choice" 1 9
read_choice() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local choice=""

    while true; do
        # Output prompt to stderr so it doesn't get captured by command substitution
        echo -n "$prompt [$min-$max]: " >&2
        read -r choice

        # Handle empty input
        if [[ -z "$choice" ]]; then
            echo "Please enter a choice." >&2
            continue
        fi

        # Handle quit shortcuts
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            echo "quit"
            return
        fi

        # Validate numeric input
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            echo "Please enter a number." >&2
            continue
        fi

        # Validate range
        if [[ "$choice" -lt "$min" || "$choice" -gt "$max" ]]; then
            echo "Please enter a number between $min and $max." >&2
            continue
        fi

        echo "$choice"
        return
    done
}

# Read yes/no confirmation
# Usage: confirm "Are you sure?"
confirm() {
    local prompt="$1"
    local response

    while true; do
        echo -n "$prompt [y/n]: "
        read -r response

        # Convert to lowercase (bash 3.x compatible)
        response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

        case "$response" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please enter 'y' or 'n'."
                ;;
        esac
    done
}

# Read URL from user
read_url() {
    local current="$1"
    local new_url

    echo ""
    echo "Current URL: $current"
    echo -n "Enter new URL (or press Enter to keep current): "
    read -r new_url

    if [[ -z "$new_url" ]]; then
        echo "$current"
    else
        # Auto-prepend https:// if missing
        if [[ ! "$new_url" =~ ^https?:// ]]; then
            new_url="https://$new_url"
        fi
        echo "$new_url"
    fi
}

# Display the main menu header
show_menu_header() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${COLOR_BOLD}╔════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD}║       HTTPS/SSL Connectivity Diagnostics Tool              ║${COLOR_RESET}"
    echo -e "${COLOR_BOLD}╚════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
    echo -e "  Platform: ${COLOR_CYAN}$(get_platform_string)${COLOR_RESET}"
    echo -e "  Target:   ${COLOR_CYAN}${CURRENT_URL}${COLOR_RESET}"
    echo ""
    print_separator "-" 62
}

# Show main menu
show_main_menu() {
    show_menu_header

    echo ""
    echo -e "${COLOR_BOLD}  Basic Tools:${COLOR_RESET}"
    echo "    1) Check with curl"
    echo "    2) Check with wget"
    echo ""
    echo -e "${COLOR_BOLD}  Programming Languages:${COLOR_RESET}"
    echo "    3) Check with Python     (submenu)"
    echo "    4) Check with .NET/C#    (submenu)"
    echo ""
    echo -e "${COLOR_BOLD}  Batch Operations:${COLOR_RESET}"
    echo "    5) Check ALL available tools"
    echo "    6) Check specific version ranges"
    echo ""
    echo -e "${COLOR_BOLD}  Utilities:${COLOR_RESET}"
    echo "    7) Change target URL"
    echo "    8) Extract server CA certificates"
    echo "    9) Find system CA bundles"
    echo "   10) Configure environment variables"
    echo ""
    echo "    0) Exit"
    echo ""
    print_separator "-" 62

    local choice
    choice=$(read_choice "Enter choice" 0 10)

    handle_main_menu_choice "$choice"
}

# Handle main menu selection
handle_main_menu_choice() {
    local choice="$1"

    case "$choice" in
        0|quit)
            MENU_RUNNING=false
            echo ""
            echo "Goodbye!"
            ;;
        1)
            run_tool_check "curl"
            ;;
        2)
            run_tool_check "wget"
            ;;
        3)
            show_python_menu
            ;;
        4)
            show_dotnet_menu
            ;;
        5)
            run_all_checks
            ;;
        6)
            show_batch_menu
            ;;
        7)
            change_url
            ;;
        8)
            extract_certificates
            ;;
        9)
            find_ca_bundles
            ;;
        10)
            configure_env_vars
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

# Python submenu
show_python_menu() {
    while true; do
        show_menu_header

        echo ""
        echo -e "${COLOR_BOLD}  Python SSL Check${COLOR_RESET}"
        echo ""

        # Detect installed Python versions
        local installed_versions=()
        local version_display=""

        for ver in "${PYTHON_VERSIONS[@]}"; do
            if command -v "python${ver}" >/dev/null 2>&1; then
                installed_versions+=("$ver")
            elif [[ "$ver" == "3" ]] && command -v python3 >/dev/null 2>&1; then
                installed_versions+=("3")
            fi
        done

        # Check for default python
        if command -v python >/dev/null 2>&1; then
            local py_version
            py_version=$(python --version 2>&1 | awk '{print $2}' | cut -d. -f1-2)
            echo "    1) Check with system Python ($py_version)"
        else
            echo -e "    1) Check with system Python ${COLOR_YELLOW}(not found)${COLOR_RESET}"
        fi

        # Check for python3
        if command -v python3 >/dev/null 2>&1; then
            local py3_version
            py3_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1-2)
            echo "    2) Check with Python 3 ($py3_version)"
        else
            echo -e "    2) Check with Python 3 ${COLOR_YELLOW}(not found)${COLOR_RESET}"
        fi

        echo ""
        echo -e "${COLOR_BOLD}  Specific Versions:${COLOR_RESET}"
        echo "    3) Check with Python 3.12"
        echo "    4) Check with Python 3.11"
        echo "    5) Check with Python 3.10"
        echo "    6) Check with Python 3.9"
        echo ""
        echo -e "${COLOR_BOLD}  Batch:${COLOR_RESET}"
        echo "    7) Check last 5 Python versions"
        echo "    8) Check ALL available Python versions"
        echo ""
        echo "    9) Back to main menu"
        echo ""
        print_separator "-" 62

        local choice
        choice=$(read_choice "Enter choice" 1 9)

        case "$choice" in
            1)
                run_python_check "python"
                ;;
            2)
                run_python_check "python3"
                ;;
            3)
                run_python_check "python3.12"
                ;;
            4)
                run_python_check "python3.11"
                ;;
            5)
                run_python_check "python3.10"
                ;;
            6)
                run_python_check "python3.9"
                ;;
            7)
                run_python_batch "5"
                ;;
            8)
                run_python_batch "all"
                ;;
            9|quit)
                return
                ;;
        esac

        wait_for_keypress
    done
}

# .NET submenu
show_dotnet_menu() {
    while true; do
        show_menu_header

        echo ""
        echo -e "${COLOR_BOLD}  .NET/C# SSL Check${COLOR_RESET}"
        echo ""

        # Check for dotnet
        if command -v dotnet >/dev/null 2>&1; then
            local dotnet_version
            dotnet_version=$(dotnet --version 2>/dev/null || echo "unknown")
            echo "    1) Check with installed .NET ($dotnet_version)"
        else
            echo -e "    1) Check with installed .NET ${COLOR_YELLOW}(not found)${COLOR_RESET}"
        fi

        echo ""
        echo -e "${COLOR_BOLD}  Specific Versions (via Docker):${COLOR_RESET}"
        echo "    2) Check with .NET 9"
        echo "    3) Check with .NET 8 (LTS)"
        echo "    4) Check with .NET 7"
        echo "    5) Check with .NET 6 (LTS)"
        echo ""
        echo -e "${COLOR_BOLD}  Batch:${COLOR_RESET}"
        echo "    6) Check ALL .NET versions"
        echo ""
        echo "    7) Back to main menu"
        echo ""
        print_separator "-" 62

        local choice
        choice=$(read_choice "Enter choice" 1 7)

        case "$choice" in
            1)
                run_dotnet_check ""
                ;;
            2)
                run_dotnet_check "9"
                ;;
            3)
                run_dotnet_check "8"
                ;;
            4)
                run_dotnet_check "7"
                ;;
            5)
                run_dotnet_check "6"
                ;;
            6)
                run_dotnet_batch
                ;;
            7|quit)
                return
                ;;
        esac

        wait_for_keypress
    done
}

# Batch operations menu
show_batch_menu() {
    show_menu_header

    echo ""
    echo -e "${COLOR_BOLD}  Batch Operations${COLOR_RESET}"
    echo ""
    echo "    1) Check all Python 3.x versions (3.8-3.13)"
    echo "    2) Check all .NET versions (6-9)"
    echo "    3) Check all basic tools (curl, wget)"
    echo "    4) Check everything available"
    echo ""
    echo "    5) Back to main menu"
    echo ""
    print_separator "-" 62

    local choice
    choice=$(read_choice "Enter choice" 1 5)

    case "$choice" in
        1)
            run_python_batch "all"
            ;;
        2)
            run_dotnet_batch
            ;;
        3)
            run_basic_tools_batch
            ;;
        4)
            run_all_checks
            ;;
        5|quit)
            return
            ;;
    esac

    wait_for_keypress
}

# Change target URL
change_url() {
    CURRENT_URL=$(read_url "$CURRENT_URL")
    echo ""
    echo -e "Target URL changed to: ${COLOR_CYAN}${CURRENT_URL}${COLOR_RESET}"
    sleep 1
}

# Extract certificates from server
extract_certificates() {
    echo ""
    echo -e "${COLOR_BOLD}Extracting certificates from ${CURRENT_URL}...${COLOR_RESET}"
    echo ""

    local output_dir="${OUTPUT_DIR}/certs"
    mkdir -p "$output_dir"

    bash "${PROJECT_ROOT}/common/ca-extract.sh" --extract "$CURRENT_URL" "$output_dir"

    echo ""
    echo "Certificates saved to: $output_dir"

    wait_for_keypress
}

# Find system CA bundles
find_ca_bundles() {
    echo ""
    echo -e "${COLOR_BOLD}Finding system CA bundles...${COLOR_RESET}"
    echo ""

    bash "${PROJECT_ROOT}/common/ca-bundle.sh" --find

    wait_for_keypress
}

# Configure environment variables
configure_env_vars() {
    echo ""
    echo -e "${COLOR_BOLD}Environment Variable Configuration${COLOR_RESET}"
    echo ""
    echo "This will help you set up environment variables for SSL/TLS."
    echo ""

    # Find system CA bundle
    local ca_bundle
    ca_bundle=$(bash "${PROJECT_ROOT}/common/ca-bundle.sh" 2>/dev/null || echo "")

    if [[ -n "$ca_bundle" ]]; then
        echo "Found system CA bundle: $ca_bundle"
        echo ""
        echo "Recommended environment variables:"
        echo ""
        echo "  # General SSL"
        echo "  export SSL_CERT_FILE=\"$ca_bundle\""
        echo ""
        echo "  # curl"
        echo "  export CURL_CA_BUNDLE=\"$ca_bundle\""
        echo ""
        echo "  # Python requests"
        echo "  export REQUESTS_CA_BUNDLE=\"$ca_bundle\""
        echo ""
        echo "  # Git"
        echo "  export GIT_SSL_CAINFO=\"$ca_bundle\""
        echo ""

        if confirm "Would you like to add these to your shell config?"; then
            # Detect shell config
            local shell_config=""
            if [[ -f "$HOME/.zshrc" ]]; then
                shell_config="$HOME/.zshrc"
            elif [[ -f "$HOME/.bashrc" ]]; then
                shell_config="$HOME/.bashrc"
            elif [[ -f "$HOME/.profile" ]]; then
                shell_config="$HOME/.profile"
            fi

            if [[ -n "$shell_config" ]]; then
                echo ""
                echo "Adding to $shell_config..."

                # Backup
                cp "$shell_config" "${shell_config}.backup.$(date +%Y%m%d%H%M%S)"

                # Add variables
                {
                    echo ""
                    echo "# SSL/TLS CA Bundle Configuration (added by ssl-diagnostics)"
                    echo "export SSL_CERT_FILE=\"$ca_bundle\""
                    echo "export CURL_CA_BUNDLE=\"$ca_bundle\""
                    echo "export REQUESTS_CA_BUNDLE=\"$ca_bundle\""
                    echo "export GIT_SSL_CAINFO=\"$ca_bundle\""
                } >> "$shell_config"

                echo "Done! Please restart your shell or run: source $shell_config"
            else
                echo "Could not detect shell config file."
            fi
        fi
    else
        echo "No system CA bundle found."
        echo "You may need to extract certificates from your server:"
        echo ""
        echo "  $0 --extract-certs https://your-server.com"
    fi

    wait_for_keypress
}

# Wait for user to press a key
wait_for_keypress() {
    echo ""
    echo -n "Press Enter to continue..."
    read -r
}

# Run a single tool check
run_tool_check() {
    local tool="$1"

    echo ""
    echo -e "${COLOR_BOLD}Running $tool check against ${CURRENT_URL}...${COLOR_RESET}"
    echo ""

    case "$tool" in
        curl)
            bash "${PROJECT_ROOT}/curl/check.sh" "$CURRENT_URL" --human
            ;;
        wget)
            bash "${PROJECT_ROOT}/wget/check.sh" "$CURRENT_URL" --human
            ;;
        *)
            echo "Unknown tool: $tool"
            ;;
    esac

    wait_for_keypress
}

# Run Python check
run_python_check() {
    local python_cmd="$1"

    echo ""
    echo -e "${COLOR_BOLD}Running Python check with ${python_cmd}...${COLOR_RESET}"
    echo ""

    if [[ -f "${PROJECT_ROOT}/python/check.sh" ]]; then
        bash "${PROJECT_ROOT}/python/check.sh" "$CURRENT_URL" "$python_cmd" --human
    else
        echo "Python check module not yet implemented."
    fi
}

# Run Python batch check
run_python_batch() {
    local count="$1"

    echo ""
    echo -e "${COLOR_BOLD}Running batch Python check...${COLOR_RESET}"
    echo ""

    local versions=("${PYTHON_VERSIONS[@]}")
    if [[ "$count" != "all" ]]; then
        versions=("${PYTHON_VERSIONS[@]:0:$count}")
    fi

    for ver in "${versions[@]}"; do
        echo "Checking Python $ver..."
        run_python_check "python${ver}"
        echo ""
    done
}

# Run .NET check
run_dotnet_check() {
    local version="$1"

    echo ""
    echo -e "${COLOR_BOLD}Running .NET check...${COLOR_RESET}"
    echo ""

    if [[ -f "${PROJECT_ROOT}/dotnet/check.sh" ]]; then
        bash "${PROJECT_ROOT}/dotnet/check.sh" "$CURRENT_URL" "$version" --human
    else
        echo ".NET check module not yet implemented."
    fi
}

# Run .NET batch check
run_dotnet_batch() {
    echo ""
    echo -e "${COLOR_BOLD}Running batch .NET check...${COLOR_RESET}"
    echo ""

    for ver in "${DOTNET_VERSIONS[@]}"; do
        echo "Checking .NET $ver..."
        run_dotnet_check "$ver"
        echo ""
    done
}

# Run basic tools batch
run_basic_tools_batch() {
    echo ""
    echo -e "${COLOR_BOLD}Running basic tools check...${COLOR_RESET}"
    echo ""

    run_tool_check "curl"
    run_tool_check "wget"
}

# Run all checks
run_all_checks() {
    echo ""
    echo -e "${COLOR_BOLD}Running ALL available checks...${COLOR_RESET}"
    echo ""

    # Basic tools
    echo "=== Basic Tools ==="
    run_tool_check "curl"
    run_tool_check "wget"

    # Python
    echo ""
    echo "=== Python ==="
    if command -v python3 >/dev/null 2>&1; then
        run_python_check "python3"
    else
        echo "Python 3 not found, skipping."
    fi

    # .NET
    echo ""
    echo "=== .NET ==="
    if command -v dotnet >/dev/null 2>&1; then
        run_dotnet_check ""
    else
        echo ".NET not found, skipping."
    fi

    echo ""
    echo "=== Summary ==="
    echo "All checks completed."

    wait_for_keypress
}

# Start the menu loop
start_menu() {
    MENU_RUNNING=true
    while [[ "$MENU_RUNNING" == true ]]; do
        show_main_menu
    done
}

# Export functions for use by main.sh
export -f show_main_menu
export -f read_choice
export -f confirm
export -f wait_for_keypress

# If run directly, start the menu
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse optional URL argument
    if [[ -n "${1:-}" && "$1" != -* ]]; then
        CURRENT_URL="$1"
    fi

    start_menu
fi
