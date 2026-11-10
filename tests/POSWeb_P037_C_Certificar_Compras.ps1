#requires -Version 5.1
[CmdletBinding()]
param(
 [string]$Repo='C:\POSFlutter_Web\POSFlutter_Original',
 [string]$Instancia='POSWEB_V44_LAB_20261018',
 [string]$Database='POSFlutter_MvcLab_P037_PurchaseCert_20261019',
 [int]$Port=7146,
 [string]$LabUsername='web.lab',
 [string]$PublishDll=''
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$hostProcess=$null;$exitState='FAIL'
$originalProxy=[System.Net.WebRequest]::DefaultWebProxy
$envNames=@('ConnectionStrings__SqlServer','ASPNETCORE_URLS')
$oldEnv=@{};foreach($name in $envNames){$oldEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$work=Join-Path $env:TEMP ('POSWEB_P037_'+[guid]::NewGuid().ToString('N'))
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
 $request=[System.Net.HttpWebRequest]::Create($base+$path)
 $request.Method=$method;$request.AllowAutoRedirect=$false;$request.CookieContainer=$script:session.Cookies;$request.Timeout=20000;$request.Proxy=$null
 if($method -eq 'POST'){
   $request.ContentType='application/json';$request.Headers['X-CSRF-TOKEN']=$script:csrf
   $bytes=[Text.Encoding]::UTF8.GetBytes(($data|ConvertTo-Json -Compress -Depth 8));$request.ContentLength=$bytes.Length
   $stream=$request.GetRequestStream();try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
 }
 try{$response=$request.GetResponse()}catch [System.Net.WebException]{$response=$_.Exception.Response}
 if($null -eq $response){throw 'HTTP_JSON_NO_RESPONSE'}
 try{$reader=New-Object System.IO.StreamReader($response.GetResponseStream());try{$body=$reader.ReadToEnd()}finally{$reader.Dispose()};return [pscustomobject]@{Code=[int]$response.StatusCode;Body=$body}}finally{$response.Dispose()}
}
try{
 Write-Host '===== P037-C - CERTIFICACION HTTPS COMPRAS =====' -ForegroundColor Cyan
 Assert (($Database -match '^(POSFlutter_MvcLab_|POSWEB_AV98_INVENTORY_)') -and $LabUsername -ceq 'web.lab') 'LAB_TARGET_NOT_ALLOWED'
 Assert (Test-Path -LiteralPath $sqlCmd) 'SQLCMD_NOT_FOUND'
 $webDir=Join-Path $Repo 'web\PosFlutter.Web'
 Assert (Test-Path $webDir) 'WEB_DIR_NOT_FOUND'
 $dotnetCmd=Get-Command dotnet.exe -ErrorAction Stop
 $webAssembly=if($PublishDll){Get-Item -LiteralPath $PublishDll -ErrorAction SilentlyContinue}else{Get-ChildItem -LiteralPath (Join-Path $webDir 'bin\Release') -Filter 'PosFlutter.Web.dll' -File -Recurse -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1}
 Assert ($null -ne $webAssembly) 'RELEASE_DLL_NOT_FOUND'
 if($PublishDll){$webDir=$webAssembly.Directory.FullName}
 Assert (@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count -eq 0) 'HTTPS_PORT_BUSY'
 & sqllocaldb start $Instancia 2>$null | Out-Null
 $check=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d master -h -1 -W -Q "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'$Database') IS NULL THEN 'MISSING' ELSE 'FOUND' END;" 2>&1)
 Assert ($LASTEXITCODE -eq 0 -and @($check|Where-Object{$_ -match 'FOUND'}).Count -eq 1) 'LAB_DATABASE_NOT_FOUND'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Purchases') -eq 0) 'PURCHASES_ALREADY_EXIST'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.PurchaseLines') -eq 0) 'PURCHASE_LINES_ALREADY_EXIST'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.InventoryMovements WHERE Type='Purchase'") -eq 0) 'PURCHASE_MOVEMENTS_ALREADY_EXIST'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.SyncChanges WHERE EntityType='Purchase'") -eq 0) 'PURCHASE_SYNC_ALREADY_EXIST'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Sales') -eq 0) 'SALES_ALREADY_EXIST'
 $inventoryBefore=SqlScalar 'SELECT COALESCE(SUM(CAST(AvailableQuantity AS BIGINT)),0) FROM dbo.InventoryLots'
 $lotsBefore=SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.InventoryLots'
 $movementsBefore=SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.InventoryMovements'
 Assert ($inventoryBefore -eq 10 -and $lotsBefore -eq 1) 'UNEXPECTED_INITIAL_INVENTORY'
 Write-Host 'SQL_BASELINE=PASS Purchases=0 Lines=0 Lots=1 Stock=10'
    Write-Host '[2/6] Reutilizar certificado HTTPS de desarrollo existente'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    & dotnet dev-certs https --check | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'HTTPS_DEVELOPMENT_CERTIFICATE_UNAVAILABLE'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::Expect100Continue = $false
    [System.Net.WebRequest]::DefaultWebProxy = $null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Host '[3/6] Iniciar Kestrel HTTPS aislado (sin detener HTTP 7105)'
    [Environment]::SetEnvironmentVariable('ConnectionStrings__SqlServer', ('Server=' + $instanceSql + ';Database=' + $Database + ';Integrated Security=true;TrustServerCertificate=true'), 'Process')
    [Environment]::SetEnvironmentVariable('ASPNETCORE_URLS', $base, 'Process')
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
        try { $probe=Invoke-WebRequest -Uri "$base/Home/Login" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop; if($probe.StatusCode -eq 200){$ready=$true;break} } catch {}
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
 $authenticatedPage=Invoke-WebRequest -Uri "$base/" -WebSession $script:session -UseBasicParsing -TimeoutSec 20
 Assert ($authenticatedPage.StatusCode -eq 200) 'AUTHENTICATED_HOME_FAILED'
 $meta=[regex]::Match($authenticatedPage.Content,'<meta\b(?=[^>]*\bname\s*=\s*["'']pos-csrf["''])(?=[^>]*\bcontent\s*=\s*["'']([^"'']+)["''])[^>]*>',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
 Assert $meta.Success 'CASH_CSRF_META_MISSING'
 $script:csrf=[System.Net.WebUtility]::HtmlDecode($meta.Groups[1].Value)
 Write-Host 'LOGIN_HTTPS=PASS'
 Write-Host '[5/6] Compra HTTPS, replay, conflicto y validaciones'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Purchases') -eq 0 -and (SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.PurchaseLines') -eq 0) 'LAB_NOT_EMPTY_BEFORE_WRITE'
 $supplierId=$null;$productId=$null
 $lookup=@"
