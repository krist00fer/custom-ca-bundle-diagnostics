#!/usr/bin/env python3
"""
Python SSL connectivity diagnostic script.

Tests HTTPS connectivity using multiple methods:
- urllib (standard library)
- requests (if available)
- ssl module directly

Outputs JSON results for aggregation.
"""

import json
import ssl
import socket
import sys
import time
import os
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
from datetime import datetime, timezone


def get_ssl_info():
    """Get information about Python's SSL configuration."""
    info = {
        "ssl_version": ssl.OPENSSL_VERSION,
        "ssl_version_info": list(ssl.OPENSSL_VERSION_INFO),
        "default_verify_paths": {},
        "has_sni": hasattr(ssl, 'HAS_SNI') and ssl.HAS_SNI,
        "has_alpn": hasattr(ssl, 'HAS_ALPN') and ssl.HAS_ALPN,
    }

    # Get default certificate paths
    try:
        paths = ssl.get_default_verify_paths()
        info["default_verify_paths"] = {
            "cafile": paths.cafile,
            "capath": paths.capath,
            "openssl_cafile": paths.openssl_cafile,
            "openssl_capath": paths.openssl_capath,
            "openssl_cafile_env": paths.openssl_cafile_env,
            "openssl_capath_env": paths.openssl_capath_env,
        }
    except Exception as e:
        info["default_verify_paths_error"] = str(e)

    return info


def check_with_urllib(url, timeout=10):
    """Test HTTPS connection using urllib."""
    result = {
        "method": "urllib",
        "success": False,
        "error_type": "none",
        "error_message": "",
        "duration_ms": 0,
    }

    start_time = time.time()

    try:
        # Create SSL context with certificate verification
        context = ssl.create_default_context()

        # Make the request
        request = Request(url, headers={"User-Agent": "ssl-diagnostics/1.0"})
        response = urlopen(request, timeout=timeout, context=context)

        # Success
        result["success"] = True
        result["status_code"] = response.getcode()

    except ssl.SSLCertVerificationError as e:
        result["error_type"] = "ssl_error"
        result["error_message"] = f"SSL certificate verification failed: {e}"
        result["ssl_error_code"] = getattr(e, 'verify_code', None)
        result["ssl_error_message"] = getattr(e, 'verify_message', None)

    except ssl.SSLError as e:
        result["error_type"] = "ssl_error"
        result["error_message"] = f"SSL error: {e}"

    except URLError as e:
        if isinstance(e.reason, ssl.SSLError):
            result["error_type"] = "ssl_error"
            result["error_message"] = f"SSL error: {e.reason}"
        elif isinstance(e.reason, socket.timeout):
            result["error_type"] = "timeout"
            result["error_message"] = f"Connection timed out: {e.reason}"
        elif isinstance(e.reason, socket.gaierror):
            result["error_type"] = "dns_error"
            result["error_message"] = f"DNS resolution failed: {e.reason}"
        elif isinstance(e.reason, ConnectionRefusedError):
            result["error_type"] = "network_error"
            result["error_message"] = f"Connection refused: {e.reason}"
        else:
            result["error_type"] = "network_error"
            result["error_message"] = f"URL error: {e.reason}"

    except HTTPError as e:
        # HTTP errors are still "successful" SSL connections
        result["success"] = True
        result["status_code"] = e.code
        result["http_error"] = str(e)

    except socket.timeout:
        result["error_type"] = "timeout"
        result["error_message"] = "Connection timed out"

    except Exception as e:
        result["error_type"] = "unknown"
        result["error_message"] = f"Unexpected error: {type(e).__name__}: {e}"

    result["duration_ms"] = int((time.time() - start_time) * 1000)
    return result


def check_with_requests(url, timeout=10):
    """Test HTTPS connection using requests library (if available)."""
    result = {
        "method": "requests",
        "success": False,
        "error_type": "none",
        "error_message": "",
        "duration_ms": 0,
    }

    try:
        import requests
        from requests.exceptions import SSLError, ConnectionError, Timeout
    except ImportError:
        result["error_type"] = "runtime_missing"
        result["error_message"] = "requests library not installed"
        return result

    start_time = time.time()

    try:
        response = requests.get(
            url,
            timeout=timeout,
            verify=True,
            headers={"User-Agent": "ssl-diagnostics/1.0"}
        )
        result["success"] = True
        result["status_code"] = response.status_code

    except SSLError as e:
        result["error_type"] = "ssl_error"
        result["error_message"] = f"SSL error: {e}"

    except ConnectionError as e:
        # Check if it's an SSL error wrapped in ConnectionError
        error_str = str(e).lower()
        if "ssl" in error_str or "certificate" in error_str:
            result["error_type"] = "ssl_error"
        elif "name" in error_str or "resolve" in error_str:
            result["error_type"] = "dns_error"
        else:
            result["error_type"] = "network_error"
        result["error_message"] = f"Connection error: {e}"

    except Timeout:
        result["error_type"] = "timeout"
        result["error_message"] = "Connection timed out"

    except Exception as e:
        result["error_type"] = "unknown"
        result["error_message"] = f"Unexpected error: {type(e).__name__}: {e}"

    result["duration_ms"] = int((time.time() - start_time) * 1000)
    return result


