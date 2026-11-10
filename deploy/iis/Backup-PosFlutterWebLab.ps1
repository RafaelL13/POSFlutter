[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [switch]$Apply,
    [switch]$OwnerAuthorized
)

$ErrorActionPreference = 'Stop'

function Resolve-Directory([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Name does not exist or is not a directory."
    }
    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\\')
}

$source = Resolve-Directory $SourcePath 'SourcePath'
$backup = [IO.Path]::GetFullPath($BackupPath).TrimEnd('\\')
if ($source -eq $backup) { throw 'BackupPath must be different from SourcePath.' }
if (Test-Path -LiteralPath $backup) { throw 'BackupPath must be a new directory; existing backups are never overwritten.' }

$required = @('PosFlutter.Web.dll', 'Infrastructure.dll', 'web.config', 'appsettings.json')
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $source $_) -PathType Leaf) })
if ($missing.Count -gt 0) { throw "SourcePath is not a published POSFlutter Web release: $($missing -join ', ')" }

if (-not $Apply) {
    [pscustomobject]@{
        BackupSource = $source
        BackupDestination = $backup
        BackupAction = 'NONE (plan mode)'
        NextStep = 'After owner authorization, re-run with -Apply -OwnerAuthorized. The destination must remain new.'
    } | Format-List
    return
}

if (-not $OwnerAuthorized) { throw 'Apply mode requires explicit owner authorization: pass -OwnerAuthorized only after it is recorded.' }

New-Item -ItemType Directory -Path $backup | Out-Null
try {
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $backup -Recurse -Force
    }
    $manifest = Get-ChildItem -LiteralPath $backup -File -Recurse | ForEach-Object {
        [pscustomobject]@{
            RelativePath = $_.FullName.Substring($backup.Length).TrimStart('\\')
            Length = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $backup 'backup-manifest.json') -Encoding UTF8
    [pscustomobject]@{ BackupSource = $source; BackupDestination = $backup; Files = @($manifest).Count; BackupAction = 'CREATED' } | Format-List
}
catch {
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
    throw
}
