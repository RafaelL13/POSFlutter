[CmdletBinding()]
param([Parameter(Mandatory)] [string] $SqlServer, [Parameter(Mandatory)] [string] $Database, [Parameter(Mandatory)] [string] $OutputDirectory)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { throw 'sqlcmd es requerido para el respaldo.' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$file = Join-Path $OutputDirectory ("$Database-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak')
& sqlcmd -S $SqlServer -E -Q "BACKUP DATABASE [$Database] TO DISK = N'$file' WITH CHECKSUM, COPY_ONLY"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file)) { throw 'Falló el respaldo SQL Server.' }
Get-FileHash $file -Algorithm SHA256 | Format-List