def check_with_ssl_socket(url, timeout=10):
    """Test SSL connection directly using ssl module."""
    result = {
        "method": "ssl_socket",
        "success": False,
        "error_type": "none",
        "error_message": "",
        "duration_ms": 0,
        "certificate": None,
    }

    # Parse URL
    from urllib.parse import urlparse
    parsed = urlparse(url)
    host = parsed.hostname
    port = parsed.port or 443

    start_time = time.time()

    try:
        # Create SSL context
        context = ssl.create_default_context()

        # Connect
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with context.wrap_socket(sock, server_hostname=host) as ssock:
                result["success"] = True
                result["ssl_version"] = ssock.version()
                result["cipher"] = ssock.cipher()

                # Get certificate info
                cert = ssock.getpeercert()
                if cert:
                    result["certificate"] = {
                        "subject": dict(x[0] for x in cert.get("subject", [])),
                        "issuer": dict(x[0] for x in cert.get("issuer", [])),
                        "notBefore": cert.get("notBefore"),
                        "notAfter": cert.get("notAfter"),
                    }

    except ssl.SSLCertVerificationError as e:
        result["error_type"] = "ssl_error"
        result["error_message"] = f"Certificate verification failed: {e}"
        result["ssl_error_code"] = getattr(e, 'verify_code', None)

    except ssl.SSLError as e:
        result["error_type"] = "ssl_error"
        result["error_message"] = f"SSL error: {e}"

    except socket.gaierror as e:
        result["error_type"] = "dns_error"
        result["error_message"] = f"DNS resolution failed: {e}"

    except socket.timeout:
        result["error_type"] = "timeout"
        result["error_message"] = "Connection timed out"

    except ConnectionRefusedError as e:
        result["error_type"] = "network_error"
        result["error_message"] = f"Connection refused: {e}"

    except Exception as e:
        result["error_type"] = "unknown"
        result["error_message"] = f"Unexpected error: {type(e).__name__}: {e}"

    result["duration_ms"] = int((time.time() - start_time) * 1000)
    return result


def generate_fix_suggestion(error_type, method):
    """Generate fix suggestions based on error type."""
    if error_type != "ssl_error":
        return None

    fix = {
        "description": "",
        "env_vars": {},
        "commands": [],
    }

    if method in ("urllib", "ssl_socket"):
        fix["description"] = "Set SSL_CERT_FILE environment variable to your CA bundle"
        fix["env_vars"]["SSL_CERT_FILE"] = "/path/to/ca-bundle.crt"
        fix["commands"] = [
            "export SSL_CERT_FILE=/path/to/ca-bundle.crt",
            "# Or set SSL_CERT_DIR for a directory of certificates",
            "export SSL_CERT_DIR=/path/to/certs/",
        ]
    elif method == "requests":
        fix["description"] = "Set REQUESTS_CA_BUNDLE environment variable to your CA bundle"
        fix["env_vars"]["REQUESTS_CA_BUNDLE"] = "/path/to/ca-bundle.crt"
        fix["commands"] = [
            "export REQUESTS_CA_BUNDLE=/path/to/ca-bundle.crt",
            "# Or use CURL_CA_BUNDLE which requests also respects",
            "export CURL_CA_BUNDLE=/path/to/ca-bundle.crt",
        ]

    # Try to find system CA bundle
    ca_paths = [
        "/etc/ssl/cert.pem",
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/pki/tls/certs/ca-bundle.crt",
    ]
    for path in ca_paths:
        if os.path.exists(path):
            fix["env_vars"] = {k: path for k in fix["env_vars"]}
            fix["commands"] = [cmd.replace("/path/to/ca-bundle.crt", path)
                               for cmd in fix["commands"]]
            break

    return fix


def main():
    """Main entry point."""
    import platform

    # Parse arguments
    url = sys.argv[1] if len(sys.argv) > 1 else "https://www.google.com"
    timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    # Get Python and platform info
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"

    # Run checks
    urllib_result = check_with_urllib(url, timeout)
    requests_result = check_with_requests(url, timeout)
    ssl_result = check_with_ssl_socket(url, timeout)

    # Determine overall success - ALL methods must succeed (or be unavailable)
    # If any method fails with an SSL error, overall status is FAILED
    all_results = [urllib_result, requests_result, ssl_result]
    
    # Filter out runtime_missing errors (library not installed)
    testable_results = [r for r in all_results if r["error_type"] != "runtime_missing"]
    
    # Success only if all testable methods succeeded
    success = all(r["success"] for r in testable_results)
    
    # Determine primary error from the first failing method
    primary_result = urllib_result
    failed_results = [r for r in testable_results if not r["success"]]
    
    if failed_results:
        primary_result = failed_results[0]  # Use first failure as primary
    
    error_type = primary_result["error_type"]
    error_message = primary_result["error_message"]
    duration_ms = primary_result["duration_ms"]

    # Generate fixes for each failed method
    fixes = {}
    for result in all_results:
        method = result["method"]
        if not result["success"] and result["error_type"] == "ssl_error":
            fix_suggestion = generate_fix_suggestion(result["error_type"], method)
            if fix_suggestion:
                fixes[method] = fix_suggestion
    
    # Use the first fix as the primary one for backward compatibility
    fix = fixes.get("urllib") or fixes.get("requests") or fixes.get("ssl_socket") or None

    # Build output
    output = {
        "tool": "python",
        "version": python_version,
        "url": url,
        "success": success,
        "error_type": error_type,
        "error_message": error_message,
        "error_code": 0 if success else 1,
        "duration_ms": duration_ms,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "platform": {
            "os": platform.system().lower(),
            "arch": platform.machine(),
            "distro": platform.platform(),
            "is_wsl": "microsoft" in platform.release().lower(),
        },
        "fix": fix,
        "fixes": fixes,  # Include all method-specific fixes
        "details": {
            "ssl_info": get_ssl_info(),
            "urllib_result": urllib_result,
            "requests_result": requests_result,
            "ssl_socket_result": ssl_result,
        }
    }

    # Output JSON
    print(json.dumps(output, indent=2, default=str))

    # Return appropriate exit code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
