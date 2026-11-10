#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$Repo='C:\POSFlutter_Web\POSFlutter_Original',
 [string]$Instancia='POSWEB_V44_LAB_20261018',
 [string]$Database='POSFlutter_MvcLab_P036_CashCert_20261019',
 [int]$Port=7145,
 [string]$LabUsername='web.lab'
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$hostProcess=$null;$certificate=$null;$rootTrustAdded=$false;$exitState='FAIL'
$originalCertCallback=[System.Net.ServicePointManager]::ServerCertificateValidationCallback
$originalProxy=[System.Net.WebRequest]::DefaultWebProxy
$envNames=@('ConnectionStrings__SqlServer','ASPNETCORE_URLS','ASPNETCORE_Kestrel__Certificates__Default__Path','ASPNETCORE_Kestrel__Certificates__Default__Password')
$oldEnv=@{};foreach($name in $envNames){$oldEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$work=Join-Path $env:TEMP ('POSWEB_P036_'+[guid]::NewGuid().ToString('N'))
$base='https://localhost:'+$Port
$sqlCmd='C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
$instanceSql='(localdb)\'+$Instancia
function Fail([string]$reason){throw $reason}
function SqlScalar([string]$query){
 $result=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d $Database -h -1 -W -Q $query 2>&1)
 if($LASTEXITCODE -ne 0){Fail ('SQL_FAILED '+(($result|Select-Object -First 2)-join ' '))}
 $values=@($result|ForEach-Object{[string]$_}|Where-Object{$_.Trim() -match '^-?\d+$'})
 if($values.Count -ne 1){Fail ('SQL_RESULT_UNEXPECTED '+($result -join ' '))}
 return [long]$values[0].Trim()
}
function Assert([bool]$ok,[string]$reason){if(-not $ok){Fail $reason}}
function CallJson([string]$method,[string]$path,$data=$null){
 $params=@{Uri=($base+$path);WebSession=$script:session;Method=$method;UseBasicParsing=$true;TimeoutSec=20;MaximumRedirection=0;ErrorAction='Stop'}
 if($method -eq 'POST'){$params['ContentType']='application/json';$params['Headers']=@{'X-CSRF-TOKEN'=$script:csrf};$params['Body']=($data|ConvertTo-Json -Compress -Depth 8)}
 try{$r=Invoke-WebRequest @params;return [pscustomobject]@{Code=[int]$r.StatusCode;Body=[string]$r.Content}}
 catch [System.Net.WebException]{
   $response=$_.Exception.Response
   if($null -eq $response){throw}
   $code=[int]$response.StatusCode
   $reader=New-Object System.IO.StreamReader($response.GetResponseStream())
   try{$body=$reader.ReadToEnd()}finally{$reader.Dispose();$response.Dispose()}
   return [pscustomobject]@{Code=$code;Body=$body}
 }
}
try{
 Write-Host '===== P036-C4 - CERTIFICACION HTTPS CAJA =====' -ForegroundColor Cyan
 Assert ($Instancia -ceq 'POSWEB_V44_LAB_20261018' -and $Database -ceq 'POSFlutter_MvcLab_P036_CashCert_20261019' -and $LabUsername -ceq 'web.lab') 'LAB_TARGET_NOT_ALLOWED'
 Assert (Test-Path -LiteralPath $sqlCmd) 'SQLCMD_NOT_FOUND'
 $webDir=Join-Path $Repo 'web\PosFlutter.Web'
 Assert (Test-Path $webDir) 'WEB_DIR_NOT_FOUND'
 $dotnetCmd=Get-Command dotnet.exe -ErrorAction Stop
 $webAssembly=Get-ChildItem -LiteralPath (Join-Path $webDir 'bin\Release') -Filter 'PosFlutter.Web.dll' -File -Recurse -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
 Assert ($null -ne $webAssembly) 'RELEASE_DLL_NOT_FOUND'
 Assert (@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count -eq 0) 'HTTPS_PORT_BUSY'
 & sqllocaldb start $Instancia 2>$null | Out-Null
 $check=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d master -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'$Database') IS NULL THEN 'MISSING' ELSE 'FOUND' END;" 2>&1)
 Assert ($LASTEXITCODE -eq 0 -and @($check|Where-Object{$_ -match 'FOUND'}).Count -eq 1) 'LAB_DATABASE_NOT_FOUND'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.CashSessions') -eq 0) 'CASH_SESSIONS_ALREADY_EXIST'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.CashMovements') -eq 0) 'CASH_MOVEMENTS_ALREADY_EXIST'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Sales') -eq 0) 'LAB_SALES_ALREADY_EXIST'
 $inventoryBefore=SqlScalar 'SELECT COALESCE(SUM(CAST(AvailableQuantity AS BIGINT)),0) FROM dbo.InventoryLots'
 $movementsBefore=SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.InventoryMovements'
 Write-Host 'SQL_BASELINE=PASS Sales=0 CashSessions=0 CashMovements=0'
    Write-Host '[2/6] Crear certificado HTTPS efimero con confianza temporal CurrentUser (no global)'
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

    Write-Host '[3/6] Iniciar Kestrel HTTPS aislado (sin detener HTTP 7105)'
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


 Write-Host '[4/6] Autenticacion HTTPS'
 $script:session=New-Object Microsoft.PowerShell.Commands.WebRequestSession
 $login=Invoke-WebRequest -Uri "$base/Home/Login" -WebSession $script:session -UseBasicParsing -TimeoutSec 20
 Assert ($login.StatusCode -eq 200) 'LOGIN_PAGE_FAILED'
 $tokenMatch=[regex]::Match($login.Content,'<input\b(?=[^>]*\bname\s*=\s*["'']__RequestVerificationToken["''])(?=[^>]*\bvalue\s*=\s*["'']([^"'']+)["''])[^>]*>',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
 Assert $tokenMatch.Success 'LOGIN_CSRF_NOT_FOUND'
 $loginToken=[System.Net.WebUtility]::HtmlDecode($tokenMatch.Groups[1].Value)
 $identityQuery=@"
SET NOCOUNT ON;
SELECT TOP 1 CONVERT(varchar(36),b.GlobalId)+'|'+CONVERT(varchar(36),d.GlobalId)
FROM dbo.Businesses b JOIN dbo.Branches br ON br.BusinessId=b.Id
JOIN dbo.Devices d ON d.BranchId=br.Id JOIN dbo.Users u ON u.BusinessId=b.Id
WHERE b.Active=1 AND br.Active=1 AND d.Active=1 AND u.Active=1
AND d.Mode='PointOfSale' AND u.Username='$LabUsername' AND u.Role='Administrator';
"@
 $identityOutput=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d $Database -h -1 -W -Q $identityQuery 2>&1)
 Assert ($LASTEXITCODE -eq 0) 'LAB_IDENTITY_SQL_FAILED'
 $identity=@($identityOutput|Where-Object{[string]$_ -match '^[0-9a-fA-F-]{36}\|[0-9a-fA-F-]{36}$'})
 Assert ($identity.Count -eq 1) 'LAB_IDENTITY_NOT_FOUND'
 $ids=([string]$identity[0]).Split('|')
 $password=[Environment]::GetEnvironmentVariable('POSFLUTTER_LAB_PASSWORD','Process')
 Assert (-not [string]::IsNullOrWhiteSpace($password)) 'POSFLUTTER_LAB_PASSWORD_MISSING_IN_PROCESS'
 Write-Host 'LOGIN_PASSWORD_SOURCE=PROCESS_ENVIRONMENT (value hidden)'
 try{
  # HttpWebRequest evita el fallo de estado interno de Invoke-WebRequest
  # con -MaximumRedirection 0 en Windows PowerShell 5.1.
  $form=[ordered]@{BusinessGlobalId=$ids[0];DeviceGlobalId=$ids[1];Username=$LabUsername;Password=$password;__RequestVerificationToken=$loginToken}
  $pairs=foreach($field in $form.GetEnumerator()){
   [uri]::EscapeDataString([string]$field.Key)+'='+[uri]::EscapeDataString([string]$field.Value)
  }
  $bytes=[System.Text.Encoding]::UTF8.GetBytes(($pairs -join '&'))
  $request=[System.Net.HttpWebRequest]::Create("$base/Home/Login")
  $request.Method='POST'
  $request.ContentType='application/x-www-form-urlencoded'
  $request.AllowAutoRedirect=$false
  $request.CookieContainer=$script:session.Cookies
  $request.Proxy=$null
  $request.Timeout=20000
  $request.ContentLength=$bytes.Length
  $stream=$request.GetRequestStream()
  try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
  $loginResponse=$null
  try{$loginResponse=$request.GetResponse()}
  catch [System.Net.WebException]{
   if($null -eq $_.Exception.Response){throw}
   $loginResponse=$_.Exception.Response
  }
  try{
   $loginCode=[int]$loginResponse.StatusCode
   $loginPost=$null
   if($loginCode -eq 200){
    $reader=New-Object System.IO.StreamReader($loginResponse.GetResponseStream())
    try{$loginPost=[pscustomobject]@{Content=$reader.ReadToEnd()}}finally{$reader.Dispose()}
   }
  }finally{if($null -ne $loginResponse){$loginResponse.Dispose()}}
 }finally{
  $password=$null
  if($null -ne $form){$form.Clear()}
  $bytes=$null
 }

 if ($loginCode -eq 200) {
  # A 200 response means the MVC login form was returned, not an authenticated session.
  # Report only known validation messages; never print password, form fields or HTML.
  $safeMessage='UNSPECIFIED_LOGIN_REJECTION'
  if ($null -ne $loginPost -and $null -ne $loginPost.Content) {
   $html=[string]$loginPost.Content
   if ($html -match 'Datos de acceso incompletos') { $safeMessage='INCOMPLETE_LOGIN_FIELDS_OR_MODEL' }
   elseif ($html -match 'Acceso rechazado') { $safeMessage='CREDENTIALS_OR_TENANT_REJECTED' }
   elseif ($html -match 'Servidor de datos no disponible') { $safeMessage='DATABASE_LOGIN_ERROR' }
  }
  Fail ('LOGIN_POST_FAILED_HTTP_200_REASON_'+$safeMessage)
 }
 Assert ($loginCode -in @(302,303)) ('LOGIN_POST_FAILED_HTTP_'+$loginCode)
 $home=Invoke-WebRequest -Uri "$base/" -WebSession $script:session -UseBasicParsing -TimeoutSec 20
 Assert ($home.StatusCode -eq 200) 'AUTHENTICATED_HOME_FAILED'
 $meta=[regex]::Match($home.Content,'<meta\b(?=[^>]*\bname\s*=\s*["'']pos-csrf["''])(?=[^>]*\bcontent\s*=\s*["'']([^"'']+)["''])[^>]*>',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
 Assert $meta.Success 'CASH_CSRF_META_MISSING'
 $script:csrf=[System.Net.WebUtility]::HtmlDecode($meta.Groups[1].Value)
 Write-Host 'LOGIN_HTTPS=PASS'
 Write-Host '[5/6] Apertura, idempotencia, conciliacion y cierre'
 # Final fail-closed SQL precondition immediately before first write.
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.CashSessions') -eq 0 -and (SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.CashMovements') -eq 0) 'LAB_NOT_EMPTY_BEFORE_WRITE'
 $open=CallJson 'POST' '/cash-operations/open' @{openingBalanceCents=10000}
 Assert ($open.Code -eq 200) ('OPEN_FAILED_HTTP_'+$open.Code)
 $opened=$open.Body|ConvertFrom-Json
 $sid=[guid]$opened.globalId
 Assert ($sid -ne [guid]::Empty) 'OPEN_SESSION_ID_EMPTY'
 Write-Host 'OPEN_HTTP=200'
 $duplicate=CallJson 'POST' '/cash-operations/open' @{openingBalanceCents=10000}
 Assert ($duplicate.Code -eq 409) ('DUPLICATE_OPEN_EXPECTED_409_ACTUAL_'+$duplicate.Code)
 Write-Host 'DUPLICATE_OPEN_HTTP=409'
 $inId=[guid]::NewGuid();$outId=[guid]::NewGuid()
 $in=@{cashSessionGlobalId="$sid";operationGlobalId="$inId";type='In';amountCents=2500;notes='P036 automated lab in'}
 $out=@{cashSessionGlobalId="$sid";operationGlobalId="$outId";type='Out';amountCents=700;notes='P036 automated lab out'}
 $first=CallJson 'POST' '/cash-operations/movement' $in
 Assert ($first.Code -eq 200) ('MOVEMENT_IN_FAILED_HTTP_'+$first.Code)
 Assert (-not ($first.Body|ConvertFrom-Json).replay) 'MOVEMENT_IN_UNEXPECTED_REPLAY'
 $replay=CallJson 'POST' '/cash-operations/movement' $in
 Assert ($replay.Code -eq 200 -and ($replay.Body|ConvertFrom-Json).replay) 'MOVEMENT_REPLAY_FAILED'
 $conflict=@{}+$in;$conflict.amountCents=2501
 $changed=CallJson 'POST' '/cash-operations/movement' $conflict
 Assert ($changed.Code -eq 409) ('MOVEMENT_PAYLOAD_CONFLICT_EXPECTED_409_ACTUAL_'+$changed.Code)
 $withdraw=CallJson 'POST' '/cash-operations/movement' $out
 Assert ($withdraw.Code -eq 200) ('MOVEMENT_OUT_FAILED_HTTP_'+$withdraw.Code)
 Write-Host 'MOVEMENT_IN=PASS REPLAY=PASS CONFLICT=409 MOVEMENT_OUT=PASS'
 $preview=CallJson 'GET' '/cash-operations/reconciliation-preview'
 Assert ($preview.Code -eq 200) ('RECONCILIATION_FAILED_HTTP_'+$preview.Code)
 $balance=$preview.Body|ConvertFrom-Json
 Assert ([long]$balance.expectedCashCents -eq 11800) ('EXPECTED_CASH_MISMATCH_'+$balance.expectedCashCents)
 Assert ($balance.closeAuthorized -eq $true) 'CLOSE_NOT_AUTHORIZED_BY_PREVIEW'
 Write-Host 'RECONCILIATION=PASS ExpectedCashCents=11800'
 $close=CallJson 'POST' '/cash-operations/close' @{sessionGlobalId="$sid";countedCashCents=11800}
 Assert ($close.Code -eq 200) ('CLOSE_FAILED_HTTP_'+$close.Code)
 $closed=$close.Body|ConvertFrom-Json
 Assert ($closed.status -eq 'Closed' -and [long]$closed.differenceCents -eq 0) 'CLOSE_BALANCE_MISMATCH'
 $repeatClose=CallJson 'POST' '/cash-operations/close' @{sessionGlobalId="$sid";countedCashCents=11800}
 Assert ($repeatClose.Code -eq 409) ('REPEAT_CLOSE_EXPECTED_409_ACTUAL_'+$repeatClose.Code)
 $afterClose=CallJson 'POST' '/cash-operations/movement' @{cashSessionGlobalId="$sid";operationGlobalId="$([guid]::NewGuid())";type='In';amountCents=100;notes='P036 rejected after close'}
 Assert ($afterClose.Code -eq 409) ('POST_CLOSE_MOVEMENT_EXPECTED_409_ACTUAL_'+$afterClose.Code)
 Write-Host 'CLOSE=PASS DIFFERENCE=0 REPEAT_CLOSE=409 POST_CLOSE_MOVEMENT=409'
 Write-Host '[6/6] Verificacion persistencia SQL'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.CashSessions WHERE Status=''Closed'' AND ExpectedCashCents=11800 AND CountedCashCents=11800 AND DifferenceCents=0') -eq 1) 'SQL_CASH_SESSION_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.CashMovements') -eq 2) 'SQL_MOVEMENT_COUNT_INVALID'
 Assert ((SqlScalar 'SELECT COALESCE(SUM(CAST(AmountCents AS BIGINT)),0) FROM dbo.CashMovements') -eq 1800) 'SQL_MOVEMENT_TOTAL_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Sales') -eq 0) 'SQL_SALES_CHANGED'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.InventoryMovements') -eq $movementsBefore) 'SQL_INVENTORY_MOVEMENTS_CHANGED'
 Assert ((SqlScalar 'SELECT COALESCE(SUM(CAST(AvailableQuantity AS BIGINT)),0) FROM dbo.InventoryLots') -eq $inventoryBefore) 'SQL_INVENTORY_QUANTITY_CHANGED'
 Write-Host 'P036_SQL_AUDIT=PASS CashSessions=1 Closed=1 CashMovements=2 Sales=0 InventoryUnchanged=YES'
 $exitState='PASS'
 Write-Host 'P036_CASH_CERTIFICATION=PASS' -ForegroundColor Green
}
catch{
 Write-Host ('P036_CASH_CERTIFICATION=FAIL REASON='+$_.Exception.Message) -ForegroundColor Red
}
finally{
 if($null -ne $hostProcess){try{$hostProcess.Refresh();if(-not $hostProcess.HasExited){Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue}}catch{}}
 foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$oldEnv[$name],'Process')}
 [System.Net.ServicePointManager]::ServerCertificateValidationCallback=$originalCertCallback
 [System.Net.WebRequest]::DefaultWebProxy=$originalProxy
 if($rootTrustAdded -and $null -ne $certificate){try{$store=New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','CurrentUser');$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite);$store.Remove($certificate);$store.Close()}catch{Write-Host 'WARNING_TEMP_ROOT_CERT_CLEANUP_FAILED'}}
 if($null -ne $certificate){Remove-Item ('Cert:\CurrentUser\My\'+$certificate.Thumbprint) -Force -ErrorAction SilentlyContinue}
 if(Test-Path $work){Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue}
}
if($exitState -eq 'PASS'){exit 0}else{exit 1}
