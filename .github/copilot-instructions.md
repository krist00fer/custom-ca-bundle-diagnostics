# GitHub Copilot Instructions for Custom CA Bundle Diagnostics

## Project Overview

This repository provides diagnostic tools to identify and resolve HTTPS/SSL connectivity issues in corporate network environments that require custom CA bundles. The tools test connections from multiple programming languages/runtimes (curl, wget, Python, .NET) and suggest fixes when SSL/TLS certificate verification fails.

## Architecture

### Core Concept
Each supported language/tool has its own diagnostic module that:
1. Attempts HTTPS connection to a user-specified URL
2. Detects SSL certificate verification failures
3. Reports the specific error
4. Suggests the correct environment variable(s) or configuration for that language/tool

### Directory Structure
```
/<language>/           - Language-specific diagnostic tool
/common/               - Shared utilities
/runner/               - Main orchestrator that runs all diagnostics
```

**Key directories:**
- `curl/` - curl diagnostic module
- `wget/` - wget diagnostic module  
- `python/` - Python diagnostic module with version detection
- `dotnet/` - .NET diagnostic module with version detection
- `common/` - Shared bash utilities (CA bundle detection, cert extraction, error classification, etc.)
- `runner/` - Main entry point with CLI, menu, and output formatting
- `output/` - Generated output files (certs, logs, etc.)

## Technology Stack

