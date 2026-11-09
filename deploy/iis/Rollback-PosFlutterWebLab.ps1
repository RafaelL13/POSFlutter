[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$RestoreDestination,
    [switch]$Apply,
    [switch]$OwnerAuthorized
)

$ErrorActionPreference = 'Stop'

function Resolve-Directory([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Name does not exist or is not a directory." }
    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd('\\')
}

$backup = Resolve-Directory $BackupPath 'BackupPath'
$restore = [IO.Path]::GetFullPath($RestoreDestination).TrimEnd('\\')
if (Test-Path -LiteralPath $restore) { throw 'RestoreDestination must be a new directory; rollback never overwrites a deployment.' }

$manifestPath = Join-Path $backup 'backup-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'BackupPath has no backup-manifest.json; an unverified backup cannot be restored.' }
$manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
if ($manifest.Count -eq 0) { throw 'Backup manifest is empty.' }
foreach ($entry in $manifest) {
    $file = Join-Path $backup $entry.RelativePath
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Backup file is missing: $($entry.RelativePath)" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Backup hash mismatch: $($entry.RelativePath)" }
}

if (-not $Apply) {
    [pscustomobject]@{
        VerifiedBackup = $backup
        RestoreDestination = $restore
        Files = $manifest.Count
        RollbackAction = 'NONE (plan mode)'
        NextStep = 'After owner authorization, re-run with -Apply -OwnerAuthorized. Update an IIS PhysicalPath only under the approved IIS change procedure.'
    } | Format-List
    return
}

if (-not $OwnerAuthorized) { throw 'Apply mode requires explicit owner authorization: pass -OwnerAuthorized only after it is recorded.' }
New-Item -ItemType Directory -Path $restore | Out-Null
try {
    Get-ChildItem -LiteralPath $backup -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $restore -Recurse -Force
    }
    foreach ($entry in $manifest) {
        $file = Join-Path $restore $entry.RelativePath
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.SHA256) {
            throw "Restored file verification failed: $($entry.RelativePath)"
        }
    }
    [pscustomobject]@{ VerifiedBackup = $backup; RestoreDestination = $restore; Files = $manifest.Count; RollbackAction = 'RESTORE_STAGED' } | Format-List
}
catch {
    if (Test-Path -LiteralPath $restore) { Remove-Item -LiteralPath $restore -Recurse -Force }
    throw
}
