[CmdletBinding()]
param(
  [int] $Port = 8080,
  [string] $SiteName = 'POSFlutterApi',
  [string] $PublicHealthUrl
)
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration
if (-not (Test-Path "IIS:\Sites\$SiteName")) { throw "No existe el sitio IIS $SiteName." }
$response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 "http://127.0.0.1:$Port/health"
if ($response.StatusCode -ne 200) { throw "Health devolvió $($response.StatusCode)." }
if ($PublicHealthUrl) {
  $publicResponse = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 $PublicHealthUrl
  if ($publicResponse.StatusCode -ne 200) { throw "Health público devolvió $($publicResponse.StatusCode)." }
}
Write-Output 'POSFlutter server verification: PASS'
