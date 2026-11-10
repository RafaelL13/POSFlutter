#requires -Version 5.1
# POSFlutter Web: restauracion del runtime LAB P04 historicamente aprobado.
# No cambia IIS, aplicaciones fuente, cuentas, contrasenas ni datos SQL.
[CmdletBinding(DefaultParameterSetName='Start')]
param(
    [Parameter(ParameterSetName='Start')][switch]$Start,
    [Parameter(ParameterSetName='Start')][switch]$Push,
    [Parameter(ParameterSetName='Stop',Mandatory=$true)][switch]$Stop,
    [Parameter(ParameterSetName='Status',Mandatory=$true)][switch]$Status
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = 'C:\POSFlutter_Web\POSFlutter_Original'
$source = 'C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_185415\release'
$work = Join-Path $root 'artifacts\P04_KESTREL_RECOVERY'
$target = Join-Path $work 'release'
$stateFile = Join-Path $work 'state.json'
$port = 59444
$base = 'https://localhost:59444'
$instance = 'POSWEB_V44_LAB_20261018'
$database = 'POSFlutter_MvcLab_P04Visual_ac22f4bd8dd2407f9b488351d08156ca'
$expectedSource = 'C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_185415\release'
$ownedProcess = $null
$runLog = $null

function Assert-Ok([bool]$ok, [string]$message) {
    if (-not $ok) { throw $message }
}
function Read-State {
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    return (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json)
}
function Get-OwnedProcess($state) {
    if ($null -eq $state -or -not $state.Pid) { return $null }
    $p = Get-Process -Id ([int]$state.Pid) -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    try {
        $startUtc = $p.StartTime.ToUniversalTime().ToString('o')
        $command = (Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$state.Pid) -ErrorAction Stop).CommandLine
        if ($startUtc -ne [string]$state.StartUtc) { return $null }
        if ([string]::IsNullOrWhiteSpace($command)) { return $null }
        if (-not $command.Contains((Join-Path $target 'PosFlutter.Web.dll'))) { return $null }
        return $p
    }
    catch { return $null }
}
function Get-HttpCode([string]$url) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    Assert-Ok (Test-Path -LiteralPath $curl) 'CURL_SYSTEM_NOT_FOUND'
    $reply = @(& $curl -4 -k -sS --noproxy '*' --connect-timeout 2 --max-time 5 -o NUL -w '%{http_code}' $url 2>$null)
    if ($LASTEXITCODE -ne 0) { return '000' }
    return ($reply -join '').Trim()
}
function Save-Result([string]$result, [string]$detail, [string]$evidencePath) {
    $data = [ordered]@{
        Result = $result
        Detail = $detail
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        Source = $source
        Runtime = $target
        HealthUrl = "$base/health"
        LabDatabase = $database
        IisChanges = 'NONE'
        ProductionDeployment = 'NO'
    }
    if ($evidencePath) { $data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidencePath 'result.json') -Encoding UTF8 }
    Write-Host "RECOVERY=$result; DETAIL=$detail"
}

if ($Stop) {
    $s = Read-State
    $owned = Get-OwnedProcess $s
    if ($null -eq $owned) {
        Write-Host 'STOP=NO_OWNED_PROCESS; CONFIGURATION_CHANGES=NONE'
        return
    }
    Stop-Process -Id $owned.Id -Force -ErrorAction Stop
    $owned.WaitForExit(10000) | Out-Null
    $s | Add-Member -NotePropertyName StoppedUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
    $s | Add-Member -NotePropertyName Active -NotePropertyValue $false -Force
    $s | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Write-Host "STOP=PASS; PID=$($owned.Id); IIS_CHANGES=NONE"
    return
}
if ($Status) {
    $s = Read-State
    $owned = Get-OwnedProcess $s
    $code = Get-HttpCode "$base/health"
    Write-Host "OWNED_PROCESS=$([bool]$owned)"
    Write-Host "HEALTH_HTTP=$code"
    if ($owned) { Write-Host "PID=$($owned.Id)" }
    Write-Host "URL=$base"
    Write-Host 'IIS_CHANGES=NONE; PRODUCTION_DEPLOYMENT=NO'
    return
}

