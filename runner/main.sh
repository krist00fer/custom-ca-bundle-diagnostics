#!/usr/bin/env bash
# main.sh - Main orchestrator for SSL diagnostics tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/output.sh"
source "${SCRIPT_DIR}/../common/detect-os.sh"
source "${SCRIPT_DIR}/../common/json-utils.sh"

# Global variables
TARGET_URL="${DEFAULT_URL}"
RUN_MODE="interactive"  # interactive, single, all, json
SELECTED_TOOL=""
SELECTED_VERSION=""

# Print usage information
print_usage() {
    cat <<EOF
HTTPS/SSL Connectivity Diagnostics Tool

Usage:
  $(basename "$0") [OPTIONS] [URL]
  $(basename "$0") --tool TOOL [--version VERSION] [URL]

Options:
  -i, --interactive      Run in interactive menu mode (default)
  -a, --all              Check all available tools
  -t, --tool TOOL        Check specific tool (curl, wget, python, dotnet)
  -V, --version VER      Specify version for language tools
  -j, --json             Output results as JSON
  -q, --quiet            Suppress non-essential output
  -v, --verbose          Enable verbose output
  --timeout SEC          Connection timeout (default: ${TIMEOUT_SECONDS}s)
  -h, --help             Show this help message

Examples:
  $(basename "$0")                                    # Interactive menu
  $(basename "$0") https://internal.company.com      # Interactive with custom URL
  $(basename "$0") --all                             # Check all tools
  $(basename "$0") --tool curl                       # Check with curl only
  $(basename "$0") --tool python --version 3.12     # Check with Python 3.12
  $(basename "$0") --json --all                     # JSON output, all tools

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interactive)
                RUN_MODE="interactive"
                shift
                ;;
            -a|--all)
                RUN_MODE="all"
                shift
                ;;
            -t|--tool)
                RUN_MODE="single"
                SELECTED_TOOL="$2"
                shift 2
                ;;
            -V|--version)
                SELECTED_VERSION="$2"
                shift 2
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -q|--quiet)
                VERBOSE=0
                shift
                ;;
            -v|--verbose)
                VERBOSE=2
                shift
                ;;
            --debug)
                VERBOSE=3
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                # Assume it's the URL
                if [[ "$1" == http* ]]; then
                    TARGET_URL="$1"
                else
                    TARGET_URL="https://$1"
                fi
                shift
                ;;
        esac
    done
}

# Run a single tool check and return JSON result
run_check() {
    local tool="$1"
    local version="${2:-}"
    local result=""

    case "$tool" in
        curl)
            result=$(bash "${PROJECT_ROOT}/curl/check.sh" "$TARGET_URL")
            ;;
        wget)
            result=$(bash "${PROJECT_ROOT}/wget/check.sh" "$TARGET_URL")
            ;;
        python)
            if [[ -f "${PROJECT_ROOT}/python/check.sh" ]]; then
                result=$(bash "${PROJECT_ROOT}/python/check.sh" "$TARGET_URL" "$version")
            else
                result=$(create_result_json \
                    "python" \
                    "${version:-system}" \
                    "$TARGET_URL" \
                    "false" \
                    "runtime_missing" \
                    "Python check module not yet implemented" \
                    "1" \
                    "0" \
                    "$(get_platform_json)" \
                    "null")
            fi
            ;;
        dotnet)
            if [[ -f "${PROJECT_ROOT}/dotnet/check.sh" ]]; then
                result=$(bash "${PROJECT_ROOT}/dotnet/check.sh" "$TARGET_URL" "$version")
            else
                result=$(create_result_json \
                    "dotnet" \
                    "${version:-system}" \
                    "$TARGET_URL" \
                    "false" \
                    "runtime_missing" \
                    ".NET check module not yet implemented" \
                    "1" \
                    "0" \
                    "$(get_platform_json)" \
                    "null")
            fi
            ;;
        *)
            log_error "Unknown tool: $tool"
            return 1
            ;;
    esac

    echo "$result"
}

# Run all available checks
run_all_checks() {
    local results=()
    local tools=("curl" "wget")

    # Add Python if available
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        tools+=("python")
    fi

    # Add .NET if available
    if command -v dotnet >/dev/null 2>&1; then
        tools+=("dotnet")
    fi

    log_info "Running checks for: ${tools[*]}"

    for tool in "${tools[@]}"; do
        log_info "Checking $tool..."
        local result
        result=$(run_check "$tool" "")
        results+=("$result")

        if [[ "$JSON_OUTPUT" != true ]]; then
            display_tool_result "$result"
        fi
    done

    if [[ "$JSON_OUTPUT" == true ]]; then
        format_results_json "$TARGET_URL" "${results[@]}"
    else
        display_summary "${results[@]}"
    fi
}

# Run single tool check
run_single_check() {
    local tool="$SELECTED_TOOL"
    local version="$SELECTED_VERSION"

    log_info "Checking $tool${version:+ version $version}..."

    local result
    result=$(run_check "$tool" "$version")

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "$result"
    else
        display_tool_result "$result"

        # Show fix suggestions if failed
        local success
        success=$(echo "$result" | grep -o '"success"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*: *//')
        if [[ "$success" != "true" ]]; then
            local fix_json
            fix_json=$(echo "$result" | grep -o '"fix"[[:space:]]*:[[:space:]]*{[^}]*}' || echo "")
            if [[ -n "$fix_json" && "$fix_json" != *"null"* ]]; then
                display_fix_suggestions "$fix_json" "$tool"
            fi
        fi
    fi
}

# Run interactive mode
run_interactive() {
    # Set the current URL for the menu
    export CURRENT_URL="$TARGET_URL"

    # Source and run the menu
    source "${SCRIPT_DIR}/menu.sh"
    CURRENT_URL="$TARGET_URL"
    start_menu
}

# Main entry point
main() {
    parse_arguments "$@"

    # Ensure output directory exists
    ensure_output_dir

    log_debug "Run mode: $RUN_MODE"
    log_debug "Target URL: $TARGET_URL"
    log_debug "Selected tool: ${SELECTED_TOOL:-none}"
    log_debug "JSON output: $JSON_OUTPUT"

    case "$RUN_MODE" in
        interactive)
            run_interactive
            ;;
        all)
            if [[ "$JSON_OUTPUT" != true ]]; then
                print_header "HTTPS/SSL Connectivity Check"
                print_kv "Target URL" "$TARGET_URL"
                print_kv "Platform" "$(get_platform_string)"
                echo ""
            fi
            run_all_checks
            ;;
        single)
            if [[ -z "$SELECTED_TOOL" ]]; then
                log_error "No tool specified. Use --tool TOOL"
                exit 1
            fi
            if [[ "$JSON_OUTPUT" != true ]]; then
                print_header "HTTPS/SSL Connectivity Check - ${SELECTED_TOOL}"
                print_kv "Target URL" "$TARGET_URL"
                print_kv "Tool" "${SELECTED_TOOL}${SELECTED_VERSION:+ $SELECTED_VERSION}"
                echo ""
            fi
            run_single_check
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
