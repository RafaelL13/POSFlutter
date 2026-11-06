[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ })][string]$PackagePath,
    [string]$ExistingLabPath = 'C:\POSFlutter_Web\LAB_IIS',
    [ValidatePattern('^https://')][string]$ExpectedUrl = 'https://localhost:8443'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$required = @(
    'release/PosFlutter.Web.dll', 'release/Infrastructure.dll', 'release/web.config', 'release/appsettings.json',
    'iis/Install-PosFlutterWeb.ps1', 'iis/Verify-PosFlutterWeb.ps1'
)

$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath))
try {
    # Compress-Archive on Windows may store '\\' while ZIP tooling commonly
    # exposes '/'. Compare canonical relative names so a valid package is not
    # rejected solely because of the host separator.
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $missing = @($required | Where-Object { $entries -notcontains $_ })
    if ($missing.Count -gt 0) { throw "Package is missing required entries: $($missing -join ', ')" }
}
finally { $archive.Dispose() }

$uri = [Uri]$ExpectedUrl
$port = if ($uri.IsDefaultPort) { 443 } else { $uri.Port }
$ssl = & netsh http show sslcert "ipport=127.0.0.1:$port" 2>$null
$listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
$health = 'NOT_TESTED'
try {
    $response = Invoke-WebRequest -Uri ($ExpectedUrl.TrimEnd('/') + '/health') -UseBasicParsing -TimeoutSec 10
    $health = "HTTP_$($response.StatusCode)"
}
catch [System.Net.WebException] {
    if ($_.Exception.Response) { $health = "HTTP_$([int]$_.Exception.Response.StatusCode)" } else { $health = 'UNREACHABLE' }
}
catch { $health = 'UNREACHABLE' }

[pscustomobject]@{
    PackageValidated = $true
    ExistingLabDirectory = Test-Path -LiteralPath $ExistingLabPath
    HttpsCertificateBinding = [bool]($ssl -match "127\.0\.0\.1:$port")
    PortListening = [bool]$listener
    Health = $health
    DeploymentAction = 'NONE (read-only preflight)'
} | Format-List

if ($health -ne 'HTTP_200') {
    Write-Warning 'The existing lab endpoint was not certified by this read-only preflight. Do not replace its files or IIS configuration without explicit authorization.'
}