Write-Host '===== POSFLUTTER P04 — RECUPERAR KESTREL LAB APROBADO =====' -ForegroundColor Cyan
Assert-Ok ($source -eq $expectedSource) 'SOURCE_PATH_CHANGED'
Assert-Ok ($database -match '^POSFlutter_MvcLab_P04Visual_[a-f0-9]{32}$') 'UNSAFE_LAB_DATABASE'
Assert-Ok ($instance -eq 'POSWEB_V44_LAB_20261018') 'UNEXPECTED_SQL_INSTANCE'
foreach ($file in @('PosFlutter.Web.dll','PosFlutter.Web.deps.json','PosFlutter.Web.runtimeconfig.json','web.config','wwwroot\css\p04-visual-fixes.css')) {
    Assert-Ok (Test-Path -LiteralPath (Join-Path $source $file)) ("APPROVED_P04_SOURCE_INCOMPLETE=" + $file)
}
$dotnetCommand = Get-Command dotnet.exe -ErrorAction SilentlyContinue
Assert-Ok ($null -ne $dotnetCommand) 'DOTNET_NOT_AVAILABLE'
$dotnet = $dotnetCommand.Source
$certCheck = @(& $dotnet dev-certs https --check 2>&1)
Assert-Ok ($LASTEXITCODE -eq 0) 'DOTNET_HTTPS_DEV_CERT_UNAVAILABLE'

$s = Read-State
$existing = Get-OwnedProcess $s
if ($existing) {
    $code = Get-HttpCode "$base/health"
    if ($code -eq '200') {
        Write-Host "ALREADY_RUNNING=PASS; PID=$($existing.Id); HEALTH_HTTP=200"
        Write-Host "OPEN_URL=$base"
        Write-Host 'NO_RESTART; IIS_CHANGES=NONE; PRODUCTION_DEPLOYMENT=NO'
        return
    }
    throw "OWNED_PROCESS_UNHEALTHY_NOT_KILLED; PID=$($existing.Id); HEALTH_HTTP=$code"
}
# El puerto debe estar libre; nunca cerrar o reemplazar un servicio ajeno.
$listener = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
Assert-Ok ($listener.Count -eq 0) 'PORT_59444_ALREADY_IN_USE_NO_CHANGES'

# La base aprobada ya existe; no crear, migrar, restaurar ni sembrar datos.
$sqlLocal = Get-Command sqllocaldb.exe -ErrorAction SilentlyContinue
Assert-Ok ($null -ne $sqlLocal) 'SQLLOCALDB_NOT_AVAILABLE'
$sqlInfo = @(& $sqlLocal.Source info $instance 2>&1)
Assert-Ok ($LASTEXITCODE -eq 0) 'EXISTING_LAB_SQL_INSTANCE_NOT_FOUND'
$sqlStart = @(& $sqlLocal.Source start $instance 2>&1)
Assert-Ok ($LASTEXITCODE -eq 0) 'EXISTING_LAB_SQL_INSTANCE_START_FAILED'

