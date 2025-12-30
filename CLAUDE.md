# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository contains diagnostic tools to identify and resolve HTTPS connectivity issues in corporate network environments that require custom CA bundles. The tools test connections from multiple programming languages/runtimes and suggest fixes (typically environment variables) when SSL/TLS certificate verification fails.

## Architecture

### Core Concept
Each supported language/tool has its own diagnostic module that:
1. Attempts HTTPS connection to a user-specified URL
2. Detects SSL certificate verification failures
3. Reports the specific error
4. Suggests the correct environment variable(s) or configuration for that language/tool

### Common CA Bundle Environment Variables by Language/Tool

| Language/Tool | Environment Variable(s) |
|---------------|------------------------|
| Node.js | `NODE_EXTRA_CA_CERTS` |
| Python (requests) | `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE` |
| Python (ssl) | `SSL_CERT_FILE`, `SSL_CERT_DIR` |
| Ruby | `SSL_CERT_FILE` |
| Go | `SSL_CERT_FILE`, `SSL_CERT_DIR` |
| curl | `CURL_CA_BUNDLE` |
| wget | `SSL_CERT_FILE` |
| Git | `GIT_SSL_CAINFO`, `GIT_SSL_CAPATH` |
| OpenSSL | `SSL_CERT_FILE`, `SSL_CERT_DIR` |
| Java | `-Djavax.net.ssl.trustStore` (JVM arg) |
| .NET | Platform-specific certificate stores |
| Rust | `SSL_CERT_FILE`, `SSL_CERT_DIR` |
| PHP | `openssl.cafile` (php.ini) or `CURL_CA_BUNDLE` |

### Directory Structure Convention
```
/<language>/           - Language-specific diagnostic tool
/common/               - Shared utilities (if needed)
/runner/               - Main orchestrator that runs all diagnostics
```

## Development Guidelines

- Each language module should be self-contained and runnable independently
- All modules must accept a target URL as input
- Output should be structured (JSON preferred) for aggregation by the runner
- Include both the error detection and the fix suggestion in each module
- Test against both working HTTPS endpoints and endpoints requiring custom CA bundles
