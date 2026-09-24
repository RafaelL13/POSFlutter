[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [string] $SourceRoot,
  [securestring] $SqlConnectionString,
  [securestring] $JwtSigningKey,
  [string] $SiteName = 'POSFlutterApi',
  [string] $AppPoolName = 'POSFlutterApiPool',
  [string] $InstallPath = 'C:\Apps\POSFlutter\Api',
  [int] $Port = 8080,
  [switch] $Upgrade
)

$ErrorActionPreference = 'Stop'
function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Ejecuta este instalador desde PowerShell elevado.'
  }
}
function Assert-Command([string] $Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "No se encontró el requisito: $Name."
  }
}
function Assert-ServerPrerequisites {
  if (-not $IsWindows) { throw 'El instalador de servidor sólo es compatible con Windows Server/IIS.' }
  if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) {
    throw 'No se pudo validar IIS: falta ServerManager/Get-WindowsFeature.'
  }
  if (-not (Get-WindowsFeature Web-Server).Installed) { throw 'IIS Web-Server no está instalado.' }
  $runtime = & dotnet --list-runtimes | Select-String '^Microsoft.AspNetCore.App 10\\.'
  if ($null -eq $runtime) { throw 'Falta ASP.NET Core 10 Hosting Bundle/runtime.' }
}
function Convert-SecureString([securestring] $Value) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Read-RequiredSecret([string] $Prompt) {
  $value = Read-Host -Prompt $Prompt -AsSecureString
  if ($value.Length -eq 0) { throw "$Prompt es obligatorio." }
  return $value
}
function Set-PosFlutterEnvironment([string] $Path, [string] $ConnectionString, [string] $SigningKey) {
  $configPath = Join-Path $Path 'web.config'
  if (-not (Test-Path $configPath)) { throw 'La publicación no generó web.config para IIS.' }
  [xml] $config = Get-Content -LiteralPath $configPath -Raw
  $aspNetCore = $config.configuration.'system.webServer'.aspNetCore
  if ($null -eq $aspNetCore) { throw 'web.config no contiene la configuración aspNetCore esperada.' }
  $environmentVariables = $aspNetCore.environmentVariables
  if ($null -eq $environmentVariables) {
    $environmentVariables = $config.CreateElement('environmentVariables')
    [void] $aspNetCore.AppendChild($environmentVariables)
  }
  foreach ($entry in @(@{ Name = 'ConnectionStrings__SqlServer'; Value = $ConnectionString }, @{ Name = 'Jwt__SigningKey'; Value = $SigningKey })) {
    $node = @($environmentVariables.environmentVariable | Where-Object { $_.name -eq $entry.Name }) | Select-Object -First 1
    if ($null -eq $node) {
      $node = $config.CreateElement('environmentVariable')
      [void] $environmentVariables.AppendChild($node)
    }
    $node.SetAttribute('name', $entry.Name)
    $node.SetAttribute('value', $entry.Value)
  }
  $config.Save($configPath)
}

Assert-Administrator
Assert-Command dotnet
Assert-ServerPrerequisites
Import-Module WebAdministration
if (-not (Test-Path (Join-Path $SourceRoot 'server\src\Api\Api.csproj'))) {
  throw 'SourceRoot no contiene el proyecto POSFlutter server esperado.'
}
if ($SiteName -eq 'SistemaVentas') { throw 'POSFlutter no puede usar el sitio IIS SistemaVentas.' }
if ($null -eq $SqlConnectionString) { $SqlConnectionString = Read-RequiredSecret 'Cadena de conexión SQL Server' }
if ($null -eq $JwtSigningKey) { $JwtSigningKey = Read-RequiredSecret 'JWT signing key' }

$apiProject = Join-Path $SourceRoot 'server\src\Api\Api.csproj'
$infrastructureProject = Join-Path $SourceRoot 'server\src\Infrastructure\Infrastructure.csproj'
$plainConnection = Convert-SecureString $SqlConnectionString
$plainJwt = Convert-SecureString $JwtSigningKey
try {
  if ((Test-Path "IIS:\Sites\$SiteName") -and -not $Upgrade) {
    throw "El sitio IIS $SiteName ya existe. Reejecuta con -Upgrade después de respaldar y verificar el despliegue actual."
  }
  if ($PSCmdlet.ShouldProcess($InstallPath, 'Publicar API')) {
    New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
    & dotnet publish $apiProject --configuration Release --output $InstallPath --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Falló dotnet publish.' }
  }
  if ($PSCmdlet.ShouldProcess('POSFlutter database', 'Aplicar migraciones EF')) {
    $env:POSFLUTTER_EF_CONNECTION_STRING = $plainConnection
    & dotnet ef database update --project $infrastructureProject --startup-project $apiProject --no-build
    if ($LASTEXITCODE -ne 0) { throw 'Falló la migración de SQL Server.' }
  }
  if ($PSCmdlet.ShouldProcess($AppPoolName, 'Configurar AppPool IIS')) {
    if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) { New-WebAppPool -Name $AppPoolName | Out-Null }
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ''
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.identityType -Value ApplicationPoolIdentity
    if (Test-Path "IIS:\Sites\$SiteName") { Remove-Website -Name $SiteName }
    New-Website -Name $SiteName -PhysicalPath $InstallPath -Port $Port -ApplicationPool $AppPoolName | Out-Null
    Set-PosFlutterEnvironment -Path $InstallPath -ConnectionString $plainConnection -SigningKey $plainJwt
    Restart-WebAppPool -Name $AppPoolName
  }
  $health = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 "http://127.0.0.1:$Port/health"
  if ($health.StatusCode -ne 200) { throw "Health devolvió $($health.StatusCode)." }
  Write-Output 'POSFlutter server installation: PASS'
} finally {
  Remove-Item Env:POSFLUTTER_EF_CONNECTION_STRING -ErrorAction SilentlyContinue
  $plainConnection = $null
  $plainJwt = $null
}
