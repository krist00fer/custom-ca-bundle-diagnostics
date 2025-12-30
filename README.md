# HTTPS/SSL Connectivity Diagnostics Tool

A comprehensive diagnostic tool to identify and resolve HTTPS/SSL connectivity issues in corporate network environments that require custom CA bundles.

## Quick Start

```bash
# Interactive menu
./check.sh

# Or with just (if installed)
just check

# Check specific URL
just check https://internal.company.com

# Check all available tools
just check-all
```

## Features

- **Multi-tool diagnostics**: Test HTTPS connectivity with curl, wget, Python, and .NET
- **Version-specific testing**: Test different versions of Python and .NET
- **SSL error detection**: Automatically identifies SSL certificate verification failures
- **Fix suggestions**: Provides actionable solutions including environment variables to set
- **CA certificate extraction**: Extract certificates from server chains
- **Environment persistence**: Configure shell environment variables permanently
- **Docker support**: Test with specific runtime versions via Docker containers
- **Cross-platform**: Works on macOS, Linux, and WSL

## Requirements

- Bash 4.0+
- One or more of: curl, wget, Python 3.x, .NET SDK
- Optional: Docker (for version-specific testing)
- Optional: [just](https://just.systems/) command runner

## Installation

```bash
# Clone the repository
git clone https://github.com/your-org/custom-ca-bundle-diagnostics.git
cd custom-ca-bundle-diagnostics

# Make scripts executable
chmod +x check.sh
chmod +x **/*.sh

# Run the tool
./check.sh
```

## Usage

### Interactive Mode

```bash
./check.sh
# or
just check
```

This opens an interactive menu where you can:
- Test individual tools (curl, wget, Python, .NET)
- Test specific versions
- Extract certificates from servers
- Configure environment variables

### Command Line Mode

```bash
# Check all tools against a URL
./check.sh --all https://example.com

# Check specific tool
./check.sh --tool curl https://example.com
./check.sh --tool python --version 3.12 https://example.com

# JSON output (for scripting)
./check.sh --json --all https://example.com
```

### Using Just (Recommended)

```bash
# Interactive menu
just check

# Check all tools
just check-all https://example.com

# Check specific tools
just check-curl https://example.com
just check-python https://example.com
just check-dotnet https://example.com

# Extract certificates from server
just extract-certs https://internal.company.com

# Configure environment variables
just configure-env
```

## Understanding SSL Certificate Errors

Common SSL errors this tool helps diagnose:

| Error | Cause | Solution |
|-------|-------|----------|
| Unable to get local issuer certificate | Corporate proxy/firewall with SSL inspection | Add corporate CA to trust store |
| Self-signed certificate | Server uses self-signed cert | Add certificate to trust store |
| Certificate has expired | Server certificate expired | Contact server administrator |
| Hostname mismatch | Cert issued for different hostname | Check URL or contact admin |

## Environment Variables

The tool can configure these environment variables to fix SSL issues:

| Variable | Used By |
|----------|---------|
| `SSL_CERT_FILE` | Python ssl, OpenSSL, most tools |
| `SSL_CERT_DIR` | Directory of CA certificates |
| `CURL_CA_BUNDLE` | curl |
| `REQUESTS_CA_BUNDLE` | Python requests library |
| `GIT_SSL_CAINFO` | Git |
| `NODE_EXTRA_CA_CERTS` | Node.js |
| `PIP_CERT` | pip |

### Adding to Shell Configuration

```bash
# Interactive configuration
just configure-env

# Or manually add to your CA bundle
just add-ssl-env /path/to/ca-bundle.crt
```

## Docker Support

Test with specific runtime versions using Docker:

```bash
# Build all Docker images
just docker-build

# Run check with specific Python version
just docker-run python 3.12 https://example.com

# Run check with specific .NET version
just docker-run dotnet 8 https://example.com
```

## Extracting CA Certificates

If you need to extract CA certificates from a server (e.g., corporate proxy):

```bash
# Extract certificates
just extract-certs https://internal.company.com

# Certificates saved to ./output/certs/
# Use the chain.pem file as your CA bundle
```

## Project Structure

```
.
├── check.sh           # Main entry point
├── justfile           # Just command definitions
├── runner/            # Main orchestrator
│   ├── main.sh        # CLI entry point
│   ├── menu.sh        # Interactive menu
│   ├── config.sh      # Configuration
│   ├── output.sh      # Output formatting
│   └── docker-helper.sh
├── common/            # Shared utilities
│   ├── detect-os.sh   # Platform detection
│   ├── ca-bundle.sh   # CA bundle finder
│   ├── ca-extract.sh  # Certificate extraction
│   ├── env-persist.sh # Environment variable management
│   └── ...
├── curl/              # curl diagnostic module
├── wget/              # wget diagnostic module
├── python/            # Python diagnostic module
├── dotnet/            # .NET diagnostic module
└── docker/            # Docker images
```

## Troubleshooting

### "curl: command not found"

Install curl:
- macOS: `brew install curl`
- Ubuntu/Debian: `sudo apt-get install curl`
- RHEL/CentOS: `sudo yum install curl`

### "wget: command not found"

Install wget:
- macOS: `brew install wget`
- Ubuntu/Debian: `sudo apt-get install wget`

### "Python not found"

Install Python:
- macOS: `brew install python`
- Or use pyenv: `pyenv install 3.12`

### ".NET not found"

Install .NET:
- macOS: `brew install dotnet`
- Linux: See https://dot.net/download

### Docker issues

Ensure Docker is running:
- macOS/Windows: Start Docker Desktop
- Linux: `sudo systemctl start docker`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `just test`
5. Submit a pull request

## License

MIT License - See LICENSE file for details.