SET NOCOUNT ON;
SELECT CONVERT(varchar(36),br.GlobalId)+'|'+CONVERT(varchar(36),u.GlobalId)
FROM dbo.Businesses b JOIN dbo.Branches br ON br.BusinessId=b.Id
JOIN dbo.Users u ON u.BusinessId=b.Id
WHERE b.GlobalId='$($ids[0])' AND u.Username='$LabUsername' AND br.Active=1 AND u.Active=1;
"@
 $look=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d $Database -h -1 -W -Q $lookup 2>&1)
 Assert ($LASTEXITCODE -eq 0) 'BRANCH_USER_LOOKUP_FAILED'
 $matching=@($look|Where-Object{[string]$_ -match '^[0-9a-fA-F-]{36}\|[0-9a-fA-F-]{36}$'})
 Assert ($matching.Count -eq 1) 'BRANCH_USER_NOT_UNIQUE'
 $contextIds=([string]$matching[0]).Split('|')
 $supplierLookup=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d $Database -h -1 -W -Q "SET NOCOUNT ON; SELECT TOP 1 CONVERT(varchar(36),s.GlobalId) FROM dbo.Suppliers s JOIN dbo.Businesses b ON b.Id=s.BusinessId WHERE b.GlobalId='$($ids[0])' AND s.Active=1;" 2>&1)
 $productLookup=@(& $sqlCmd -S $instanceSql -E -C -b -l 15 -d $Database -h -1 -W -Q "SET NOCOUNT ON; SELECT TOP 1 CONVERT(varchar(36),p.GlobalId) FROM dbo.Products p JOIN dbo.Businesses b ON b.Id=p.BusinessId WHERE b.GlobalId='$($ids[0])' AND p.Active=1;" 2>&1)
 $supplierId=@($supplierLookup|Where-Object{$_ -match '^[0-9a-fA-F-]{36}$'}|Select-Object -First 1);$productId=@($productLookup|Where-Object{$_ -match '^[0-9a-fA-F-]{36}$'}|Select-Object -First 1)
 Assert ($supplierId -and $productId) 'LAB_SUPPLIER_OR_PRODUCT_NOT_FOUND'
  $supplierId = [guid]::Parse([string]$supplierId[0]).ToString()
  $productId = [guid]::Parse([string]$productId[0]).ToString()
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.Suppliers WHERE GlobalId='$supplierId' AND Active=1") -eq 1) 'SUPPLIER_NOT_FOUND'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.Products WHERE GlobalId='$productId' AND Active=1") -eq 1) 'PRODUCT_NOT_FOUND'
 $purchaseId=[guid]::NewGuid();$detailId=[guid]::NewGuid();$lotId=[guid]::NewGuid()
 $date=[DateTimeOffset]::UtcNow.ToString('o')
 $payload=@{globalId="$purchaseId";businessGlobalId=$ids[0];branchGlobalId=$contextIds[0];deviceGlobalId=$ids[1];userGlobalId=$contextIds[1];supplierGlobalId=$supplierId;date=$date;reference='P037 HTTPS lab';notes='Isolated purchase certification';totalCents=12000;lines=@(@{detailGlobalId="$detailId";productGlobalId=$productId;quantity=5;unitCostCents=2400;subtotalCents=12000;lotGlobalId="$lotId"})}
 $created=CallJson 'POST' '/purchases' $payload
 Write-Host ('PURCHASE_CREATE_HTTP='+$created.Code+' BODY='+($created.Body -replace '[\r\n]+',' '))
 Assert ($created.Code -eq 200) ('PURCHASE_CREATE_HTTP_'+$created.Code)
 $createdBody=$created.Body|ConvertFrom-Json
 Assert ($createdBody.replay -eq $false -and [long]$createdBody.totalCents -eq 12000 -and "$($createdBody.globalId)" -eq "$purchaseId") 'PURCHASE_CREATE_RESPONSE_INVALID'
 Write-Host 'PURCHASE_CREATE=PASS HTTP=200 TotalCents=12000'
 $replay=CallJson 'POST' '/purchases' $payload
 Assert ($replay.Code -eq 200 -and ($replay.Body|ConvertFrom-Json).replay -eq $true) 'PURCHASE_REPLAY_FAILED'
 $changed=@{}+$payload;$changed.totalCents=12001
 $conflict=CallJson 'POST' '/purchases' $changed
 Assert ($conflict.Code -eq 409) ('PURCHASE_CONFLICT_EXPECTED_409_ACTUAL_'+$conflict.Code)
 Write-Host 'PURCHASE_REPLAY=PASS CONFLICT_HTTP=409'
 $invalidTotal=@{}+$payload;$invalidTotal.globalId="$([guid]::NewGuid())";$invalidTotal.totalCents=12001
 $badTotal=CallJson 'POST' '/purchases' $invalidTotal
 Assert ($badTotal.Code -eq 400) ('INVALID_TOTAL_EXPECTED_400_ACTUAL_'+$badTotal.Code)
 $invalidQty=@{}+$payload;$invalidQty.globalId="$([guid]::NewGuid())";$invalidQty.lines=@(@{detailGlobalId="$([guid]::NewGuid())";productGlobalId=$productId;quantity=0;unitCostCents=2400;subtotalCents=0;lotGlobalId="$([guid]::NewGuid())"})
 $badQty=CallJson 'POST' '/purchases' $invalidQty
 Assert ($badQty.Code -eq 400) ('INVALID_QTY_EXPECTED_400_ACTUAL_'+$badQty.Code)
 Write-Host 'INVALID_TOTAL=400 INVALID_QUANTITY=400'
 Write-Host '[6/6] Auditoria SQL persistente'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.Purchases WHERE GlobalId='$purchaseId' AND TotalCents=12000 AND Status='Confirmed'") -eq 1) 'SQL_PURCHASE_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Purchases') -eq 1) 'SQL_PURCHASE_DUPLICATE'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.PurchaseLines WHERE GlobalId='$detailId' AND Quantity=5 AND UnitCostCents=2400 AND SubtotalCents=12000") -eq 1) 'SQL_PURCHASE_LINE_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.PurchaseLines') -eq 1) 'SQL_PURCHASE_LINE_DUPLICATE'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.InventoryLots WHERE GlobalId='$lotId' AND ProductGlobalId='$productId' AND InitialQuantity=5 AND AvailableQuantity=5 AND UnitCostCents=2400 AND PurchaseLineGlobalId='$detailId'") -eq 1) 'SQL_PURCHASE_LOT_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.InventoryLots') -eq ($lotsBefore+1)) 'SQL_LOT_COUNT_INVALID'
 Assert ((SqlScalar 'SELECT COALESCE(SUM(CAST(AvailableQuantity AS BIGINT)),0) FROM dbo.InventoryLots') -eq ($inventoryBefore+5)) 'SQL_STOCK_INVALID'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.InventoryMovements WHERE ReferenceGlobalId='$purchaseId' AND Type='Purchase' AND QuantityDelta=5 AND PreviousStock=10 AND NewStock=15") -eq 1) 'SQL_PURCHASE_MOVEMENT_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.InventoryMovements') -eq ($movementsBefore+1)) 'SQL_MOVEMENT_COUNT_INVALID'
 Assert ((SqlScalar "SELECT COUNT_BIG(*) FROM dbo.SyncChanges WHERE EntityType='Purchase' AND EntityGlobalId='$purchaseId'") -eq 1) 'SQL_PURCHASE_SYNC_INVALID'
 Assert ((SqlScalar 'SELECT COUNT_BIG(*) FROM dbo.Sales') -eq 0) 'SQL_SALES_CHANGED'
 Write-Host 'P037_SQL_AUDIT=PASS Purchases=1 Lines=1 LotsAdded=1 Stock=15 MovementsAdded=1 SyncChanges=1 Sales=0'
 $exitState='PASS'
 Write-Host 'P037_PURCHASE_CERTIFICATION=PASS' -ForegroundColor Green
}
catch{
 Write-Host ('P037_PURCHASE_CERTIFICATION=FAIL REASON='+$_.Exception.Message) -ForegroundColor Red
}
finally{
 if($null -ne $hostProcess){try{$hostProcess.Refresh();if(-not $hostProcess.HasExited){Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue}}catch{}}
 foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$oldEnv[$name],'Process')}
 [System.Net.WebRequest]::DefaultWebProxy=$originalProxy
 if(Test-Path $work){Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue}
}
if($exitState -eq 'PASS'){exit 0}else{exit 1}
