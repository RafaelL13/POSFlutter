#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$SiteName = 'POSFlutterWeb_LAB',
    [string]$ExpectedBinding = '127.0.0.1:8443:127.0.0.1',
    [string]$TargetBinding = '127.0.0.1:8443:localhost',
    [string]$EvidenceRoot = 'C:\POSFlutter_Web\POSFlutter_Original\artifacts\IIS_LAB_HOSTNAME_FIX_20261106'
)

$ErrorActionPreference = 'Stop'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Test-Health {
    try {
        $response = Invoke-WebRequest -Uri 'https://localhost:8443/health' -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

Require $Apply 'APPLY_REQUIRED_NO_CONFIGURATION_CHANGED'
Require ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) 'ELEVATED_ADMINISTRATOR_REQUIRED'

Import-Module WebAdministration -ErrorAction Stop
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

$site = Get-Website -Name $SiteName -ErrorAction Stop
Require ($site.State -eq 'Started') 'LAB_SITE_NOT_STARTED'
$pool = Get-Item ("IIS:\AppPools\" + $site.ApplicationPool)
Require ($pool.State -eq 'Started') 'LAB_APP_POOL_NOT_STARTED'

$matches = @(Get-WebBinding -Name $SiteName | Where-Object {
    $_.protocol -eq 'https' -and $_.bindingInformation -eq $ExpectedBinding
})
Require ($matches.Count -eq 1) 'EXPECTED_LAB_BINDING_NOT_FOUND'
Require (@(Get-WebBinding -Name $SiteName | Where-Object {
    $_.protocol -eq 'https' -and $_.bindingInformation -eq $TargetBinding
}).Count -eq 0) 'TARGET_LAB_BINDING_ALREADY_EXISTS'

$before = [pscustomobject]@{
    Site = $SiteName
    ApplicationPool = $site.ApplicationPool
    Binding = $ExpectedBinding
    TargetBinding = $TargetBinding
    TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
}
$before | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'binding-before.json') -Encoding UTF8

try {
    Set-WebBinding -Name $SiteName -BindingInformation $ExpectedBinding -PropertyName bindingInformation -Value $TargetBinding
    Require (@(Get-WebBinding -Name $SiteName | Where-Object {
        $_.protocol -eq 'https' -and $_.bindingInformation -eq $TargetBinding
    }).Count -eq 1) 'TARGET_LAB_BINDING_NOT_APPLIED'
    # HTTP.sys retains registrations until the owning site reloads. Restart only
    # the explicitly named LAB site, never an application pool or another site.
    Stop-Website -Name $SiteName
    Start-Website -Name $SiteName
    Start-Sleep -Milliseconds 750
    $status = Test-Health
    if ($status -ne 200) { throw ('HEALTHCHECK_FAILED_HTTP_' + $status) }
    [pscustomobject]@{
        Result = 'PASS'
        HealthStatus = $status
        Binding = $TargetBinding
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        ProductionDeployment = $false
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'result.json') -Encoding UTF8
    'IIS_LAB_HOSTNAME_FIX=PASS'
}
catch {
    $failure = $_.Exception.Message
    try {
        Set-WebBinding -Name $SiteName -BindingInformation $TargetBinding -PropertyName bindingInformation -Value $ExpectedBinding
        Stop-Website -Name $SiteName
        Start-Website -Name $SiteName
        $rollback = 'PASS'
    }
    catch {
        $rollback = 'FAIL:' + $_.Exception.Message
    }
    [pscustomobject]@{
        Result = 'FAIL'
        Error = $failure
        Rollback = $rollback
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        ProductionDeployment = $false
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'result.json') -Encoding UTF8
    throw
}
