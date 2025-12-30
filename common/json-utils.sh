#!/usr/bin/env bash
# json-utils.sh - Pure bash JSON utilities (no external dependencies)

set -euo pipefail

# Escape a string for JSON
# Usage: json_escape "string with \"quotes\" and \n newlines"
json_escape() {
    local str="$1"
    # Escape backslashes first, then other special characters
    str="${str//\\/\\\\}"     # Backslash
    str="${str//\"/\\\"}"     # Double quote
    str="${str//$'\n'/\\n}"   # Newline
    str="${str//$'\r'/\\r}"   # Carriage return
    str="${str//$'\t'/\\t}"   # Tab
    # Remove other control characters
    str="$(echo "$str" | tr -d '\000-\011\013-\037')"
    echo "$str"
}

# Create a JSON string value (quoted and escaped)
# Usage: json_string "value"
json_string() {
    printf '"%s"' "$(json_escape "$1")"
}

# Create a JSON number value (unquoted)
# Usage: json_number 42
json_number() {
    local num="$1"
    # Validate it's actually a number
    if [[ "$num" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "$num"
    else
        echo "0"
    fi
}

# Create a JSON boolean value
# Usage: json_bool true
# Usage: json_bool false
json_bool() {
    local val
    val=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$val" in
        true|1|yes)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Create a JSON null value
json_null() {
    echo "null"
}

# Create a JSON key-value pair
# Usage: json_kv "key" "value" [type]
# Types: string (default), number, bool, raw (for nested objects/arrays)
json_kv() {
    local key="$1"
    local value="$2"
    local type="${3:-string}"

    printf '"%s":' "$key"
    case "$type" in
        string)
            json_string "$value"
            ;;
        number)
            json_number "$value"
            ;;
        bool)
            json_bool "$value"
            ;;
        raw)
            # Raw JSON (object, array, or already formatted)
            echo -n "$value"
            ;;
        null)
            json_null
            ;;
    esac
}

# Create a JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2" ...
# For non-string values, prefix with type: json_object "count:number" "42" "active:bool" "true"
json_object() {
    local first=true
    local key value type

    echo -n "{"
    while [[ $# -gt 0 ]]; do
        key="$1"
        value="${2:-}"
        type="string"

        # Check for type annotation (key:type)
        if [[ "$key" == *:* ]]; then
            type="${key##*:}"
            key="${key%:*}"
        fi

        if [[ "$first" == true ]]; then
            first=false
        else
            echo -n ","
        fi

        json_kv "$key" "$value" "$type"
        shift 2 || break
    done
    echo -n "}"
}

# Create a JSON array from values
# Usage: json_array "value1" "value2" "value3"
# For non-string values, prefix with type: json_array "string:hello" "number:42"
json_array() {
    local first=true
    local value type

    echo -n "["
    for item in "$@"; do
        type="string"
        value="$item"

        # Check for type annotation (type:value)
        if [[ "$item" == *:* ]]; then
            local prefix="${item%%:*}"
            if [[ "$prefix" =~ ^(string|number|bool|raw|null)$ ]]; then
                type="$prefix"
                value="${item#*:}"
            fi
        fi

        if [[ "$first" == true ]]; then
            first=false
        else
            echo -n ","
        fi

        case "$type" in
            string)
                json_string "$value"
                ;;
            number)
                json_number "$value"
                ;;
            bool)
                json_bool "$value"
                ;;
            raw)
                echo -n "$value"
                ;;
            null)
                json_null
                ;;
        esac
    done
    echo -n "]"
}

# Create the standard diagnostic result JSON
# Usage: create_result_json tool version url success error_type error_message error_code platform_json fix_json
create_result_json() {
    local tool="$1"
    local version="$2"
    local url="$3"
    local success="$4"
    local error_type="$5"
    local error_message="$6"
    local error_code="$7"
    local duration_ms="$8"
    local platform_json="$9"
    local fix_json="${10:-null}"
    local timestamp

    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    cat <<EOF
{
  "tool": $(json_string "$tool"),
  "version": $(json_string "$version"),
  "url": $(json_string "$url"),
  "success": $(json_bool "$success"),
  "error_type": $(json_string "$error_type"),
  "error_message": $(json_string "$error_message"),
  "error_code": $(json_number "$error_code"),
  "duration_ms": $(json_number "$duration_ms"),
  "timestamp": $(json_string "$timestamp"),
  "platform": ${platform_json},
  "fix": ${fix_json}
}
EOF
}

# Create a fix suggestion JSON object
# Usage: create_fix_json "description" "env_vars_json" "commands_array_json"
create_fix_json() {
    local description="$1"
    local env_vars_json="${2:-{}}"
    local commands_json="${3:-[]}"

    cat <<EOF
{
    "description": $(json_string "$description"),
    "env_vars": ${env_vars_json},
    "commands": ${commands_json}
}
EOF
}

# Pretty print JSON (basic indentation)
# Usage: echo '{"a":1}' | json_pretty
json_pretty() {
    local indent=0
    local char prev_char=""
    local in_string=false
    local escape_next=false

    while IFS= read -r -n1 char; do
        if [[ "$escape_next" == true ]]; then
            echo -n "$char"
            escape_next=false
            prev_char="$char"
            continue
        fi

        if [[ "$char" == "\\" && "$in_string" == true ]]; then
            echo -n "$char"
            escape_next=true
            prev_char="$char"
            continue
        fi

        if [[ "$char" == '"' ]]; then
            in_string=$([[ "$in_string" == true ]] && echo false || echo true)
            echo -n "$char"
            prev_char="$char"
            continue
        fi

        if [[ "$in_string" == true ]]; then
            echo -n "$char"
            prev_char="$char"
            continue
        fi

        case "$char" in
            '{' | '[')
                echo -n "$char"
                ((indent+=2))
                echo ""
                printf '%*s' "$indent" ""
                ;;
            '}' | ']')
                ((indent-=2))
                echo ""
                printf '%*s' "$indent" ""
                echo -n "$char"
                ;;
            ',')
                echo -n "$char"
                echo ""
                printf '%*s' "$indent" ""
                ;;
            ':')
                echo -n ": "
                ;;
            ' ' | $'\n' | $'\t')
                # Skip whitespace
                ;;
            *)
                echo -n "$char"
                ;;
        esac
        prev_char="$char"
    done
    echo ""
}

# If run directly, show examples
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "JSON Utilities Examples:"
    echo ""

    echo "1. Simple object:"
    json_object "name" "test" "version" "1.0" "count:number" "42" "active:bool" "true"
    echo ""

    echo ""
    echo "2. Array:"
    json_array "one" "two" "three"
    echo ""

    echo ""
    echo "3. Nested structure:"
    platform=$(json_object "os" "darwin" "arch" "arm64")
    json_object "tool" "curl" "success:bool" "true" "platform:raw" "$platform"
    echo ""

    echo ""
    echo "4. Full diagnostic result:"
    platform_json='{"os":"darwin","arch":"arm64","distro":"none","is_wsl":false}'
    fix_json=$(create_fix_json "Set CURL_CA_BUNDLE to your CA bundle" '{"CURL_CA_BUNDLE":"/etc/ssl/cert.pem"}' '["export CURL_CA_BUNDLE=/etc/ssl/cert.pem"]')
    create_result_json "curl" "8.7.1" "https://example.com" "false" "ssl_error" "certificate verify failed" "60" "150" "$platform_json" "$fix_json"
fi
