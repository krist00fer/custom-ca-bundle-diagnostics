using System;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Security;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using System.Threading.Tasks;

namespace SslDiagnostics;

/// <summary>
/// SSL/TLS connectivity diagnostic tool for .NET
/// </summary>
public class CheckSsl
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static async Task<int> Main(string[] args)
    {
        var url = args.Length > 0 ? args[0] : "https://www.google.com";
        var timeoutSeconds = args.Length > 1 && int.TryParse(args[1], out var t) ? t : 10;

        var result = await CheckConnection(url, timeoutSeconds);
        Console.WriteLine(JsonSerializer.Serialize(result, JsonOptions));

        return result.Success ? 0 : 1;
    }

    private static async Task<DiagnosticResult> CheckConnection(string url, int timeoutSeconds)
    {
        var result = new DiagnosticResult
        {
            Tool = "dotnet",
            Version = Environment.Version.ToString(),
            Url = url,
            Timestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            Platform = new PlatformInfo
            {
                Os = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "windows" :
                     RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "darwin" : "linux",
                Arch = RuntimeInformation.OSArchitecture.ToString().ToLower(),
                Distro = RuntimeInformation.OSDescription,
                IsWsl = Environment.GetEnvironmentVariable("WSL_DISTRO_NAME") != null
            }
        };

        var stopwatch = Stopwatch.StartNew();

        try
        {
            using var handler = new HttpClientHandler();

            // Store certificate info during validation
            X509Certificate2? serverCert = null;
            X509Chain? certChain = null;
            SslPolicyErrors sslErrors = SslPolicyErrors.None;

            handler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) =>
            {
                serverCert = cert != null ? new X509Certificate2(cert) : null;
                certChain = chain;
                sslErrors = errors;

                // Return false to enforce certificate validation
                // This will cause an exception if there are SSL errors
                return errors == SslPolicyErrors.None;
            };

            using var client = new HttpClient(handler)
            {
                Timeout = TimeSpan.FromSeconds(timeoutSeconds)
            };

            client.DefaultRequestHeaders.UserAgent.ParseAdd("ssl-diagnostics/1.0");

            var response = await client.GetAsync(url);

            stopwatch.Stop();

            result.Success = true;
            result.ErrorType = "none";
            result.ErrorMessage = "";
            result.ErrorCode = 0;
            result.DurationMs = (int)stopwatch.ElapsedMilliseconds;

            // Add certificate details
            if (serverCert != null)
            {
                result.Details = new ResultDetails
                {
                    StatusCode = (int)response.StatusCode,
                    Certificate = new CertificateInfo
                    {
                        Subject = serverCert.Subject,
                        Issuer = serverCert.Issuer,
                        NotBefore = serverCert.NotBefore.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                        NotAfter = serverCert.NotAfter.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                        Thumbprint = serverCert.Thumbprint
                    }
                };
            }
        }
        catch (HttpRequestException ex)
        {
            stopwatch.Stop();
            result.DurationMs = (int)stopwatch.ElapsedMilliseconds;
            result.Success = false;
            result.ErrorCode = 1;

            var innerMessage = ex.InnerException?.Message ?? "";
            var fullMessage = $"{ex.Message} {innerMessage}".ToLower();

            // Classify the error
            if (fullMessage.Contains("ssl") || fullMessage.Contains("certificate") ||
                fullMessage.Contains("tls") || fullMessage.Contains("authentication"))
            {
                result.ErrorType = "ssl_error";
                result.ErrorMessage = $"SSL/TLS error: {ex.Message}";
                if (ex.InnerException != null)
                {
                    result.ErrorMessage += $" - {ex.InnerException.Message}";
                }

                // Generate fix suggestion
                result.Fix = GenerateSslFix();
            }
            else if (fullMessage.Contains("name") || fullMessage.Contains("resolve") ||
                     fullMessage.Contains("dns") || fullMessage.Contains("host"))
            {
                result.ErrorType = "dns_error";
                result.ErrorMessage = $"DNS resolution failed: {ex.Message}";
            }
            else if (fullMessage.Contains("refused") || fullMessage.Contains("reset") ||
                     fullMessage.Contains("unreachable"))
            {
                result.ErrorType = "network_error";
                result.ErrorMessage = $"Network error: {ex.Message}";
            }
            else
            {
                result.ErrorType = "network_error";
                result.ErrorMessage = ex.Message;
            }
        }
        catch (TaskCanceledException)
        {
            stopwatch.Stop();
            result.DurationMs = (int)stopwatch.ElapsedMilliseconds;
            result.Success = false;
            result.ErrorType = "timeout";
            result.ErrorMessage = "Connection timed out";
            result.ErrorCode = 1;
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            result.DurationMs = (int)stopwatch.ElapsedMilliseconds;
            result.Success = false;
            result.ErrorType = "unknown";
            result.ErrorMessage = $"{ex.GetType().Name}: {ex.Message}";
            result.ErrorCode = 1;
        }

        return result;
    }

    private static FixSuggestion GenerateSslFix()
    {
        var fix = new FixSuggestion
        {
            Description = ".NET uses the platform's certificate store. You may need to add your CA certificate to the system trust store.",
            EnvVars = new Dictionary<string, string>
            {
                ["SSL_CERT_FILE"] = "/path/to/ca-bundle.crt",
                ["SSL_CERT_DIR"] = "/path/to/certs/"
            },
            Commands = new List<string>()
        };

        // Platform-specific instructions
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            fix.Commands.Add("# On macOS, add certificate to System Keychain:");
            fix.Commands.Add("sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/cert.crt");
        }
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            fix.Commands.Add("# On Linux (Debian/Ubuntu):");
            fix.Commands.Add("sudo cp /path/to/cert.crt /usr/local/share/ca-certificates/");
            fix.Commands.Add("sudo update-ca-certificates");
            fix.Commands.Add("");
            fix.Commands.Add("# On Linux (RHEL/CentOS):");
            fix.Commands.Add("sudo cp /path/to/cert.crt /etc/pki/ca-trust/source/anchors/");
            fix.Commands.Add("sudo update-ca-trust");
        }
        else
        {
            fix.Commands.Add("# On Windows, import certificate to Trusted Root Certification Authorities:");
            fix.Commands.Add("certutil -addstore -f \"ROOT\" cert.crt");
        }

        // Also mention environment variables
        fix.Commands.Add("");
        fix.Commands.Add("# Alternatively, set environment variables:");
        fix.Commands.Add("export SSL_CERT_FILE=/path/to/ca-bundle.crt");

        return fix;
    }

    #region Result Classes

    public class DiagnosticResult
    {
        public string Tool { get; set; } = "";
        public string Version { get; set; } = "";
        public string Url { get; set; } = "";
        public bool Success { get; set; }
        public string ErrorType { get; set; } = "none";
        public string ErrorMessage { get; set; } = "";
        public int ErrorCode { get; set; }
        public int DurationMs { get; set; }
        public string Timestamp { get; set; } = "";
        public PlatformInfo? Platform { get; set; }
        public FixSuggestion? Fix { get; set; }
        public ResultDetails? Details { get; set; }
    }

    public class PlatformInfo
    {
        public string Os { get; set; } = "";
        public string Arch { get; set; } = "";
        public string Distro { get; set; } = "";
        public bool IsWsl { get; set; }
    }

    public class FixSuggestion
    {
        public string Description { get; set; } = "";
        public Dictionary<string, string> EnvVars { get; set; } = new();
        public List<string> Commands { get; set; } = new();
    }

    public class ResultDetails
    {
        public int StatusCode { get; set; }
        public CertificateInfo? Certificate { get; set; }
    }

    public class CertificateInfo
    {
        public string Subject { get; set; } = "";
        public string Issuer { get; set; } = "";
        public string NotBefore { get; set; } = "";
        public string NotAfter { get; set; } = "";
        public string Thumbprint { get; set; } = "";
    }

    #endregion
}
