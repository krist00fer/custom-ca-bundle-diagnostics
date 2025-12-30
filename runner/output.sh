#!/usr/bin/env bash
# output.sh - Output formatting and display utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/../common/json-utils.sh"
source "${SCRIPT_DIR}/../common/error-classify.sh"

# Print a horizontal line
print_separator() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

# Print a header
print_header() {
    local title="$1"
    echo ""
    print_separator "="
    echo -e "${COLOR_BOLD}${title}${COLOR_RESET}"
    print_separator "="
    echo ""
}

# Print a section header
print_section() {
    local title="$1"
    echo ""
    echo -e "${COLOR_BOLD}--- ${title} ---${COLOR_RESET}"
    echo ""
}

# Print a key-value pair
print_kv() {
    local key="$1"
    local value="$2"
    local width="${3:-20}"
    printf "%-${width}s %s\n" "${key}:" "$value"
}

# Print a status indicator
# Usage: print_status "success" "Connection successful"
# Usage: print_status "error" "Connection failed"
print_status() {
    local status="$1"
    local message="$2"

    case "$status" in
        success|ok|pass)
            echo -e "  ${COLOR_GREEN}[PASS]${COLOR_RESET} $message"
            ;;
        error|fail|failed)
            echo -e "  ${COLOR_RED}[FAIL]${COLOR_RESET} $message"
            ;;
        warning|warn)
            echo -e "  ${COLOR_YELLOW}[WARN]${COLOR_RESET} $message"
            ;;
        info)
            echo -e "  ${COLOR_CYAN}[INFO]${COLOR_RESET} $message"
            ;;
        skip|skipped)
            echo -e "  ${COLOR_BLUE}[SKIP]${COLOR_RESET} $message"
            ;;
        *)
            echo "  [$status] $message"
            ;;
    esac
}

