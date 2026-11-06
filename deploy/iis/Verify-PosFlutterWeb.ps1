[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^https://')][string]$BaseUrl)
$ErrorActionPreference='Stop'
try {$response=Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/')+'/health') -UseBasicParsing -TimeoutSec 20}catch {throw "Health check failed: $($_.Exception.Message)"}
if($response.StatusCode -ne 200){throw "Health check returned HTTP $($response.StatusCode)."}
Write-Host 'POSFlutter Web health check PASS.'
