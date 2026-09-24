[CmdletBinding()]
param([string] $AdbPath = 'adb')
$ErrorActionPreference = 'Stop'
& $AdbPath shell pm path com.posflutter.pos_app
if ($LASTEXITCODE -ne 0) { throw 'POSFlutter no está instalado.' }
& $AdbPath shell am start -n com.posflutter.pos_app/.MainActivity | Out-Null
Write-Output 'POSFlutter tablet verification: PASS'