- **Primary Language**: Bash (4.0+)
- **Supported Diagnostics**: curl, wget, Python 3.x, .NET SDK
- **Testing Tools**: Python (with requests library), .NET (C# with HttpClient)
- **Optional Tools**: Docker (for version-specific testing), just (task runner)
- **Platforms**: macOS, Linux, WSL

## Coding Standards

### Bash Scripts
- Use `#!/usr/bin/env bash` shebang
- Enable strict mode: `set -euo pipefail`
- Always quote variables: `"$VAR"` not `$VAR`
- Use `$(command)` not backticks for command substitution
- Make scripts executable: `chmod +x script.sh`
- Use `--no-pager` with git commands to avoid interactive output
- Source common utilities using: `source "${PROJECT_ROOT}/common/detect-os.sh"`
  - Set PROJECT_ROOT first: `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`

### Function Conventions
- Use descriptive function names with underscores: `detect_ssl_error`, `extract_certificates`
- Add comment blocks before complex functions
- Return JSON when `--json` flag is used
- Return human-readable output when `--human` flag is used
- Always validate required arguments

### Error Handling
- Use the `common/error-classify.sh` utility to classify SSL/TLS errors
- Provide actionable error messages with suggested fixes
- Always suggest the appropriate environment variable(s) for the tool being diagnosed

### Output Format
- Support both JSON and human-readable output
- JSON output should be valid and parseable
- Use the utilities in `common/json-utils.sh` for JSON generation
- Human output should be clear and include suggested fixes

## Environment Variables by Tool

When suggesting fixes, reference the correct environment variables:

| Tool/Language | Environment Variable(s) |
|---------------|------------------------|
| curl | `CURL_CA_BUNDLE` |
| wget | `SSL_CERT_FILE` |
| Python (requests) | `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE` |
| Python (ssl) | `SSL_CERT_FILE`, `SSL_CERT_DIR` |
| .NET | Platform-specific certificate stores (use `dotnet dev-certs` or system store) |
| Git | `GIT_SSL_CAINFO`, `GIT_SSL_CAPATH` |
| Node.js | `NODE_EXTRA_CA_CERTS` |
| Ruby | `SSL_CERT_FILE` |
| Go | `SSL_CERT_FILE`, `SSL_CERT_DIR` |

## Building and Testing

### Running the Tool

**Interactive mode:**
```bash
./check.sh
# or with just
just check
```

**Command-line mode:**
```bash
# Check specific tool
./check.sh --tool curl https://example.com

# Check all tools
./check.sh --all https://example.com

# JSON output
./check.sh --json --all https://example.com
```

**Using just:**
```bash
# Check all tools
just check-all https://example.com

# Check specific tools
just check-curl https://example.com
just check-python https://example.com
just check-dotnet https://example.com

# Extract certificates
just extract-certs https://example.com
```

### Testing Individual Modules

Each module can be tested independently:
```bash
# Test curl module (no version parameter)
bash curl/check.sh https://example.com --human

# Test Python module (optional version parameter)
bash python/check.sh https://example.com "" --human
# Or with specific version
bash python/check.sh https://example.com "python3.12" --human

# Test .NET module (optional version parameter)
bash dotnet/check.sh https://example.com "" --human
# Or with specific version
bash dotnet/check.sh https://example.com "8" --human
```

**Note**: Python and .NET modules accept an optional second parameter for version. Use an empty string `""` to use the default version, or specify a version like `"python3.12"` or `"8"` for .NET.

### .NET Module Building

The .NET module requires building the C# project:
```bash
cd dotnet/
dotnet build CheckSsl.csproj
dotnet run --project CheckSsl.csproj -- https://example.com
```

### No Automated Tests

Currently, this repository does not have automated unit or integration tests. Testing is done manually by running the diagnostic tools against known HTTPS endpoints (both working and failing).

## Common Development Tasks

### Adding a New Diagnostic Tool

1. Create a new directory: `/<tool_name>/`
2. Add `check.sh` script that:
   - Accepts a URL as first argument
   - Supports `--json` and `--human` flags
   - Outputs structured JSON or human-readable text
   - Detects SSL errors and suggests fixes
3. Add integration to `runner/main.sh` and `runner/menu.sh`
4. Update `justfile` with new recipes
5. Update README.md with the new tool

### Adding a New Utility Script

1. Place in `common/` directory
2. Make executable: `chmod +x common/new-utility.sh`
3. Follow bash coding standards
4. Document usage in comments at top of file
5. Source from other scripts as needed

### Modifying Error Detection

1. Review `common/error-classify.sh` for current error patterns
2. Add new patterns or improve existing ones
3. Ensure suggestions include the correct environment variables
4. Test with various SSL error scenarios

## Important Notes

### Module Independence
- Each diagnostic module (`curl/`, `wget/`, `python/`, `dotnet/`) should be self-contained
- Modules can use shared utilities from `common/` but should not depend on other modules
- All modules must accept a target URL as input
- Output should be structured for aggregation by the runner

### Backward Compatibility
- Maintain backward compatibility with existing command-line interfaces
- Don't break existing scripts that depend on output format
- When adding new features, use optional flags

### Security Considerations
- Never commit actual CA certificates or sensitive credentials
- Generated certificates in `output/` should be in `.gitignore`
- Be careful when suggesting to disable SSL verification (always prefer adding CA bundles)

### Platform Differences
- Test changes on both Linux and macOS when possible
- Use portable bash constructs (avoid GNU-specific features)
- Check `common/detect-os.sh` for OS-specific logic

## Troubleshooting

### Scripts Not Executable
```bash
chmod +x check.sh
chmod +x **/*.sh
```

### .NET Build Failures
```bash
cd dotnet/
dotnet restore
dotnet build
```

### Python Module Issues
Ensure Python 3 and requests library are installed:
```bash
python3 -m pip install requests
```

### Docker Issues
Ensure Docker is running before using Docker-based version testing.

## File Organization

- **Entry Points**: `check.sh`, `justfile`
- **Main Logic**: `runner/main.sh`, `runner/menu.sh`
- **Diagnostic Modules**: `curl/check.sh`, `wget/check.sh`, `python/check.sh`, `dotnet/check.sh`
- **Utilities**: All scripts in `common/`
- **Build Artifacts**: `dotnet/bin/`, `dotnet/obj/` (not committed)
- **Generated Files**: `output/` (not committed)

## Documentation

- Primary documentation: `README.md`
- Developer guidance: `CLAUDE.md` (for Claude Code)
- This file: `.github/copilot-instructions.md` (for GitHub Copilot)

When updating features:
1. Update relevant module scripts
2. Update `README.md` if user-facing changes
3. Update `CLAUDE.md` if architecture changes
4. Keep this file updated with new conventions or patterns

