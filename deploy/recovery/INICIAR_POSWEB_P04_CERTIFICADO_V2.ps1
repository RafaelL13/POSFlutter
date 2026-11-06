$ErrorActionPreference = 'Stop'
$release = 'C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_183339\release'
$instance = 'POSWEB_V44_LAB_20261018'
$database = 'POSFlutter_MvcLab_P04Visual_ac22f4bd8dd2407f9b488351d08156ca'
# Seleccionar un puerto disponible sin detener servicios existentes.
$port = $null
foreach ($candidatePort in 59446..59546) {
    $listener = $null
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $candidatePort)
        $listener.Start()
        $port = $candidatePort
        break
    } catch [System.Net.Sockets.SocketException] {
        continue
    } finally {
        if ($null -ne $listener) { $listener.Stop() }
    }
}
if ($null -eq $port) {
    Write-Host 'LAB_VISUAL=FAIL; DETAIL=NO_FREE_PORT_59446_59546'
    Write-Host 'PRODUCTION=NO_GO'
    exit 1
}
$base = "https://localhost:$port"
$evidence = 'C:\POSFlutter_Web\POSFlutter_Original\artifacts\P04_VISUAL_MANUAL'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
try {
    if (-not (Test-Path -LiteralPath (Join-Path $release 'PosFlutter.Web.dll'))) { throw 'CANDIDATE_MISSING' }
    $sqlcmd = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
    if (-not (Test-Path -LiteralPath $sqlcmd)) { throw 'SQLCMD_MISSING' }
    $check = @(& $sqlcmd -S "(localdb)\$instance" -E -C -d master -b -h -1 -W -Q "SET NOCOUNT ON;SELECT CASE WHEN DB_ID(N'$database') IS NULL THEN 0 ELSE 1 END;" 2>&1)
    if ($LASTEXITCODE -ne 0 -or (($check | Select-Object -Last 1).ToString().Trim() -ne '1')) { throw 'LAB_DATABASE_UNAVAILABLE' }
    & dotnet dev-certs https --check | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HTTPS_CERT_MISSING' }
    $oldConn = [Environment]::GetEnvironmentVariable('ConnectionStrings__SqlServer','Process')
    $oldUrls = [Environment]::GetEnvironmentVariable('ASPNETCORE_URLS','Process')
    $oldEnv = [Environment]::GetEnvironmentVariable('ASPNETCORE_ENVIRONMENT','Process')
    try {
        [Environment]::SetEnvironmentVariable('ConnectionStrings__SqlServer',"Server=(localdb)\$instance;Database=$database;Integrated Security=True;TrustServerCertificate=True",'Process')
        [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS',$base,'Process')
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT','Development','Process')
        $out = Join-Path $evidence ("stdout_$port.log"); $err = Join-Path $evidence ("stderr_$port.log")
        $proc = Start-Process -FilePath (Get-Command dotnet).Source -ArgumentList @('PosFlutter.Web.dll') -WorkingDirectory $release -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
    } finally {
        [Environment]::SetEnvironmentVariable('ConnectionStrings__SqlServer',$oldConn,'Process')
        [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS',$oldUrls,'Process')
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT',$oldEnv,'Process')
    }
    $ok = $false
    for ($i=0; $i -lt 40; $i++) {
        if ($proc.HasExited) { break }
        try {
            $response = Invoke-WebRequest -Uri "$base/health" -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200) { $ok = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ok) { throw "HEALTH_FAILED; PID=$($proc.Id); LOG=$err" }
    Write-Host 'LAB_VISUAL=PASS'
    Write-Host "PID=$($proc.Id)"
    Write-Host "URL=$base/Home/Login"
    Write-Host "EVIDENCE=$evidence"
    Write-Host 'IIS_CHANGES=NONE'
    Write-Host 'PRODUCTION=NO_GO'
    Start-Process "$base/Home/Login"
} catch {
    Write-Host "LAB_VISUAL=FAIL; DETAIL=$($_.Exception.Message)"
    Write-Host 'PRODUCTION=NO_GO'
    exit 1
}
