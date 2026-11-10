[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [string]$Destination,
    [string]$SqlConnection,
    [string]$HostName="localhost",
    [switch]$Apply,
    [switch]$OwnerAuthorized
)

$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $PackagePath)){throw 'Package ZIP was not found.'}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $PackagePath))
try {
    # ZIP writers on Windows may use either separator; compare portable paths.
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
    $required = @('release/PosFlutter.Web.dll','release/Infrastructure.dll','release/web.config','release/appsettings.json','iis/Verify-PosFlutterWeb.ps1')
    $missing = @($required | Where-Object { $entries -notcontains $_ })
    if($missing.Count -gt 0){throw "Package is missing required entries: $($missing -join ', ')"}
}
finally { $archive.Dispose() }

if(-not $Apply){
    [pscustomobject]@{
        PackageValidated = $true
        DeploymentAction = 'NONE (preflight mode)'
        NextStep = 'Obtain written owner authorization, then re-run with -Apply -OwnerAuthorized and a new empty Destination.'
    } | Format-List
    return
}

if(-not $OwnerAuthorized){throw 'Apply mode requires explicit owner authorization: pass -OwnerAuthorized only after it is recorded.'}
if([string]::IsNullOrWhiteSpace($Destination)){throw 'Apply mode requires Destination.'}
if([string]::IsNullOrWhiteSpace($SqlConnection) -or $SqlConnection -match 'SET_IN_IIS_OR_SECURE_FILE'){throw 'Apply mode requires a secure SQL Server connection string.'}
if(Test-Path -LiteralPath $Destination){throw 'Destination must be a new empty laboratory directory; existing files are not overwritten.'}

New-Item -ItemType Directory -Path $Destination | Out-Null
Expand-Archive -LiteralPath $PackagePath -DestinationPath $Destination
$config=Join-Path $Destination 'release\appsettings.json'
$settings=Get-Content $config -Raw | ConvertFrom-Json
if ($null -eq $settings.ConnectionStrings) {
    $settings | Add-Member -NotePropertyName ConnectionStrings -NotePropertyValue ([pscustomobject]@{})
}
$settings.ConnectionStrings | Add-Member -Force -NotePropertyName SqlServer -NotePropertyValue $SqlConnection
$settings | Add-Member -Force -NotePropertyName AllowedHosts -NotePropertyValue $HostName
$settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding UTF8
Write-Host 'Files installed into the new destination. Point the laboratory IIS application PhysicalPath at the release subdirectory, then configure an application pool (No Managed Code) and HTTPS binding separately.'
Write-Host 'Do not copy this laboratory configuration to production.'