# Format and display a single tool result
# Usage: display_tool_result "$json_result"
display_tool_result() {
    local json="$1"

    # Parse JSON (simple extraction without jq)
    local tool version url success error_type error_message

    # Extract values using grep/sed (works without jq)
    # Handle both snake_case (bash modules) and camelCase (.NET module)
    tool=$(echo "$json" | grep -o '"tool"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    version=$(echo "$json" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    url=$(echo "$json" | grep -o '"url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    success=$(echo "$json" | grep -o '"success"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*: *//')
    # Try snake_case first, then camelCase (use || true to prevent set -e from exiting on no match)
    error_type=$(echo "$json" | grep -o '"error_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    if [[ -z "$error_type" ]]; then
        error_type=$(echo "$json" | grep -o '"errorType"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    fi
    error_message=$(echo "$json" | grep -o '"error_message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    if [[ -z "$error_message" ]]; then
        error_message=$(echo "$json" | grep -o '"errorMessage"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    fi

    print_section "${tool} ${version}"

    print_kv "URL" "$url"
    print_kv "Version" "$version"

    if [[ "$success" == "true" ]]; then
        print_status "success" "Connection successful"
    else
        print_status "error" "Connection failed"
        print_kv "Error Type" "$(describe_error_type "$error_type")"
        if [[ -n "$error_message" && "$error_message" != "null" ]]; then
            echo ""
            echo "  Error details:"
            echo "    $error_message" | fold -s -w 60 | sed 's/^/    /'
        fi
    fi
}

# Display fix suggestions
# Usage: display_fix_suggestions "$fix_json" "$tool"
display_fix_suggestions() {
    local fix_json="$1"
    local tool="$2"

    if [[ -z "$fix_json" || "$fix_json" == "null" ]]; then
        return
    fi

    echo ""
    echo -e "${COLOR_YELLOW}Suggested Fix:${COLOR_RESET}"

    # Extract description
    local description
    description=$(echo "$fix_json" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')

    if [[ -n "$description" ]]; then
        echo "  $description"
    fi

    # Show environment variables to set
    echo ""
    echo "  Environment variable(s) to set:"

    # Extract env_vars (simplified parsing)
    local env_vars
    env_vars=$(echo "$fix_json" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/.*{//;s/}.*//')

    if [[ -n "$env_vars" ]]; then
        # Parse key-value pairs
        echo "$env_vars" | tr ',' '\n' | while read -r pair; do
            if [[ -n "$pair" ]]; then
                local key value
                key=$(echo "$pair" | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
                value=$(echo "$pair" | sed 's/.*:.*"\([^"]*\)".*/\1/' | tail -1)
                if [[ -n "$key" && -n "$value" ]]; then
                    echo -e "    ${COLOR_CYAN}export ${key}=\"${value}\"${COLOR_RESET}"
                fi
            fi
        done
    fi
}

# Display a summary of all results
# Usage: display_summary "$result1" "$result2" ...
# Or: display_summary_from_array (reads from RESULTS_ARRAY global)
display_summary() {
    local total=0
    local passed=0
    local failed=0

    # Process all arguments as results
    for result in "$@"; do
        ((total++))
        local success
        success=$(echo "$result" | grep -o '"success"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*: *//')
        if [[ "$success" == "true" ]]; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    print_header "Summary"

    print_kv "Total checks" "$total"
    print_kv "Passed" "$passed"
    print_kv "Failed" "$failed"

    echo ""

    if [[ $failed -eq 0 ]]; then
        echo -e "${COLOR_GREEN}All checks passed!${COLOR_RESET}"
    elif [[ $passed -eq 0 ]]; then
        echo -e "${COLOR_RED}All checks failed. SSL configuration may need attention.${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}Some checks failed. Review the results above for details.${COLOR_RESET}"
    fi
}

# Format results as JSON array
# Usage: format_results_json url result1 result2 ...
format_results_json() {
    local url="$1"
    shift
    local total=0
    local passed=0
    local failed=0
    local timestamp

    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # First pass: count results
    for result in "$@"; do
        ((total++))
        local success
        success=$(echo "$result" | grep -o '"success"[[:space:]]*:[[:space:]]*[a-z]*' | sed 's/.*: *//')
        if [[ "$success" == "true" ]]; then
            ((passed++))
        else
            ((failed++))
        fi
    done

    # Build JSON output
    cat <<EOF
{
  "summary": {
    "url": $(json_string "$url"),
    "total_checks": $total,
    "passed": $passed,
    "failed": $failed,
    "timestamp": $(json_string "$timestamp")
  },
  "results": [
EOF

    local first=true
    for result in "$@"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $result"
    done

    cat <<EOF

  ]
}
EOF
}

# Show a progress spinner
# Usage: show_spinner $pid "Checking..."
show_spinner() {
    local pid=$1
    local message="${2:-Working...}"
    local spin='-\|/'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${COLOR_CYAN}[%c]${COLOR_RESET} %s" "${spin:$i:1}" "$message"
        sleep 0.1
    done
    printf "\r%*s\r" $((${#message} + 5)) ""
}

# Show elapsed time
# Usage: show_elapsed_time $start_time
show_elapsed_time() {
    local start_time=$1
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    if [[ $elapsed -lt 60 ]]; then
        echo "${elapsed}s"
    else
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        echo "${minutes}m ${seconds}s"
    fi
}

# Print boxed message
# Usage: print_box "Title" "Line 1" "Line 2" ...
print_box() {
    local title="$1"
    shift
    local lines=("$@")
    local max_len=${#title}

    # Find max line length
    for line in "${lines[@]}"; do
        if [[ ${#line} -gt $max_len ]]; then
            max_len=${#line}
        fi
    done

    local width=$((max_len + 4))

    # Top border
    printf "+"
    printf '%*s' "$width" '' | tr ' ' '-'
    printf "+\n"

    # Title
    printf "| ${COLOR_BOLD}%-*s${COLOR_RESET} |\n" "$((width-2))" "$title"

    # Separator
    printf "+"
    printf '%*s' "$width" '' | tr ' ' '-'
    printf "+\n"

    # Content lines
    for line in "${lines[@]}"; do
        printf "| %-*s |\n" "$((width-2))" "$line"
    done

    # Bottom border
    printf "+"
    printf '%*s' "$width" '' | tr ' ' '-'
    printf "+\n"
}

# If run directly, show examples
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_header "Output Formatting Examples"

    print_section "Key-Value Pairs"
    print_kv "Tool" "curl"
    print_kv "Version" "8.7.1"
    print_kv "URL" "https://example.com"

    print_section "Status Indicators"
    print_status "success" "curl connected successfully"
    print_status "error" "wget failed to connect"
    print_status "warning" "Python version outdated"
    print_status "skip" "Docker not available"

    print_section "Box Example"
    print_box "Fix Required" \
        "Set the following environment variable:" \
        "" \
        "  export CURL_CA_BUNDLE=/path/to/ca-bundle.crt" \
        "" \
        "Add to ~/.bashrc for persistence"

    print_separator
    echo "Done!"
fi
