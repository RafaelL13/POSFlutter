#requires -Version 5.1
<#
POSFlutter Web - certificacion automatica HTTPS en laboratorio.
Windows PowerShell 5.1; no requiere Codex ni PowerShell 7.
No modifica archivos fuente, el harness original ni bases productivas.
Agrega temporalmente confianza en CurrentUser\Root y la retira en finally.
Usa un certificado efimero en CurrentUser\My y confianza temporal en CurrentUser\Root.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'C:\POSFlutter_Web\POSFlutter_Original',
    [string]$Instancia = 'POSWEB_V44_LAB_20261018',
    [string]$Database = 'POSFlutter_MvcLab_CheckoutCert_20261018_222511_f300b7c3',
    [int]$Port = 7143
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$hostProcess = $null
$certificate = $null
$rootTrustAdded = $false
$originalCertCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
$originalProxy = [System.Net.WebRequest]::DefaultWebProxy
$envNames = @('ConnectionStrings__SqlServer', 'ASPNETCORE_URLS', 'ASPNETCORE_Kestrel__Certificates__Default__Path', 'ASPNETCORE_Kestrel__Certificates__Default__Password')
$oldEnv = @{}
foreach ($name in $envNames) { $oldEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$work = Join-Path $env:TEMP ('POSWEB_HTTPS_CERT_' + [guid]::NewGuid().ToString('N'))
$base = 'https://localhost:' + $Port
$harnessSource = Join-Path $Repo 'tests\CertifyMvcPosLab.ps1'
$sqlCmd = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
$instanceSql = '(localdb)\' + $Instancia
$exitState = 'FAIL'

function Fail([string]$reason) { throw $reason }
function Get-LabCounts {
    $query = @"
SET NOCOUNT ON;
SELECT CONCAT(
 (SELECT COUNT_BIG(*) FROM dbo.Sales), '|',
 (SELECT COUNT_BIG(*) FROM dbo.SalePayments WHERE Method = 'Card'), '|',
 (SELECT COUNT_BIG(*) FROM dbo.SalePayments WHERE Method = 'Cash'), '|',
 (SELECT COUNT_BIG(*) FROM dbo.SalePayments WHERE Method = 'Transfer'), '|',
 (SELECT COUNT_BIG(*) FROM dbo.SalePayments WHERE Method = 'Cash' AND CashSessionId IS NOT NULL), '|',
 (SELECT COUNT_BIG(*) FROM dbo.InventoryMovements), '|',
 COALESCE((SELECT SUM(CAST(AvailableQuantity AS BIGINT)) FROM dbo.InventoryLots), 0)
);
"@
    $output = @(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d $Database -h -1 -W -Q $query 2>&1)
    if ($LASTEXITCODE -ne 0) { Fail ('SQL_COUNTS_FAILED: ' + (($output | Select-Object -First 4) -join ' ')) }
    $row = @($output | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*\d+\|\d+\|\d+\|\d+\|\d+\|\d+\|-?\d+\s*$' } | Select-Object -Last 1)
    if ($row.Count -ne 1) { Fail 'SQL_COUNTS_PARSE_FAILED' }
    $parts = $row[0].Trim().Split('|')
    return [pscustomobject]@{ Sales = [long]$parts[0]; Card = [long]$parts[1]; Cash = [long]$parts[2]; Transfer = [long]$parts[3]; LinkedCash = [long]$parts[4]; Movements = [long]$parts[5]; Available = [long]$parts[6] }
}
function Show-Counts([string]$phase, $counts) {
    Write-Host ("SQL_{0}: Sales={1} Card={2} Cash={3} Transfer={4} CashLinked={5} Movements={6} Available={7}" -f $phase, $counts.Sales, $counts.Card, $counts.Cash, $counts.Transfer, $counts.LinkedCash, $counts.Movements, $counts.Available)
}

try {
    Write-Host '===== P035 - CHECKOUT INVALIDO AISLADO HTTPS / SQL SERVER =====' -ForegroundColor Cyan
    if ($Instancia -ne 'POSWEB_V44_LAB_20261018' -or $Database -ne 'POSFlutter_MvcLab_CheckoutCert_20261018_222511_f300b7c3') {
        Fail 'LAB_TARGET_NOT_ALLOWED: este script solo acepta la instancia y base de laboratorio ya verificadas.'
    }
    if (-not (Test-Path -LiteralPath $harnessSource -PathType Leaf)) { Fail 'MISSING_HARNESS: tests\CertifyMvcPosLab.ps1' }
    if (-not (Test-Path -LiteralPath $sqlCmd -PathType Leaf)) { Fail 'SQLCMD_ODBC_NOT_FOUND' }
    $webDir = Join-Path $Repo 'web\PosFlutter.Web'
    if (-not (Test-Path -LiteralPath $webDir -PathType Container)) { Fail 'WEB_PROJECT_NOT_FOUND' }
    $dotnetCmd = Get-Command dotnet.exe -ErrorAction Stop
    $webAssembly = Get-ChildItem -LiteralPath (Join-Path $webDir 'bin\Release') -Filter 'PosFlutter.Web.dll' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $webAssembly) { Fail 'RELEASE_DLL_NOT_FOUND: compile el proyecto MVC Release en laboratorio.' }
    $existing = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) { Fail "HTTPS_PORT_BUSY: $Port; no se finalizara ningun proceso ajeno." }

    $scriptText = [System.IO.File]::ReadAllText($harnessSource)
    if (-not $scriptText.Contains('POSWEB_V44_LAB_20261018') -or -not $scriptText.Contains($Database)) {
        Fail 'HARNESS_LAB_MISMATCH: no se cambiara la conexion de SQL Server.'
    }
    if ($scriptText -match '(?m)^\s*\$server\s*=\s*Start-Process') { Fail 'HARNESS_STARTS_ANOTHER_HOST: se requiere harness que reutilice el host.' }
    if (-not $scriptText.Contains('http://localhost:7105')) { Fail 'HARNESS_URL_NOT_FOUND: se esperaba http://localhost:7105.' }
    if (-not $scriptText.Contains('LOGIN_HTTP_NET')) { Fail 'HARNESS_LOGIN_NET_MISSING: se esperaba login sin seguimiento de redirecciones P023.' }

    Write-Host '[1/5] SQL Server LocalDB: iniciar y verificar laboratorio'
    # No se considera error si la instancia ya estaba corriendo; la conexion SQL es la comprobacion efectiva.
    & sqllocaldb start $Instancia 2>$null | Out-Null
    $dbCheck = @(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d master -h -1 -W -Q ("SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'" + $Database + "') IS NOT NULL THEN 'LAB_FOUND' ELSE 'LAB_MISSING' END;") 2>&1)
    if ($LASTEXITCODE -ne 0 -or (@($dbCheck | Where-Object { $_ -match 'LAB_FOUND' }).Count -eq 0)) { Fail 'LAB_DATABASE_NOT_FOUND: no se creara otra base.' }
    $before = Get-LabCounts
    Show-Counts 'BEFORE' $before

    Write-Host '[2/5] Crear certificado HTTPS efimero con confianza temporal CurrentUser (no global)'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $pfx = Join-Path $work 'posweb-localhost.pfx'
    $randomBytes = New-Object byte[] 32
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($randomBytes) } finally { $random.Dispose() }
    $pfxPassword = [Convert]::ToBase64String($randomBytes)
    $securePassword = ConvertTo-SecureString -String $pfxPassword -AsPlainText -Force
    $certificate = New-SelfSignedCertificate -DnsName 'localhost' -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotAfter (Get-Date).AddDays(1) -KeyExportPolicy Exportable -KeyAlgorithm RSA -KeyLength 2048 `
        -Type SSLServerAuthentication -ErrorAction Stop
    Export-PfxCertificate -Cert $certificate -FilePath $pfx -Password $securePassword -ErrorAction Stop | Out-Null
    $expectedThumbprint = $certificate.Thumbprint
    # Confiar SOLO en CurrentUser\Root durante esta ejecucion. No afecta LocalMachine.
    # HttpWebRequest de .NET Framework valida TLS mediante Schannel; la confianza
    # del certificado debe existir en el almacen del usuario, no solo en un callback.
    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
    try {
        $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $rootStore.Add($certificate)
        $rootTrustAdded = $true
    }
    finally { $rootStore.Close() }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.WebRequest]::DefaultWebProxy = $null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Host '[3/5] Iniciar Kestrel HTTPS aislado (sin detener HTTP 7105)'
    [Environment]::SetEnvironmentVariable('ConnectionStrings__SqlServer', ('Server=' + $instanceSql + ';Database=' + $Database + ';Integrated Security=true;TrustServerCertificate=true'), 'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS', $base, 'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_Kestrel__Certificates__Default__Path', $pfx, 'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_Kestrel__Certificates__Default__Password', $pfxPassword, 'Process')
    $stdOut = Join-Path $work 'kestrel-stdout.log'
    $stdErr = Join-Path $work 'kestrel-stderr.log'
    $hostProcess = Start-Process -FilePath $dotnetCmd.Source -WorkingDirectory $webDir `
        -ArgumentList @('"' + $webAssembly.FullName + '"', '--contentRoot', '"' + $webDir + '"', '--urls', $base) `
        -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr -PassThru -WindowStyle Hidden
    $ready = $false
    $deadline = (Get-Date).AddSeconds(60)
    do {
        $hostProcess.Refresh()
        if ($hostProcess.HasExited) { Fail "HTTPS_HOST_EXITED: $($hostProcess.ExitCode)" }
        $code = & curl.exe -k --noproxy '*' --connect-timeout 2 --max-time 4 -s -o NUL -w '%{http_code}' "$base/Home/Login" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$code" -eq '200') { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if (-not $ready) { Fail 'HTTPS_HOST_NOT_READY: consulte el log de Kestrel generado.' }
    Write-Host "HTTPS_LOGIN_GET=200 URL=$base/Home/Login"

    Write-Host '[4/5] Ejecutar solo login, catalogo y checkout invalido (sin ventas validas)'
    # Copia efimera: mismo codigo, URL HTTPS. Evitar tener dos Kestrel en el mismo puerto.
    $temporaryHarness = Join-Path $work 'CertifyMvcPosLab-HTTPS.ps1'
    $patched = $scriptText.Replace('http://localhost:7105', $base).Replace('http://127.0.0.1:7105', $base)
    $patched = $patched.Replace("`$env:ASPNETCORE_URLS = 'http://127.0.0.1:7105'", "`$env:ASPNETCORE_URLS = '$base'")
    # P035: fail-closed. No ejecutar ninguna de las tres ventas ni abrir caja.
    # Los patrones deben coincidir exactamente una vez o abortar antes de ejecutar el harness.
    $validPatterns = @(
        '(?m)^\s*\$card\s*=\s*Checkout\s+Card\s*;\s*\$transfer\s*=\s*Checkout\s+Transfer\s*$',
        '(?m)^\s*\$cashOpen\s*=\s*Invoke-WebRequest[^\r\n]*$',
        '(?m)^\s*\$cash\s*=\s*Checkout\s+Cash\s+2000\s*$'
    )
    foreach ($pattern in $validPatterns) {
        if ([regex]::Matches($patched, $pattern).Count -ne 1) { Fail 'P035_GUARD_FAILED: secuencia de ventas/caja no reconocida; no se ejecutara el harness.' }
        $patched = [regex]::Replace($patched, $pattern, '')
    }
    # El resumen original hace referencia a ventas eliminadas. Sustituirlo por una marca inequívoca.
    $summaryPattern = '(?m)^\s*"LOGIN=\$\(\$response\.StatusCode\);CATALOG=[^\r\n]*$'
    if ([regex]::Matches($patched, $summaryPattern).Count -ne 1) { Fail 'P035_SUMMARY_GUARD_FAILED' }
    $patched = [regex]::Replace($patched, $summaryPattern, '  "P035_HARNESS_NEGATIVE_ONLY=COMPLETE"')
    if (-not $patched.Contains('INVALID_CHECKOUT_EXPECTED_400') -or -not $patched.Contains('INVALID_CHECKOUT_HTTP=400')) {
        Fail 'P035_INVALID_HANDLER_MISSING: aplique primero P033.'
    }
    # Verificar que no queden invocaciones de Checkout para pagos válidos.
    if ($patched -match '(?m)^\s*\$\w+\s*=\s*Checkout\s+(Card|Transfer|Cash)\b') {
        Fail 'P035_UNSAFE_VALID_CHECKOUT_REMAINS'
    }
    # Todas las llamadas Invoke-WebRequest en PS 5.1 deben evitar el motor HTML de IE.
    $patched = [regex]::Replace($patched, 'Invoke-WebRequest(?![^\r\n]*-UseBasicParsing)', 'Invoke-WebRequest -UseBasicParsing')
    $tokens = $null; $syntaxErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($patched, [ref]$tokens, [ref]$syntaxErrors) | Out-Null
    if ($syntaxErrors.Count -gt 0) { Fail ('HARNESS_SYNTAX_FAILED: ' + $syntaxErrors[0].Message) }
    [System.IO.File]::WriteAllText($temporaryHarness, $patched, (New-Object System.Text.UTF8Encoding($false)))
    $negativeMarkerSeen = $false
    $completeMarkerSeen = $false
    Push-Location $Repo
    try {
        # No imprimir tokens de antifalsificacion ni valores de cookies.
        & $temporaryHarness | ForEach-Object {
            $line = [string]$_
            if ($line -eq 'INVALID_CHECKOUT_HTTP=400') { $negativeMarkerSeen = $true }
            if ($line -eq 'P035_HARNESS_NEGATIVE_ONLY=COMPLETE') { $completeMarkerSeen = $true }
            if ($line -notmatch '(?i)(password|cookie:|authorization:|set-cookie:|requestverificationtoken|x-csrf-token)') {
                Write-Host $line
            }
        }
    }
    finally { Pop-Location }
    if (-not $negativeMarkerSeen -or -not $completeMarkerSeen) { Fail 'P035_HTTP_400_NOT_CONFIRMED' }
    Write-Host '[5/5] Verificar que SQL Server no cambio (ventas, pagos e inventario)'
    $after = Get-LabCounts
    Show-Counts 'AFTER' $after
    $deltaSales = $after.Sales - $before.Sales
    $deltaCard = $after.Card - $before.Card
    $deltaCash = $after.Cash - $before.Cash
    $deltaTransfer = $after.Transfer - $before.Transfer
    $deltaMovements = $after.Movements - $before.Movements
    $deltaAvailable = $after.Available - $before.Available
    $deltaCashLinked = $after.LinkedCash - $before.LinkedCash
    Write-Host "SQL_DELTA: Sales=$deltaSales Card=$deltaCard Cash=$deltaCash Transfer=$deltaTransfer CashLinked=$deltaCashLinked Movements=$deltaMovements Available=$deltaAvailable"

    if ($deltaSales -ne 0 -or $deltaCard -ne 0 -or $deltaCash -ne 0 -or $deltaTransfer -ne 0 `
         -or $deltaCashLinked -ne 0 -or $deltaMovements -ne 0 -or $deltaAvailable -ne 0) {
        Fail 'P035_SQL_UNCHANGED_FAILED: cambios inesperados; NO se certifica el rechazo.'
    }
    Write-Host 'P035_HTTP_400=PASS'
    Write-Host 'P035_SQL_UNCHANGED=PASS'
    $exitState = 'PASS'
    Write-Host 'P035_CERTIFICATION=PASS' -ForegroundColor Green
}
catch {
    Write-Host 'P035_CERTIFICATION=FAIL' -ForegroundColor Red
    Write-Host ('FAIL_REASON=' + $_.Exception.Message) -ForegroundColor Red
    if ($null -ne $hostProcess) {
        if (Test-Path -LiteralPath (Join-Path $work 'kestrel-stderr.log')) {
            $tail = @(Get-Content (Join-Path $work 'kestrel-stderr.log') -Tail 8 -ErrorAction SilentlyContinue)
            foreach ($line in $tail) { if ($line -notmatch '(?i)(password|cookie|secret|token|connectionstring)') { Write-Host ('KESTREL: ' + $line) } }
        }
        if (Test-Path -LiteralPath (Join-Path $work 'kestrel-stdout.log')) {
            $tail = @(Get-Content (Join-Path $work 'kestrel-stdout.log') -Tail 8 -ErrorAction SilentlyContinue)
            foreach ($line in $tail) { if ($line -notmatch '(?i)(password|cookie|secret|token|connectionstring)') { Write-Host ('KESTREL: ' + $line) } }
        }
    }
}
finally {
    if ($null -ne $hostProcess) {
        try {
            $hostProcess.Refresh()
            if (-not $hostProcess.HasExited) { Stop-Process -Id $hostProcess.Id -Force -ErrorAction Stop }
        } catch { Write-Warning ('HOST_CLEANUP_WARNING: ' + $_.Exception.Message) }
    }
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCertCallback
    if ($rootTrustAdded -and $null -ne $certificate) {
        try {
            $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
            try {
                $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                $rootStore.Remove($certificate)
            } finally { $rootStore.Close() }
        } catch { Write-Warning ('ROOT_TRUST_CLEANUP_WARNING: ' + $_.Exception.Message) }
    }
    [System.Net.WebRequest]::DefaultWebProxy = $originalProxy
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $oldEnv[$name], 'Process') }
    if ($null -ne $certificate) {
        try { Remove-Item -LiteralPath ('Cert:\CurrentUser\My\' + $certificate.Thumbprint) -Force -ErrorAction Stop }
        catch { Write-Warning ('CERT_CLEANUP_WARNING: ' + $_.Exception.Message) }
    }
    # Conservar logs de fallo para diagnostico sin exponer credenciales; borrar PFX siempre.
    if (Test-Path -LiteralPath $work) {
        $sensitiveFiles = @((Join-Path $work 'posweb-localhost.pfx'), (Join-Path $work 'CertifyMvcPosLab-HTTPS.ps1'))
        foreach ($f in $sensitiveFiles) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
        if ($exitState -eq 'PASS') { Remove-Item -LiteralPath $work -Force -Recurse -ErrorAction SilentlyContinue }
        else { Write-Host ('DIAGNOSTIC_LOG_DIR=' + $work) }
    }
}
if ($exitState -ne 'PASS') { exit 1 }
exit 0
