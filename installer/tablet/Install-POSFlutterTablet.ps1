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
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ApkPath)) { throw 'No existe el APK indicado.' }
$actual = (Get-FileHash $ApkPath -Algorithm SHA256).Hash
if ($actual -ne $ExpectedSha256.ToUpperInvariant()) { throw 'El SHA256 del APK no coincide.' }
& $ApkSignerPath verify --verbose --print-certs $ApkPath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'La verificación de firma APK falló.' }
$certificate = @(& $ApkSignerPath verify --print-certs $ApkPath | Select-String 'certificate SHA-256 digest:') | Select-Object -First 1
if ($null -eq $certificate -or $certificate.ToString().Split(':')[-1].Trim().Replace(':', '') -ne $ExpectedCertificateSha256.ToUpperInvariant().Replace(':', '')) { throw 'El certificado del APK no coincide.' }
& $AdbPath devices
$devices = @(& $AdbPath devices | Select-String '\sdevice$')
if ($devices.Count -ne 1) { throw 'Conecta exactamente una tablet autorizada.' }
& $AdbPath shell getprop ro.build.version.sdk | Out-Null
$deviceSdk = [int] (@(& $AdbPath shell getprop ro.build.version.sdk) | Select-Object -First 1)
if ($deviceSdk -lt $MinimumSdk) { throw "La tablet tiene API $deviceSdk; se requiere al menos API $MinimumSdk." }
if ($PSCmdlet.ShouldProcess($ApkPath, 'Instalar APK POSFlutter')) { & $AdbPath install -r $ApkPath }
if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación Android.' }
& $AdbPath shell dumpsys package com.posflutter.pos_app | Select-String 'versionName=|versionCode=' | Out-Host
$installed = @(& $AdbPath shell dumpsys package com.posflutter.pos_app)
if (-not ($installed -match [regex]::Escape("versionName=$ExpectedVersionName"))) { throw 'La versión instalada no coincide.' }
if ($ExpectedVersionCode -gt 0 -and -not ($installed -match "versionCode=$ExpectedVersionCode")) { throw 'El versionCode instalado no coincide.' }
& $AdbPath shell monkey -p com.posflutter.pos_app 1 | Out-Null
Write-Output 'POSFlutter tablet installation: PASS'
