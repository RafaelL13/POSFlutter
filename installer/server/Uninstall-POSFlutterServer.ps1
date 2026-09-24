[CmdletBinding(SupportsShouldProcess)]
param([string] $SiteName = 'POSFlutterApi', [string] $AppPoolName = 'POSFlutterApiPool')
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration
if ($PSCmdlet.ShouldProcess($SiteName, 'Eliminar sitio IIS POSFlutter')) {
  if (Test-Path "IIS:\Sites\$SiteName") { Remove-Website -Name $SiteName }
  if (Test-Path "IIS:\AppPools\$AppPoolName") { Remove-WebAppPool -Name $AppPoolName }
}
Write-Output 'La base de datos y los respaldos no se eliminan mediante este script.'
