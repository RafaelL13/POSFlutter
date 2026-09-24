[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([string] $AdbPath = 'adb')
$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess('com.posflutter.pos_app', 'BORRAR todos los datos locales POSFlutter')) { return }
& $AdbPath shell pm clear com.posflutter.pos_app
if ($LASTEXITCODE -ne 0) { throw 'Falló el borrado de datos Android.' }
