[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$db=if($env:P042_DATABASE){$env:P042_DATABASE}else{'POSFlutter_MvcLab_P042_Security7_Catalog_20261020'}
$server=if($env:P042_SQL_SERVER){$env:P042_SQL_SERVER}else{'(localdb)\POSWEB_IIS_LAB_20261019'}
$publish=if($env:P042_PUBLISH){$env:P042_PUBLISH}else{'C:\POSFlutter_Web\artifacts\p042-catalog-final-20261020\publish\PosFlutter.Web.dll'}
if($db -notmatch '^(POSFlutter_MvcLab_|POSWEB_AV97_PAYMENTS_)'){throw 'Only an explicitly named disposable laboratory database is allowed.'}
if(!(Test-Path $publish)){throw 'Isolated P042 publish is missing.'}
$bytes=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
$secret=[Convert]::ToBase64String($bytes)
$env:ConnectionStrings__SqlServer="Server=$server;Database=$db;Integrated Security=True;Encrypt=False;TrustServerCertificate=True"
$env:POSFLUTTER_LAB_PASSWORD=$secret
$seed=dotnet run --project "$PSScriptRoot\..\server\tools\MvcLabSeed\MvcLabSeed.csproj" -c Release --no-build
# First use creates the core lab. The second guarded run adds only security fixtures.
if($LASTEXITCODE -eq 0 -and $seed -notmatch 'FOREIGN_BUSINESS='){$seed=dotnet run --project "$PSScriptRoot\..\server\tools\MvcLabSeed\MvcLabSeed.csproj" -c Release --no-build}
if($LASTEXITCODE -ne 0){throw 'P042 seed/password rotation failed.'}
$values=@{};foreach($part in (($seed|Select-Object -Last 1)-split ';')){$k,$v=$part-split '=',2;if($v){$values[$k]=$v}}
if(!$values.BUSINESS -or !$values.DEVICE -or !$values.SELLER -or !$values.FOREIGN_BUSINESS -or !$values.FOREIGN_DEVICE -or !$values.FOREIGN_PRODUCT){throw 'P042 security seed identity output is incomplete.'}
$env:ASPNETCORE_URLS='https://localhost:7444';$env:ASPNETCORE_ENVIRONMENT='Development'
$log=Join-Path $env:TEMP 'p042-kestrel.log';$err=Join-Path $env:TEMP 'p042-kestrel.err.log'
$kestrelProcess=$null
function New-P042Session([string]$business,[string]$device,[string]$username) {
  $initial=Invoke-WebRequest https://localhost:7444/Home/Login -UseBasicParsing -SessionVariable createdSession -TimeoutSec 10
  $initialToken=[regex]::Match($initial.Content,'name="__RequestVerificationToken"[^>]*value="([^"]+)"').Groups[1].Value
  if(!$initialToken){throw 'Security login antiforgery token was not rendered.'}
  $form=@{__RequestVerificationToken=$initialToken;BusinessGlobalId=$business;DeviceGlobalId=$device;Username=$username;Password=$secret}
  $encoded=[string]::Join('&',($form.GetEnumerator()|ForEach-Object{[uri]::EscapeDataString([string]$_.Key)+'='+[uri]::EscapeDataString([string]$_.Value)}))
  $loginRequest=[Net.HttpWebRequest]::Create('https://localhost:7444/Home/Login');$loginRequest.Method='POST';$loginRequest.AllowAutoRedirect=$false;$loginRequest.CookieContainer=$createdSession.Cookies;$loginRequest.ContentType='application/x-www-form-urlencoded';$data=[Text.Encoding]::UTF8.GetBytes($encoded);$loginRequest.ContentLength=$data.Length
  $writer=$loginRequest.GetRequestStream();try{$writer.Write($data,0,$data.Length)}finally{$writer.Dispose()}
  try{$loginResponse=$loginRequest.GetResponse()}catch [Net.WebException]{$loginResponse=$_.Exception.Response};if($null-eq$loginResponse){throw 'Security login did not return HTTP.'};try{$code=[int]$loginResponse.StatusCode}finally{$loginResponse.Dispose()}
  if($code-ne302){throw "Security login for $username returned HTTP $code."}
  $homePage=Invoke-WebRequest https://localhost:7444/ -UseBasicParsing -WebSession $createdSession
  $sessionToken=[regex]::Match($homePage.Content,'meta name="pos-csrf" content="([^"]+)"').Groups[1].Value;if(!$sessionToken){throw 'Security authenticated token was not rendered.'}
  return @{ Session=$createdSession; Token=$sessionToken }
}
function Get-P042RejectedStatus([Exception]$error) {
  if($null -ne $error.Response -and $null -ne $error.Response.StatusCode){return [int]$error.Response.StatusCode}
  throw $error
}
function Invoke-P042Rejected([scriptblock]$operation) { try { & $operation | Out-Null; return 200 } catch { return Get-P042RejectedStatus $_.Exception } }
function Get-P042WriteCount { (& sqlcmd -S $server -d $db -E -h -1 -W -Q "SET NOCOUNT ON;SELECT CONCAT((SELECT COUNT(*) FROM dbo.Sales),'|',(SELECT COUNT(*) FROM dbo.CashSessions),'|',(SELECT COUNT(*) FROM dbo.SyncChanges));") | Select-Object -Last 1 }
try {
  $kestrelProcess=Start-Process dotnet -ArgumentList $publish -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $err
  $deadline=[DateTime]::UtcNow.AddSeconds(45);$health=$null
  while([DateTime]::UtcNow-lt$deadline){try{$health=Invoke-WebRequest https://localhost:7444/health -UseBasicParsing -TimeoutSec 3;if($health.StatusCode-eq200){break}}catch{};Start-Sleep -Milliseconds 400}
  if(!$health){throw 'Kestrel health did not reach HTTP 200.'}
  # AutoValidateAntiforgeryToken rejects the anonymous write before any SQL operation.
  try { Invoke-WebRequest 'https://localhost:7444/cash-operations/open' -UseBasicParsing -Method Post -ContentType 'application/json' -Body '{"openingBalanceCents":0}' -ErrorAction Stop; throw 'Anonymous no-CSRF request unexpectedly succeeded.' }
  catch { $anonymousNoCsrf=Get-P042RejectedStatus $_.Exception }
  if($anonymousNoCsrf -notin @(400,403)){throw "Anonymous no-CSRF returned HTTP $anonymousNoCsrf."}
  $login=Invoke-WebRequest https://localhost:7444/Home/Login -UseBasicParsing -SessionVariable session -TimeoutSec 10
  $csrf=[regex]::Match($login.Content,'name="__RequestVerificationToken"[^>]*value="([^"]+)"').Groups[1].Value
  if(!$csrf){throw 'Login antiforgery token was not rendered.'}
  # A structurally valid, anonymous request with a valid antiforgery pair reaches
  # authorization and must not be mistaken for a successful login redirect.
  try { Invoke-WebRequest 'https://localhost:7444/cash-operations/open' -UseBasicParsing -WebSession $session -Method Post -ContentType 'application/json' -Headers @{'X-CSRF-TOKEN'=$csrf} -Body '{"openingBalanceCents":0}' -ErrorAction Stop; throw 'Anonymous valid-CSRF request unexpectedly succeeded.' }
  catch { $anonymousValidCsrf=Get-P042RejectedStatus $_.Exception }
  if($anonymousValidCsrf -ne401){throw "Anonymous valid-CSRF request returned HTTP $anonymousValidCsrf, expected 401."}
  $form=@{__RequestVerificationToken=$csrf;BusinessGlobalId=$values.BUSINESS;DeviceGlobalId=$values.DEVICE;Username='web.lab';Password=$secret}
  $body=([string]::Join('&',($form.GetEnumerator()|ForEach-Object{[uri]::EscapeDataString([string]$_.Key)+'='+[uri]::EscapeDataString([string]$_.Value)})))
  $request=[Net.HttpWebRequest]::Create('https://localhost:7444/Home/Login');$request.Method='POST';$request.AllowAutoRedirect=$false;$request.CookieContainer=$session.Cookies;$request.ContentType='application/x-www-form-urlencoded';$payload=[Text.Encoding]::UTF8.GetBytes($body);$request.ContentLength=$payload.Length
  $stream=$request.GetRequestStream();try{$stream.Write($payload,0,$payload.Length)}finally{$stream.Dispose()}
  try{$result=$request.GetResponse()}catch [Net.WebException]{$result=$_.Exception.Response};if($null-eq$result){throw 'Login did not return an HTTP response.'}
  $loginStatus=[int]$result.StatusCode;if($loginStatus-ne302){throw "Login returned HTTP $loginStatus."};$result.Dispose()
  $homeResponse=Invoke-WebRequest https://localhost:7444/ -UseBasicParsing -WebSession $session
  $token=[regex]::Match($homeResponse.Content,'meta name="pos-csrf" content="([^"]+)"').Groups[1].Value
  if(!$token){throw 'Authenticated antiforgery token was not rendered.'}
  # This is deliberately after successful login. HttpWebRequest avoids WebSession
  # defaults: only the authenticated cookies and JSON body are sent, never a token.
  $noCsrfRequest=[Net.HttpWebRequest]::Create('https://localhost:7444/cash-operations/open')
  $noCsrfRequest.Method='POST';$noCsrfRequest.AllowAutoRedirect=$false;$noCsrfRequest.CookieContainer=$session.Cookies
  $noCsrfRequest.ContentType='application/json';$noCsrfPayload=[Text.Encoding]::UTF8.GetBytes('{"openingBalanceCents":0}');$noCsrfRequest.ContentLength=$noCsrfPayload.Length
  $noCsrfStream=$noCsrfRequest.GetRequestStream();try{$noCsrfStream.Write($noCsrfPayload,0,$noCsrfPayload.Length)}finally{$noCsrfStream.Dispose()}
  try{$noCsrfResponse=$noCsrfRequest.GetResponse()}catch [Net.WebException]{$noCsrfResponse=$_.Exception.Response}
  if($null-eq$noCsrfResponse){throw 'Authenticated no-CSRF request returned no HTTP response.'}
  try{$authenticatedNoCsrf=[int]$noCsrfResponse.StatusCode}finally{$noCsrfResponse.Dispose()}
  if($authenticatedNoCsrf -notin @(400,403)){throw "Authenticated no-CSRF returned HTTP $authenticatedNoCsrf."}
  $catalog=Invoke-RestMethod https://localhost:7444/data/products -WebSession $session
  if(@($catalog.items).Count-ne1){throw 'Catalog did not return the seeded product.'}
  if($catalog.items[0].PSObject.Properties.Name -notcontains 'availableQuantity' -or [int]$catalog.items[0].availableQuantity -ne 10){throw 'Catalog did not expose the tenant branch availability from the current published assembly.'}
  $product=[guid]$catalog.items[0].globalId;$headers=@{'X-CSRF-TOKEN'=$token}
  # Seller is a valid POS identity but cannot open cash or access financial administration.
  $securityBefore=Get-P042WriteCount
  $sellerSession=New-P042Session $values.BUSINESS $values.DEVICE $values.SELLER_USER
  $sellerHeaders=@{'X-CSRF-TOKEN'=$sellerSession.Token}
  $sellerCash=Invoke-P042Rejected { Invoke-WebRequest 'https://localhost:7444/cash-operations/open' -UseBasicParsing -WebSession $sellerSession.Session -Method Post -ContentType 'application/json' -Headers $sellerHeaders -Body '{"openingBalanceCents":0}' -ErrorAction Stop }
  $sellerReports=Invoke-P042Rejected { Invoke-WebRequest 'https://localhost:7444/reports/admin' -UseBasicParsing -WebSession $sellerSession.Session -ErrorAction Stop }
  if($sellerCash-ne403 -or $sellerReports-ne403){throw "Seller security checks returned cash=$sellerCash reports=$sellerReports."}
  # Pairing a valid business with a device from the foreign tenant must not create a session.
  $badLogin=Invoke-WebRequest https://localhost:7444/Home/Login -UseBasicParsing -SessionVariable badSession
  $badCsrf=[regex]::Match($badLogin.Content,'name="__RequestVerificationToken"[^>]*value="([^"]+)"').Groups[1].Value
  $badForm=@{__RequestVerificationToken=$badCsrf;BusinessGlobalId=$values.BUSINESS;DeviceGlobalId=$values.FOREIGN_DEVICE;Username='web.lab';Password=$secret}
  $badEncoded=[string]::Join('&',($badForm.GetEnumerator()|ForEach-Object{[uri]::EscapeDataString([string]$_.Key)+'='+[uri]::EscapeDataString([string]$_.Value)}))
  $badRequest=[Net.HttpWebRequest]::Create('https://localhost:7444/Home/Login');$badRequest.Method='POST';$badRequest.AllowAutoRedirect=$false;$badRequest.CookieContainer=$badSession.Cookies;$badRequest.ContentType='application/x-www-form-urlencoded';$badBytes=[Text.Encoding]::UTF8.GetBytes($badEncoded);$badRequest.ContentLength=$badBytes.Length
  $badWriter=$badRequest.GetRequestStream();try{$badWriter.Write($badBytes,0,$badBytes.Length)}finally{$badWriter.Dispose()};try{$badResponse=$badRequest.GetResponse()}catch [Net.WebException]{$badResponse=$_.Exception.Response};try{$foreignDeviceLogin=[int]$badResponse.StatusCode}finally{$badResponse.Dispose()}
  $foreignDeviceProducts=Invoke-P042Rejected { Invoke-WebRequest 'https://localhost:7444/data/products' -UseBasicParsing -WebSession $badSession -ErrorAction Stop }
  if($foreignDeviceLogin-ne200 -or $foreignDeviceProducts-ne401){throw "Foreign-device login checks returned login=$foreignDeviceLogin products=$foreignDeviceProducts."}
  if((Get-P042WriteCount)-ne$securityBefore){throw 'Seller-rejected requests modified SQL state.'}
  function Invoke-P042Post([string]$path,$value){Invoke-WebRequest ("https://localhost:7444"+$path) -UseBasicParsing -WebSession $session -Method Post -ContentType 'application/json' -Headers $headers -Body ($value|ConvertTo-Json -Depth 6 -Compress)}
  $cashOpen=Invoke-P042Post '/cash-operations/open' ([ordered]@{openingBalanceCents=0})
  if($cashOpen.StatusCode-ne200){throw "Cash open returned HTTP $($cashOpen.StatusCode)."};$cashSession=(ConvertFrom-Json $cashOpen.Content).globalId
  function Checkout([object[]]$payments,[Nullable[long]]$received=$null,[guid]$key=[guid]::Empty){if($key-eq[guid]::Empty){$key=[guid]::NewGuid()};$request=[ordered]@{idempotencyKey=$key;lines=@([ordered]@{productGlobalId=$product;quantity=1});payments=$payments};if($null-ne$received){$request.receivedCashCents=$received};Invoke-P042Post '/checkout' $request}
  $cardKey=[guid]::NewGuid();$card=Checkout @([ordered]@{method='Card';amountCents=1250}) $null $cardKey;$cardReplay=Checkout @([ordered]@{method='Card';amountCents=1250}) $null $cardKey
  $transfer=Checkout @([ordered]@{method='Transfer';amountCents=1250})
  $cash=Checkout @([ordered]@{method='Cash';amountCents=1250}) 2000
  $mixed=Checkout @([ordered]@{method='Cash';amountCents=500},[ordered]@{method='Card';amountCents=750}) 500
  if(@($card.StatusCode,$cardReplay.StatusCode,$transfer.StatusCode,$cash.StatusCode,$mixed.StatusCode)|Where-Object{$_-ne200}){throw 'A checkout did not return HTTP 200.'}
  $cashSale=(ConvertFrom-Json $cash.Content).saleGlobalId
  $cancel=Invoke-P042Post '/sales/cancel' ([ordered]@{saleGlobalId=$cashSale;reason='P042 HTTPS cancellation test'})
  $cancelReplay=Invoke-P042Post '/sales/cancel' ([ordered]@{saleGlobalId=$cashSale;reason='P042 HTTPS cancellation test'})
  if($cancel.StatusCode-ne200 -or $cancelReplay.StatusCode-ne200){throw 'Cancellation or replay did not return HTTP 200.'}
  $reports=Invoke-WebRequest 'https://localhost:7444/reports/admin' -UseBasicParsing -WebSession $session
  $csv=Invoke-WebRequest 'https://localhost:7444/reports/export/sales/csv' -UseBasicParsing -WebSession $session
  $xlsx=Invoke-WebRequest 'https://localhost:7444/reports/export/sales/xlsx' -UseBasicParsing -WebSession $session
  $pdf=Invoke-WebRequest 'https://localhost:7444/reports/export/sales/pdf' -UseBasicParsing -WebSession $session
  if(@($reports.StatusCode,$csv.StatusCode,$xlsx.StatusCode,$pdf.StatusCode)|Where-Object{$_-ne200}){throw 'A report/export did not return HTTP 200.'}
  $close=Invoke-P042Post '/cash-operations/close' ([ordered]@{sessionGlobalId=$cashSession;countedCashCents=500})
  if($close.StatusCode-ne200){throw "Cash close returned HTTP $($close.StatusCode)."}
  $closeData=ConvertFrom-Json $close.Content;if($closeData.differenceCents-ne0){throw "Cash reconciliation difference was $($closeData.differenceCents), expected 0."}
  # A foreign tenant creates its own card sale. The primary session must neither
  # cancel it nor cause a write by reusing its global identifier.
  $foreignSession=New-P042Session $values.FOREIGN_BUSINESS $values.FOREIGN_DEVICE $values.FOREIGN_USERNAME
  $foreignCheckout=[ordered]@{idempotencyKey=[guid]::NewGuid();lines=@([ordered]@{productGlobalId=[guid]$values.FOREIGN_PRODUCT;quantity=1});payments=@([ordered]@{method='Card';amountCents=1250})}
  $foreignResponse=Invoke-WebRequest 'https://localhost:7444/checkout' -UseBasicParsing -WebSession $foreignSession.Session -Method Post -ContentType 'application/json' -Headers @{'X-CSRF-TOKEN'=$foreignSession.Token} -Body ($foreignCheckout|ConvertTo-Json -Depth 6 -Compress)
  if($foreignResponse.StatusCode-ne200){throw "Foreign tenant checkout returned HTTP $($foreignResponse.StatusCode)."}
  $foreignSale=(ConvertFrom-Json $foreignResponse.Content).saleGlobalId;$crossTenantBefore=Get-P042WriteCount
  $crossTenantCancel=Invoke-P042Rejected { Invoke-WebRequest 'https://localhost:7444/sales/cancel' -UseBasicParsing -WebSession $session -Method Post -ContentType 'application/json' -Headers $headers -Body (([ordered]@{saleGlobalId=$foreignSale;reason='cross tenant security test'})|ConvertTo-Json -Compress) -ErrorAction Stop }
  if($crossTenantCancel-ne404){throw "Cross-tenant identifier returned HTTP $crossTenantCancel, expected 404."}
  if((Get-P042WriteCount)-ne$crossTenantBefore){throw 'Cross-tenant rejected cancellation modified SQL state.'}
  # Revoke an already-authenticated device only in this disposable database and
  # prove that the retained session can no longer write.
  $env:POSFLUTTER_LAB_REVOKE_DEVICE='1'
  try { $revocationSeed=dotnet run --project "$PSScriptRoot\..\server\tools\MvcLabSeed\MvcLabSeed.csproj" -c Release --no-build } finally { Remove-Item Env:POSFLUTTER_LAB_REVOKE_DEVICE -ErrorAction SilentlyContinue }
  if($LASTEXITCODE-ne0 -or $revocationSeed -notmatch 'BUSINESS='){throw 'Could not revoke the isolated laboratory device.'}
  $revokedBefore=Get-P042WriteCount
  $revokedDevice=Invoke-P042Rejected { Invoke-WebRequest 'https://localhost:7444/cash-operations/open' -UseBasicParsing -WebSession $session -Method Post -ContentType 'application/json' -Headers $headers -Body '{"openingBalanceCents":0}' -ErrorAction Stop }
  if($revokedDevice-ne403){throw "Revoked device returned HTTP $revokedDevice, expected 403."}
  if((Get-P042WriteCount)-ne$revokedBefore){throw 'Revoked-device rejected request modified SQL state.'}
  "P042_HTTPS=PASS;HEALTH=$($health.StatusCode);ANON_NO_CSRF=$anonymousNoCsrf;ANON_VALID_CSRF=$anonymousValidCsrf;LOGIN=$loginStatus;AUTH_NO_CSRF=$authenticatedNoCsrf;SELLER_CASH=$sellerCash;SELLER_REPORTS=$sellerReports;FOREIGN_DEVICE_LOGIN=$foreignDeviceLogin;FOREIGN_DEVICE_PRODUCTS=$foreignDeviceProducts;CROSS_TENANT_CANCEL=$crossTenantCancel;REVOKED_DEVICE=$revokedDevice;HOME=$($homeResponse.StatusCode);CATALOG=$(@($catalog.items).Count);CASH_OPEN=$($cashOpen.StatusCode);CARD=$($card.StatusCode);CARD_REPLAY=$($cardReplay.StatusCode);TRANSFER=$($transfer.StatusCode);CASH=$($cash.StatusCode);MIXED=$($mixed.StatusCode);CANCEL=$($cancel.StatusCode);CANCEL_REPLAY=$($cancelReplay.StatusCode);REPORTS=$($reports.StatusCode);CSV=$($csv.StatusCode);XLSX=$($xlsx.StatusCode);PDF=$($pdf.StatusCode);CASH_CLOSE=$($close.StatusCode);HOST_PID=$($kestrelProcess.Id)"
} finally {if($kestrelProcess -and !$kestrelProcess.HasExited){Stop-Process -Id $kestrelProcess.Id}}
