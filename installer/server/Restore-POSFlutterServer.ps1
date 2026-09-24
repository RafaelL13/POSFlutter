[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)] [string] $SqlServer, [Parameter(Mandatory)] [string] $Database, [Parameter(Mandatory)] [string] $BackupFile)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $BackupFile)) { throw 'No existe el archivo de respaldo.' }
if (-not $PSCmdlet.ShouldProcess($Database, 'Restaurar base SQL Server; sobrescribe la base destino')) { return }
& sqlcmd -S $SqlServer -E -Q "ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; RESTORE DATABASE [$Database] FROM DISK = N'$BackupFile' WITH REPLACE, CHECKSUM; ALTER DATABASE [$Database] SET MULTI_USER"
if ($LASTEXITCODE -ne 0) { throw 'Falló la restauración SQL Server.' }
