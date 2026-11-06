#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepositoryRoot = 'C:\POSFlutter_Web\POSFlutter_Original',
    [string]$ArtifactsRoot = 'C:\POSFlutter_Web\artifacts',
    [string]$CandidateName = ('POSFlutter_Web_CANDIDATE_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Test-PackageLayout([string]$PackagePath) {
    $required = @(
        'release/PosFlutter.Web.dll', 'release/Infrastructure.dll', 'release/web.config',
        'release/appsettings.json', 'release/wwwroot/css/site.css', 'release/wwwroot/js/site.js',
        'iis/Install-PosFlutterWeb.ps1', 'iis/Preflight-PosFlutterWebLab.ps1',
        'iis/Verify-PosFlutterWeb.ps1', 'MANIFEST.sha256', 'INSTALLATION.md'
    )
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        $missing = @($required | Where-Object { $entries -notcontains $_ })
        Require ($missing.Count -eq 0) ('PACKAGE_LAYOUT_MISSING:' + ($missing -join ','))
    }
    finally { $archive.Dispose() }
}

$project = Join-Path $RepositoryRoot 'web\PosFlutter.Web\PosFlutter.Web.csproj'
$iisSource = Join-Path $RepositoryRoot 'deploy\iis'
Require (Test-Path -LiteralPath $project) 'WEB_PROJECT_MISSING'
Require (Test-Path -LiteralPath $iisSource) 'IIS_SCRIPTS_MISSING'
New-Item -ItemType Directory -Force -Path $ArtifactsRoot | Out-Null

$stage = Join-Path $ArtifactsRoot ($CandidateName + '_stage')
$zip = Join-Path $ArtifactsRoot ($CandidateName + '.zip')
Require (-not (Test-Path -LiteralPath $stage)) 'CANDIDATE_STAGE_ALREADY_EXISTS'
Require (-not (Test-Path -LiteralPath $zip)) 'CANDIDATE_ZIP_ALREADY_EXISTS'

try {
    New-Item -ItemType Directory -Path (Join-Path $stage 'release') | Out-Null
    & dotnet publish $project -c Release --no-restore -o (Join-Path $stage 'release') --nologo
    Require ($LASTEXITCODE -eq 0) 'DOTNET_PUBLISH_FAILED'
    Copy-Item -LiteralPath $iisSource -Destination (Join-Path $stage 'iis') -Recurse
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'docs\CLEAN_INSTALL.md') -Destination (Join-Path $stage 'INSTALLATION.md')

    $secretPattern = '(?i)(password\s*=\s*(?!SET_IN_IIS_OR_SECURE_FILE)|"password"\s*:\s*"(?!SET_IN_IIS_OR_SECURE_FILE))'
    $configText = Get-Content -Raw -LiteralPath (Join-Path $stage 'release\appsettings.json')
    Require (-not ($configText -match $secretPattern)) 'PACKAGE_CONFIGURATION_CONTAINS_SECRET'

    $manifestPath = Join-Path $stage 'MANIFEST.sha256'
    Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.FullName -ne $manifestPath } |
        ForEach-Object {
            $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
            ('{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $relative)
        } | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
    Test-PackageLayout $zip

    $extract = Join-Path ([IO.Path]::GetTempPath()) ('POSFlutterWebPackage_' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $extract
        foreach ($path in @('release\PosFlutter.Web.dll','release\web.config','release\wwwroot\css\site.css','MANIFEST.sha256')) {
            Require (Test-Path -LiteralPath (Join-Path $extract $path)) ('EXTRACTION_VALIDATION_MISSING:' + $path)
        }
    }
    finally { if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force } }

    [pscustomobject]@{
        Package = $zip
        Sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        Layout = 'PASS'
        Extraction = 'PASS'
        DeploymentAction = 'NONE'
    } | Format-List
}
catch {
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    throw
}