# Lectura SQL por ADO.NET. Evita fallos de versiones incompatibles de sqlcmd.
# Consulta solo metadata de master, sin crear, restaurar o actualizar bases.
$connection = $null
try {
    Add-Type -AssemblyName System.Data -ErrorAction Stop
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = "(localdb)\$instance"
    $builder['Initial Catalog'] = 'master'
    $builder['Integrated Security'] = $true
    $builder['Connect Timeout'] = 8
    $builder['Encrypt'] = $false
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = 'SELECT DB_ID(@databaseName), HAS_DBACCESS(@databaseName)'
    $parameter = $command.Parameters.Add('@databaseName', [System.Data.SqlDbType]::NVarChar, 128)
    $parameter.Value = $database
    $reader = $command.ExecuteReader()
    Assert-Ok ($reader.Read()) 'LAB_SQL_METADATA_EMPTY'
    $dbExists = -not $reader.IsDBNull(0)
    $dbAccessible = ($dbExists -and -not $reader.IsDBNull(1) -and [int]$reader.GetValue(1) -eq 1)
    $reader.Close()
    Assert-Ok $dbExists 'LAB_DATABASE_NOT_FOUND_NO_WRITE_PERFORMED'
    Assert-Ok $dbAccessible 'LAB_DATABASE_ACCESS_DENIED_NO_WRITE_PERFORMED'
    Write-Host 'LAB_DATABASE_EXISTENCE=PASS; LAB_DATABASE_ACCESS=PASS; SQL_CHECK=ADO_READ_ONLY'
}
catch {
    $errorText = [string]$_.Exception.Message
    $sqlException = $_.Exception
    if ($sqlException -is [System.Data.SqlClient.SqlException]) {
        Write-Host ("LAB_SQL_PROVIDER_ERROR_NUMBER={0}; CLASS={1}" -f $sqlException.Number, $sqlException.Class)
    }
    # La conexion es solo Windows integrada y no incluye contrasenas.
    # No imprimir la cadena completa ni los detalles de autenticacion.
    Write-Host ('LAB_SQL_DIAGNOSTIC=' + $errorText)
    throw
}
finally {
    if ($null -ne $connection) { $connection.Dispose() }
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
$sourceDllHash = (Get-FileHash -LiteralPath (Join-Path $source 'PosFlutter.Web.dll') -Algorithm SHA256).Hash
$sourceConfigHash = (Get-FileHash -LiteralPath (Join-Path $source 'web.config') -Algorithm SHA256).Hash
$sourceCssHash = (Get-FileHash -LiteralPath (Join-Path $source 'wwwroot\css\p04-visual-fixes.css') -Algorithm SHA256).Hash
if (-not (Test-Path -LiteralPath $target)) {
    New-Item -ItemType Directory -Path $target | Out-Null
    & robocopy.exe $source $target /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ | Out-Null
    Assert-Ok ($LASTEXITCODE -lt 8) 'COPY_P04_RUNTIME_FAILED'
}
foreach ($entry in @(
    @{Relative='PosFlutter.Web.dll'; Expected=$sourceDllHash},
    @{Relative='web.config'; Expected=$sourceConfigHash},
    @{Relative='wwwroot\css\p04-visual-fixes.css'; Expected=$sourceCssHash}
)) {
    $path = Join-Path $target $entry.Relative
    Assert-Ok (Test-Path -LiteralPath $path) ("RUNTIME_FILE_MISSING=" + $entry.Relative)
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Assert-Ok ($hash -eq $entry.Expected) ("RUNTIME_DIVERGED_NO_OVERWRITE=" + $entry.Relative)
}

$runLog = Join-Path $work ('attempt_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $runLog -ErrorAction Stop | Out-Null
$envNames = @('ConnectionStrings__SqlServer','ASPNETCORE_URLS','ASPNETCORE_ENVIRONMENT')
$oldEnv = @{}
foreach ($name in $envNames) { $oldEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    # Solo la base LocalDB aislada aprobada. NUNCA SQL de produccion.
    [Environment]::SetEnvironmentVariable('ConnectionStrings__SqlServer',"Server=(localdb)\$instance;Database=$database;Integrated Security=True;TrustServerCertificate=True",'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS',$base,'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT','Development','Process')
    $dll = Join-Path $target 'PosFlutter.Web.dll'
    $ownedProcess = Start-Process -FilePath $dotnet -WorkingDirectory $target `
        -ArgumentList @(('"' + $dll + '"'),'--contentRoot',('"' + $target + '"'),'--urls',$base) `
        -RedirectStandardOutput (Join-Path $runLog 'kestrel.stdout.log') `
        -RedirectStandardError (Join-Path $runLog 'kestrel.stderr.log') `
        -PassThru -WindowStyle Hidden
    Assert-Ok ($null -ne $ownedProcess) 'KESTREL_DID_NOT_START'
}
finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name,$oldEnv[$name],'Process') }
}

