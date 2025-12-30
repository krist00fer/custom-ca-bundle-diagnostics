#!/usr/bin/env bash
# check.sh - Main entry point for SSL/HTTPS Connectivity Diagnostics Tool
#
# Usage:
#   ./check.sh                           # Interactive menu
#   ./check.sh https://example.com       # Interactive with custom URL
#   ./check.sh --all                     # Check all tools
#   ./check.sh --tool curl               # Check specific tool
#   ./check.sh --help                    # Show help
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make all scripts executable
find "$SCRIPT_DIR" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

# Run the main orchestrator
exec bash "${SCRIPT_DIR}/runner/main.sh" "$@"
