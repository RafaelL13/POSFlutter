[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $ApkPath,
  [Parameter(Mandatory)] [string] $ExpectedSha256,
  [Parameter(Mandatory)] [string] $ExpectedCertificateSha256,
  [Parameter(Mandatory)] [string] $ExpectedVersionName,
  [int] $ExpectedVersionCode,
  [int] $MinimumSdk = 24,
  [string] $ApkSignerPath = 'apksigner',
  [string] $AdbPath = 'adb'
)
& (Join-Path $PSScriptRoot 'Install-POSFlutterTablet.ps1') @PSBoundParameters
