#requires -Version 5.1
<#
POSFLUTTER WEB: preserva dos runtimes P04 LAB y hace checkpoint Git selectivo.
Preflight de solo lectura por defecto; -Commit verifica y luego registra docs.
NO arranca, detiene ni reinicia procesos; NO toca IIS/SQL ni modifica credenciales.
NO hace git push. NO sobrescribe archivos preexistentes divergentes.
#>
[CmdletBinding()]
param([switch]$Commit)
$ErrorActionPreference = 'Stop'
$root = 'C:\POSFlutter_Web\POSFlutter_Original'
$inputDir = Split-Path -Parent $PSCommandPath
$recoveryDir = Join-Path $root 'deploy\recovery'
$labDb = 'POSFlutter_MvcLab_P04Visual_ac22f4bd8dd2407f9b488351d08156ca'
$urls = @(59444, 59447)
$targets = New-Object 'System.Collections.Generic.List[string]'
function Assert([bool]$ok,[string]$reason) { if (-not $ok) { throw $reason } }
function Relative([string]$p) { return $p.Replace('\','/') }
function Sha([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function NativeGit([string[]]$arguments) {
    $s = @(& $script:gitExe -C $script:root @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('GIT_FAILED=' + ($arguments -join ' ') + '; DETAIL=' + ($s -join ' ')) }
    return (($s -join "`n").Trim())
}
function ProbeHttps([int]$port,[string]$route) {
    # IPv4 determinista, SNI localhost y certificado verificado; nunca usar -k.
    $url = ('https://localhost:{0}{1}' -f $port,$route)
    $status = (& $script:curl -4 -sS --noproxy '*' --resolve ("localhost:{0}:127.0.0.1" -f $port) `
        --connect-timeout 3 --max-time 10 --output NUL --write-out '%{http_code}' $url 2>&1)
    $exit = $LASTEXITCODE
    if ($exit -ne 0) { return [pscustomobject]@{ Status=0; Error='CURL_EXIT_' + $exit } }
    if (($status -join '').Trim() -notmatch '^\d{3}$') { return [pscustomobject]@{ Status=0; Error='INVALID_RESPONSE' } }
    return [pscustomobject]@{ Status=[int](($status -join '').Trim()); Error=$null }
}
function AddUnique([string]$path) { if (-not $targets.Contains($path)) { [void]$targets.Add($path) } }
function AddFileSafe([string]$source,[string]$destination,[string]$relative) {
    Assert (Test-Path -LiteralPath $source -PathType Leaf) ('BUNDLE_MISSING=' + $source)
    if(Test-Path -LiteralPath $destination) {
        Assert ((Sha $destination) -eq (Sha $source)) ('PRESERVE_EXISTING_DIFFERENT=' + $destination)
    } else {
        $dir = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    }
    AddUnique $relative
}
Write-Host '===== POSFLUTTER P04 — DOS INSTANCIAS Y CHECKPOINT SEGURO ====='
Assert (Test-Path -LiteralPath $root -PathType Container) 'CANONICAL_REPO_MISSING'
$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
Assert (Test-Path -LiteralPath $curl) 'CURL_WINDOWS_MISSING'
$files = @('RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1','P04_RECOVERY_VERIFIED.json')
foreach($n in $files) { Assert (Test-Path -LiteralPath (Join-Path $recoveryDir $n) -PathType Leaf) ('P04_RECOVERY_FILE_MISSING=' + $n) }
foreach($stamp in @('183339','185415')) {
    $expected = Join-Path $inputDir ('P04_RESULTADOS_' + $stamp + '.json')
    Assert (Test-Path -LiteralPath $expected -PathType Leaf) ('P04_EVIDENCE_MISSING=' + $stamp)
    # PS 5.1 can emit a JSON array as one pipeline object. Count each entry explicitly.
    $parsed = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($expected))
    $requiredAreas = @('INSTALLATION_LAB','SQL_LAB','LAB_IDENTITY','HTTPS_RUNTIME',
        'AUTHENTICATION','DASHBOARD','POS','INVENTORY','PRODUCTS','PURCHASES','CATEGORIES')
    $seen = @{}
    $count = 0
    foreach($row in $parsed) {
        $count++
        Assert ($null -ne $row -and $null -ne $row.Area -and $null -ne $row.Status) ('P04_EVIDENCE_ROW_INVALID=' + $stamp)
        $area = [string]$row.Area
        Assert ($requiredAreas -ccontains $area) ('P04_EVIDENCE_UNKNOWN_AREA=' + $stamp + ':' + $area)
        Assert (-not $seen.ContainsKey($area)) ('P04_EVIDENCE_DUPLICATE_AREA=' + $stamp + ':' + $area)
        Assert ([string]$row.Status -ceq 'PASS') ('P04_EVIDENCE_AREA_NOT_PASS=' + $stamp + ':' + $area)
        $seen[$area] = $true
    }
    Assert ($count -eq $requiredAreas.Count -and $seen.Count -eq $requiredAreas.Count) ('P04_EVIDENCE_NOT_11_PASS=' + $stamp)
    Write-Host ('P04_EVIDENCE_{0}=PASS_11_OF_11' -f $stamp)
}
$manifest = Get-Content -LiteralPath (Join-Path $recoveryDir 'P04_RECOVERY_VERIFIED.json') -Raw | ConvertFrom-Json
Assert ($manifest.Result -eq 'PASS' -and [int]$manifest.HealthHttp -eq 200 -and [int]$manifest.LoginPageHttp -eq 200 -and $manifest.ProductionCertified -eq $false) 'P04_RECOVERY_MANIFEST_NOT_PASS'
Assert ($manifest.RecoveryScriptSha256 -eq (Sha (Join-Path $recoveryDir 'RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1'))) 'RECOVERY_RUNNER_HASH_CHANGED'
$routes = @{
    59444 = 'C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_185415\release'
    59447 = 'C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_183339\release'
}
$results = @()
foreach($port in $urls) {
    $source = $routes[$port]
    $dll = Join-Path $source 'PosFlutter.Web.dll'
    Assert (Test-Path -LiteralPath $dll -PathType Leaf) ('HISTORICAL_CANDIDATE_NOT_FOUND=' + $source)
    $health = ProbeHttps $port '/health'
    $login = ProbeHttps $port '/Home/Login'
    Write-Host ('PORT={0}; HEALTH_HTTP={1}; LOGIN_GET_HTTP={2}' -f $port,$health.Status,$login.Status)
    Assert ($health.Status -eq 200 -and $login.Status -eq 200) ('RUNTIME_NOT_HEALTHY_PORT=' + $port)
    $connections = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    $processIds = @($connections | ForEach-Object { [int]$_.OwningProcess } | Where-Object { $_ -gt 4 } | Sort-Object -Unique)
    Assert ($processIds.Count -eq 1) ('PORT_PID_AMBIGUOUS=' + $port)
    $ownerPid = $processIds[0]
    $ownerProc = Get-CimInstance Win32_Process -Filter ("ProcessId=$ownerPid") -ErrorAction Stop
    Assert ($null -ne $ownerProc -and $ownerProc.Name -match '^(dotnet|PosFlutter.Web)(\.exe)?$') ('UNEXPECTED_PORT_PROCESS=' + $port)
    Assert ($ownerProc.CommandLine -match 'PosFlutter\.Web(\.dll|\.exe)?') ('UNEXPECTED_RUNTIME_COMMAND_LINE=' + $port)
    Write-Host ("RUNTIME_PID_{0}={1}; CANDIDATE_HASH={2}" -f $port,$ownerPid,(Sha $dll))
    $results += [ordered]@{
        Port=$port; HealthHttp=$health.Status; LoginGetHttp=$login.Status; RuntimePidAtCheckpoint=$ownerPid
        ProcessName=$ownerProc.Name; CandidateDirectoryHistorical=$source; CandidateDllSha256=(Sha $dll)
        ActualLoadedBinaryMatchedToCandidate='NOT_VERIFIED_FROM_COMMAND_LINE'
        Authentication= $(if($port -eq 59447){'USER_SCREENSHOT_AUTHENTICATED_DASHBOARD'}else{'NOT_RETESTED_IN_RECOVERY'})
    }
}
Write-Host 'LIVE_RUNTIME=PASS; PROCESS_CHANGES=NONE; IIS_CHANGES=NONE; SQL_WRITES=NONE'
if(-not $Commit) { Write-Host 'CHECKPOINT=NOT_EXECUTED; RUN_ONCE_WITH_-Commit'; return }

# Respalda y registra SOLO cambios generados por este ejecutor.
$time = Get-Date -Format 'yyyyMMdd_HHmmss'
$evidence = Join-Path $root ("artifacts\P04_GIT_CHECKPOINT_$time")
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$gitObj = Get-Command git.exe -ErrorAction SilentlyContinue
if($gitObj) {
    $gitExe = $gitObj.Source
    $gitRoot = $null
    try { $gitRoot = NativeGit @('rev-parse','--show-toplevel') } catch { }
    if($gitRoot) {
        $g = [IO.Path]::GetFullPath($gitRoot.Replace('/','\')).TrimEnd('\')
        $r = [IO.Path]::GetFullPath($root).TrimEnd('\')
        if(-not ($r.Equals($g,[StringComparison]::OrdinalIgnoreCase) -or $r.StartsWith($g+'\',[StringComparison]::OrdinalIgnoreCase))) {
            Write-Host ('GIT_ROOT_MISMATCH=' + $g + '; EXPECTED_CANONICAL_INSIDE=' + $r)
            $gitRoot=$null
        }
    }
    if($gitRoot) {
        $originalStatus = NativeGit @('status','--porcelain=v1')
        [IO.File]::WriteAllText((Join-Path $evidence 'git-status-before.txt'),$originalStatus,(New-Object Text.UTF8Encoding($false)))
        $preStaged = NativeGit @('diff','--cached','--name-only')
        [IO.File]::WriteAllText((Join-Path $evidence 'git-staged-before.txt'),$preStaged,(New-Object Text.UTF8Encoding($false)))
    }
}
# Copiar solo archivos que faltan o son idénticos; nunca sobreescribir versiones existentes.
AddFileSafe (Join-Path $inputDir 'P04_CONSOLIDAR_INSTANCIAS_Y_GIT.ps1') (Join-Path $recoveryDir 'P04_CONSOLIDAR_INSTANCIAS_Y_GIT.ps1') 'deploy/recovery/P04_CONSOLIDAR_INSTANCIAS_Y_GIT.ps1'
AddFileSafe (Join-Path $inputDir 'INICIAR_POSWEB_P04_CERTIFICADO_V2.ps1') (Join-Path $recoveryDir 'INICIAR_POSWEB_P04_CERTIFICADO_V2.ps1') 'deploy/recovery/INICIAR_POSWEB_P04_CERTIFICADO_V2.ps1'
AddFileSafe (Join-Path $inputDir 'P04_RECUPERACION_Y_ACCESO.md') (Join-Path $root 'docs\P04_RECUPERACION_Y_ACCESO.md') 'docs/P04_RECUPERACION_Y_ACCESO.md'
AddFileSafe (Join-Path $inputDir 'P04_59447_Dashboard_20261105.png') (Join-Path $root 'docs\evidence\P04_59447_Dashboard_20261105.png') 'docs/evidence/P04_59447_Dashboard_20261105.png'
AddFileSafe (Join-Path $inputDir 'P04_RESULTADOS_183339.json') (Join-Path $root 'docs\evidence\P04_RESULTADOS_183339.json') 'docs/evidence/P04_RESULTADOS_183339.json'
AddFileSafe (Join-Path $inputDir 'P04_RESULTADOS_185415.json') (Join-Path $root 'docs\evidence\P04_RESULTADOS_185415.json') 'docs/evidence/P04_RESULTADOS_185415.json'
AddUnique 'deploy/recovery/RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1'
AddUnique 'deploy/recovery/P04_RECOVERY_VERIFIED.json'

# Agregar referencias a documentos preexistentes SIN incorporar ediciones ajenas.
$appendText = [IO.File]::ReadAllText((Join-Path $inputDir 'STATUS_P04_APPEND.md'))
$agentsText = [IO.File]::ReadAllText((Join-Path $inputDir 'AGENTS_P04_APPEND.md'))
$marker = '<!-- POSWEB_P04_RECOVERY_CONTINUITY_V1 -->'
$docChanges = @(
    @{ Path='AGENTS.md'; Note=$agentsText; Create=$true },
    @{ Path='POSWEB_EXECUTION_STATE.md'; Note=$appendText; Create=$false },
    @{ Path='DELIVERY_STATUS.md'; Note=$appendText; Create=$false },
    @{ Path='POSWEB_CIERRE_COMERCIAL.md'; Note=$appendText; Create=$false },
    @{ Path='docs/ESTADO_CANONICO.md'; Note=$appendText; Create=$false },
    @{ Path='docs/REGISTRO_ENTREGA.md'; Note=$appendText; Create=$false }
)
foreach($item in $docChanges) {
    $rel = [string]$item.Path
    $path = Join-Path $root $rel.Replace('/','\')
    if(-not (Test-Path -LiteralPath $path) -and -not $item.Create) { continue } # no duplicar estados
    if(Test-Path -LiteralPath $path) {
        $old = [IO.File]::ReadAllText($path)
        if($old.Contains($marker)) { continue } # se documentó previamente
        if($gitRoot) {
            $dirty = NativeGit @('status','--porcelain=v1','--',$rel)
            if(-not [string]::IsNullOrWhiteSpace($dirty)) {
                Write-Host "DOC_PRESERVED_DIRTY=$rel; SEE=docs/P04_RECUPERACION_Y_ACCESO.md"
                continue
            }
        }
        Copy-Item -LiteralPath $path -Destination (Join-Path $evidence (($rel -replace '[\\/]','_') + '.before'))
        [IO.File]::WriteAllText($path,($old.TrimEnd() + "`r`n`r`n" + $item.Note.Trim() + "`r`n"),(New-Object Text.UTF8Encoding($false)))
    } else {
        [IO.File]::WriteAllText($path,($item.Note.Trim() + "`r`n"),(New-Object Text.UTF8Encoding($false)))
    }
    AddUnique $rel
}
$snapshot = Join-Path $recoveryDir 'P04_DUAL_RUNTIME_SNAPSHOT.json'
$snapshotObj = [ordered]@{
    Project='POSFLUTTER WEB'; Result='PASS'; Scope='LAB_DUAL_RUNTIME'; TimestampUtc=(Get-Date).ToUniversalTime().ToString('o')
    Sources='current curl+process probes; historical verified P04 evidence; owner screenshot; recovered lab identity claim'
    GitCommitVerified=$false; P04HistoricalPass='11/11'; SqlLabDatabase=$labDb
    LabAuthRecovered='USER_VERIFIED_59447'; LabBackupStatus='PASS_REPORTED_BY_OWNER'
    LabBackupRelativePath='artifacts/P04_VISUAL_MANUAL/backup/MVC_LAB_BEFORE_IDENTITY_20261105_214347.bak'
    Runtime=$results; IisChanges='NONE'; SqlWrites='NONE'; KestrelRestarts=0
    ProductionCertified=$false; ProductionDeployment='NO_GO'
}
if (Test-Path -LiteralPath $snapshot) {
    $previousSnapshot = Get-Content -LiteralPath $snapshot -Raw | ConvertFrom-Json
    Assert ($previousSnapshot.Result -eq 'PASS' -and $previousSnapshot.IisChanges -eq 'NONE' -and $previousSnapshot.ProductionCertified -eq $false) 'EXISTING_SNAPSHOT_NOT_VALID'
    Write-Host 'SNAPSHOT=PREEXISTING_PASS_PRESERVED'
} else {
    $snapshotObj | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $snapshot -Encoding UTF8
}
AddUnique 'deploy/recovery/P04_DUAL_RUNTIME_SNAPSHOT.json'
$all = @($targets.ToArray())
$evidenceList = @($all | Sort-Object -Unique)
$evidenceList | Set-Content -LiteralPath (Join-Path $evidence 'checkpoint-allowlist.txt') -Encoding UTF8
Write-Host "FILES_PREPARED=$($evidenceList.Count); EVIDENCE=$evidence"

# Si git no puede operar sobre fuente canónica, conserva documentos pero NO crea repo alternativo.
if(-not $gitObj -or -not $gitRoot) { Write-Host 'GIT_CHECKPOINT=BLOCKED_REPO_ROOT_MISMATCH_OR_GIT_UNAVAILABLE; NO_GIT_INIT; WEB_REMAINS_RUNNING=YES'; exit 2 }
$branch = NativeGit @('symbolic-ref','--short','HEAD')
Assert (-not [string]::IsNullOrWhiteSpace($branch)) 'DETACHED_HEAD_NO_COMMIT'
Assert (-not [string]::IsNullOrWhiteSpace((NativeGit @('config','--get','user.name')))) 'GIT_AUTHOR_NAME_MISSING'
Assert (-not [string]::IsNullOrWhiteSpace((NativeGit @('config','--get','user.email')))) 'GIT_AUTHOR_EMAIL_MISSING'
foreach($rel in $evidenceList) {
    $path = Join-Path $root $rel.Replace('/','\')
    Assert (Test-Path -LiteralPath $path -PathType Leaf) ('ALLOWLIST_MISSING=' + $rel)
    $stagedAlready = NativeGit @('diff','--cached','--name-only','--',$rel)
    Assert ([string]::IsNullOrWhiteSpace($stagedAlready)) ('TARGET_ALREADY_STAGED_PRESERVE=' + $rel)
    $ignored = @(& $gitExe -C $root check-ignore -- $rel 2>$null)
    Assert ($LASTEXITCODE -eq 1) ('TARGET_IGNORED_REFUSE_FORCE_ADD=' + $rel)
}
# Se verifica no haya secretos: nunca se versionan backup, logs ni configuraciones locales.
foreach($rel in $evidenceList) {
    Assert ($rel -notmatch '(?i)(\.bak$|\.jks$|\.keystore$|\.dpapi$|\.env$|appsettings|key\.properties|artifacts/|\.log$)') ('SENSITIVE_PATH_REJECTED=' + $rel)
}
# git commit --only necesita que los nuevos paths sean conocidos, por eso intent-to-add.
foreach($rel in $evidenceList) {
    $tracked = @(& $gitExe -C $root ls-files --error-unmatch -- $rel 2>$null)
    if($LASTEXITCODE -ne 0) {
        & $gitExe -C $root add -N -- $rel | Out-Null
        Assert ($LASTEXITCODE -eq 0) ('GIT_INTENT_TO_ADD_FAILED=' + $rel)
    }
}
# Computar diferencias reales: los archivos ya confirmados y sin cambios NO
# deben aparecer como si hubieran sido modificados de nuevo.
$changesRaw = NativeGit (@('diff','HEAD','--name-only','--') + @($evidenceList.ToArray()))
$prefix = NativeGit @('rev-parse','--show-prefix')
$changedRootPaths = @(($changesRaw -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$changedPaths = @($changedRootPaths | ForEach-Object {
    $item = $_
    if($prefix) {
        Assert ($item.StartsWith($prefix,[StringComparison]::Ordinal)) ('DIFF_PATH_OUTSIDE_PROJECT=' + $item)
        $item.Substring($prefix.Length)
    } else { $item }
})
$headBefore = NativeGit @('rev-parse','HEAD')
if($changedPaths.Count -eq 0) {
    $head = $headBefore
    Write-Host "GIT_CHECKPOINT=ALREADY_COMMITTED; COMMIT=$head; NO_NEW_COMMIT"
} else {
    & $gitExe -C $root commit --only -m 'docs(posweb): preserve verified P04 dual LAB recovery and authenticated access' -- $changedPaths
    Assert ($LASTEXITCODE -eq 0) 'GIT_COMMIT_FAILED'
    $head = NativeGit @('rev-parse','HEAD')
    $prefix = NativeGit @('rev-parse','--show-prefix')
    $names = NativeGit @('show','--pretty=format:','--name-only','HEAD')
    $actual = @(($names -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $expectedRepo = @($changedPaths | ForEach-Object { ($prefix + $_).TrimStart('/') })
    $unexpected = @($actual | Where-Object { $expectedRepo -notcontains $_ })
    Assert ($unexpected.Count -eq 0) ('COMMITTED_UNEXPECTED_PATHS=' + ($unexpected -join ';'))
    foreach($item in $expectedRepo) { Assert ($actual -contains $item) ('CHECKPOINT_FILE_NOT_IN_COMMIT=' + $item) }
    Write-Host "GIT_CHECKPOINT=PASS; COMMIT=$head; BRANCH=$branch; COMMITTED_PATHS=$($actual.Count)"
}
# Comprobar que todos los archivos autorizados se encuentran en HEAD con el
# mismo contenido de disco, sean cambios nuevos o ya confirmados.
$prefix = NativeGit @('rev-parse','--show-prefix')
foreach($rel in $evidenceList) {
    $blobHead = NativeGit @('rev-parse',('HEAD:' + $prefix + $rel))
    $blobDisk = NativeGit @('hash-object',(Join-Path $root $rel.Replace('/','\')))
    Assert ($blobHead -eq $blobDisk) ('COMMITTED_BLOB_DIVERGENCE=' + $rel)
}
$afterStaged = NativeGit @('diff','--cached','--name-only')
$beforeStaged = [IO.File]::ReadAllText((Join-Path $evidence 'git-staged-before.txt'))
Assert ($afterStaged.Trim() -eq $beforeStaged.Trim()) 'PREEXISTING_GIT_STAGE_CHANGED'
Write-Host 'PREEXISTING_STAGED_PRESERVED=PASS; CHECKPOINT_CONTENT_IN_HEAD=PASS'
Write-Host 'GIT_PUSH=NOT_EXECUTED; NO_PRODUCTION_DEPLOYMENT; WEB_REMAINS_RUNNING=YES'
