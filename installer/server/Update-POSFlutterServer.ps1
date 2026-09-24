[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $SourceRoot,
  [securestring] $SqlConnectionString,
  [securestring] $JwtSigningKey,
  [string] $InstallPath = 'C:\Apps\POSFlutter\Api',
  [string] $AppPoolName = 'POSFlutterApiPool',
  [int] $Port = 8080
)
$parameters = @{}
foreach ($key in $PSBoundParameters.Keys) { $parameters[$key] = $PSBoundParameters[$key] }
$parameters.Upgrade = $true
& (Join-Path $PSScriptRoot 'Install-POSFlutterServer.ps1') @parameters