try {
    $health = '000'
    $deadline = (Get-Date).AddSeconds(50)
    do {
        $ownedProcess.Refresh()
        Assert-Ok (-not $ownedProcess.HasExited) ("KESTREL_EXITED_EARLY=" + $ownedProcess.ExitCode)
        $health = Get-HttpCode "$base/health"
        if ($health -eq '200') { break }
        Start-Sleep -Milliseconds 700
    } while ((Get-Date) -lt $deadline)
    Assert-Ok ($health -eq '200') ("KESTREL_HEALTH_HTTP=" + $health)

    # Confirmar certificado HTTPS confiable por Windows (sin -k).
    $response = Invoke-WebRequest -Uri "$base/health" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    Assert-Ok ([int]$response.StatusCode -eq 200) 'TLS_TRUSTED_HEALTH_NOT_200'

    $loginCode = Get-HttpCode "$base/Home/Login"
    Assert-Ok ($loginCode -eq '200') ("LOGIN_PAGE_HTTP=" + $loginCode)

    $ownedProcess.Refresh()
    $startTime = $ownedProcess.StartTime.ToUniversalTime().ToString('o')
    $command = (Get-CimInstance Win32_Process -Filter ("ProcessId=" + $ownedProcess.Id)).CommandLine
    Assert-Ok ($null -ne $command -and $command.Contains($dll)) 'KESTREL_PROCESS_IDENTITY_NOT_VERIFIED'
    $state = [ordered]@{
        Pid = $ownedProcess.Id
        StartUtc = $startTime
        Source = $source
        Target = $target
        Url = $base
        SourceDllSha256 = $sourceDllHash
        SourceWebConfigSha256 = $sourceConfigHash
        SourceCssSha256 = $sourceCssHash
        LabDatabase = $database
        Evidence = $runLog
        Active = $true
        ProductionCertified = $false
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Save-Result 'PASS' 'HTTPS_200_AND_LOGIN_200; AUTHENTICATION_NOT_RETESTED' $runLog
    Write-Host "KESTREL_PID=$($ownedProcess.Id)"
    Write-Host "HEALTH_HTTP=$health; LOGIN_PAGE_HTTP=$loginCode; TLS_TRUSTED=PASS"
    Write-Host "OPEN_URL=$base"
    Write-Host "EVIDENCE=$runLog"
    Write-Host 'IIS_CHANGES=NONE; SQL_TARGET=ISOLATED_LAB; PRODUCTION_DEPLOYMENT=NO'
    # Persistir ejecutor reproducible y evidencia sanitizada EN EL REPOSITORIO.
    # No incluir runtime compilado, cookies, credenciales, respaldos DPAPI ni logs privados.
    try {
        $checkpointDir = Join-Path $root 'deploy\recovery'
        New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
        $checkpointRunner = Join-Path $checkpointDir 'RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1'
        $currentScriptHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        if (Test-Path -LiteralPath $checkpointRunner) {
            Assert-Ok ((Get-FileHash -LiteralPath $checkpointRunner -Algorithm SHA256).Hash -eq $currentScriptHash) 'CANONICAL_RUNNER_DIVERGED_NO_OVERWRITE'
        }
        else {
            Copy-Item -LiteralPath $PSCommandPath -Destination $checkpointRunner -ErrorAction Stop
            Assert-Ok ((Get-FileHash -LiteralPath $checkpointRunner -Algorithm SHA256).Hash -eq $currentScriptHash) 'CANONICAL_RUNNER_COPY_HASH_MISMATCH'
        }
        $checkpointManifest = Join-Path $checkpointDir 'P04_RECOVERY_VERIFIED.json'
        [ordered]@{
            Project='POSFLUTTER WEB'; Result='PASS'
            VerifiedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
            RuntimeSource=$source; RuntimeSourceDllSha256=$sourceDllHash
            RuntimeSourceWebConfigSha256=$sourceConfigHash
            RecoveryScriptSha256=$currentScriptHash
            HealthHttp=200; LoginPageHttp=200; HttpsTrusted=$true
            LoginAuthenticatedInThisRun=$false
            Database='ISOLATED_LAB_P04'
            IisChanges='NONE'; ProductionCertified=$false
            EvidencePath=$runLog
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $checkpointManifest -Encoding UTF8
        Write-Host "CANONICAL_RECOVERY_SCRIPT=$checkpointRunner"
        Write-Host "CANONICAL_RECOVERY_MANIFEST=$checkpointManifest"
        # Git solo despues de PASS; no compromete ni incluye cambios ajenos.
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($null -eq $git) {
            Write-Host 'GIT_CHECKPOINT=BLOCKED_GIT_NOT_FOUND; WEB_REMAINS_RUNNING=YES'
        }
        else {
            $gitRootOut = @(& $git.Source -C $root rev-parse --show-toplevel 2>$null)
            $gitRoot = (($gitRootOut -join '').Trim() -replace '[\\/]+$', '')
            if ($LASTEXITCODE -ne 0 -or $gitRoot -ine ($root -replace '[\\/]+$', '')) {
                Write-Host 'GIT_CHECKPOINT=BLOCKED_REPO_ROOT_MISMATCH; WEB_REMAINS_RUNNING=YES'
            }
            else {
                $branch = @(& $git.Source -C $root symbolic-ref --short HEAD 2>$null)
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($branch -join ''))) {
                    Write-Host 'GIT_CHECKPOINT=BLOCKED_DETACHED_HEAD; WEB_REMAINS_RUNNING=YES'
                }
                else {
                    $paths = @('deploy/recovery/RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1','deploy/recovery/P04_RECOVERY_VERIFIED.json')
                    & $git.Source -C $root add -- $paths
                    Assert-Ok ($LASTEXITCODE -eq 0) 'GIT_CHECKPOINT_ADD_FAILED'
                    & $git.Source -C $root commit --only -m 'fix(posweb): preserve verified P04 Kestrel LAB recovery' -- $paths
                    if ($LASTEXITCODE -ne 0) {
                        # Puede ocurrir si la misma version y manifiesto ya estaban registrados.
                        $pending = @(& $git.Source -C $root status --porcelain -- $paths)
                        Assert-Ok ($pending.Count -eq 0) 'GIT_CHECKPOINT_COMMIT_FAILED'
                        Write-Host 'GIT_CHECKPOINT=ALREADY_COMMITTED'
                    }
                    else {
                        $commitHash = @(& $git.Source -C $root rev-parse HEAD)
                        Write-Host ("GIT_CHECKPOINT=PASS; COMMIT={0}" -f (($commitHash -join '').Trim()))
                    }
                    if ($Push) {
                        $upstream = @(& $git.Source -C $root rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
                        if ($LASTEXITCODE -ne 0 -or -not ($upstream -join '').Trim()) {
                            Write-Host 'GIT_PUSH=BLOCKED_NO_CONFIGURED_UPSTREAM'
                        }
                        else {
                            $oldPrompt = $env:GIT_TERMINAL_PROMPT
                            $oldGcmInteractive = $env:GCM_INTERACTIVE
                            try {
                                $env:GIT_TERMINAL_PROMPT = '0'
                                $env:GCM_INTERACTIVE = 'never'
                                & $git.Source -C $root push
                                if ($LASTEXITCODE -eq 0) { Write-Host 'GIT_PUSH=PASS' }
                                else { Write-Host 'GIT_PUSH=BLOCKED_OR_FAILED' }
                            }
                            finally {
                                $env:GIT_TERMINAL_PROMPT = $oldPrompt
                                $env:GCM_INTERACTIVE = $oldGcmInteractive
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Host "GIT_CHECKPOINT=BLOCKED; DETAIL=$($_.Exception.Message); WEB_REMAINS_RUNNING=YES"
        Write-Host 'GIT_RETRY=REQUIRED; NEVER_RESTART_WEB_TO_FIX_GIT'
    }
}
catch {
    $msg = $_.Exception.Message
    if ($ownedProcess) {
        try {
            $ownedProcess.Refresh()
            if (-not $ownedProcess.HasExited) {
                Stop-Process -Id $ownedProcess.Id -Force -ErrorAction Stop
                Write-Host "ROLLBACK_OWN_PROCESS=PASS; PID=$($ownedProcess.Id)"
            }
        } catch { Write-Host "ROLLBACK_OWN_PROCESS=FAIL; DETAIL=$($_.Exception.Message)" }
    }
    Save-Result 'FAIL' $msg $runLog
    throw
}
