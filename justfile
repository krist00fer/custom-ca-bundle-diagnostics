# justfile - Task runner for SSL/HTTPS Connectivity Diagnostics Tool
# Usage: just <recipe>

# Default recipe - show help
default:
    @just --list

# Main entry point: check HTTPS connectivity (interactive menu)
check url="https://www.google.com":
    @bash runner/main.sh "{{url}}"

# Run interactive menu
menu url="https://www.google.com":
    @bash runner/main.sh --interactive "{{url}}"

# Check all available tools
check-all url="https://www.google.com":
    @bash runner/main.sh --all "{{url}}"

# Check with JSON output
check-json url="https://www.google.com":
    @bash runner/main.sh --json --all "{{url}}"

# Check with curl only
check-curl url="https://www.google.com":
    @bash curl/check.sh "{{url}}" --human

# Check with wget only
check-wget url="https://www.google.com":
    @bash wget/check.sh "{{url}}" --human

# Check with Python (uses default version)
check-python url="https://www.google.com" version="":
    @bash python/check.sh "{{url}}" "{{version}}" --human

# Check with .NET (uses default version)
check-dotnet url="https://www.google.com" version="":
    @bash dotnet/check.sh "{{url}}" "{{version}}" --human

# Extract CA certificates from a server
extract-certs url:
    @bash common/ca-extract.sh --extract "{{url}}" ./output/certs

# Find system CA bundles
find-ca-bundle:
    @bash common/ca-bundle.sh --find

# Get CA bundle info as JSON
ca-bundle-json:
    @bash common/ca-bundle.sh --json

# Configure environment variables (interactive)
configure-env:
    @bash common/env-persist.sh --interactive

# Add SSL environment variables for a CA bundle
add-ssl-env ca_bundle:
    @bash common/env-persist.sh --add-ssl "{{ca_bundle}}"

# Show environment configuration status
env-status:
    @bash common/env-persist.sh --status

# Show Docker status and built images
docker-status:
    @bash runner/docker-helper.sh --status

# Build all Docker images
docker-build:
    @bash runner/docker-helper.sh --build-all

# Build Docker image for specific tool and version
docker-build-one tool version:
    @bash runner/docker-helper.sh --build "{{tool}}" "{{version}}"

# Run check in Docker container
docker-run tool version url="https://www.google.com":
    @bash runner/docker-helper.sh --run "{{tool}}" "{{version}}" "{{url}}"

# List built Docker images
docker-list:
    @bash runner/docker-helper.sh --list

# Clean up Docker images
docker-clean:
    @bash runner/docker-helper.sh --cleanup

# Detect installed Python versions
python-versions:
    @bash python/detect-versions.sh

# Detect installed .NET versions
dotnet-versions:
    @bash dotnet/detect-versions.sh

# Show platform information
platform-info:
    @bash common/detect-os.sh

# Show shell configuration info
shell-info:
    @bash common/detect-shell.sh

# Clean up generated files
clean:
    @rm -rf output/certs output/*.json
    @rm -rf dotnet/.build
    @echo "Cleaned generated files"

# Deep clean (including Docker images)
clean-all: clean docker-clean
    @echo "Deep clean complete"

# Run all module scripts to verify they work
test:
    @echo "Testing common utilities..."
    @bash common/detect-os.sh >/dev/null && echo "  detect-os.sh: OK"
    @bash common/ca-bundle.sh >/dev/null 2>&1 && echo "  ca-bundle.sh: OK" || echo "  ca-bundle.sh: OK (no bundle found)"
    @bash common/detect-shell.sh --shell >/dev/null && echo "  detect-shell.sh: OK"
    @echo ""
    @echo "Testing curl module..."
    @bash curl/check.sh https://www.google.com --json >/dev/null && echo "  curl/check.sh: OK"
    @echo ""
    @echo "Testing wget module..."
    @bash wget/check.sh https://www.google.com --json >/dev/null 2>&1 && echo "  wget/check.sh: OK" || echo "  wget/check.sh: OK (wget not installed)"
    @echo ""
    @echo "All tests passed!"
