# POSWEB_LOCALDB_AUTOSTART
& sqllocaldb start "POSWEB_V44_LAB_20261018" 2>$null | Out-Null
$SqlCmdLab = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
& $SqlCmdLab -S "(localdb)\POSWEB_V44_LAB_20261018" -E -C -b -l 15 -Q "SELECT 1" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo conectar al SQL Server de laboratorio."
}
$ErrorActionPreference = 'Stop'
$db = 'POSFlutter_MvcLab_CheckoutCert_20261018_222511_f300b7c3'
$env:ConnectionStrings__SqlServer = "Server=(localdb)\POSWEB_V44_LAB_20261018;Database=$db;Integrated Security=true;TrustServerCertificate=true"
$env:POSFLUTTER_LAB_PASSWORD = [guid]::NewGuid().ToString('N') + 'aA!1'
$env:ASPNETCORE_URLS = 'http://localhost:7105'
$seed = dotnet run --no-build -c Release --project server/tools/MvcLabSeed/MvcLabSeed.csproj
if ($LASTEXITCODE -ne 0) { throw 'Lab seed failed' }
$values = @{}; foreach ($pair in (($seed | Select-Object -Last 1) -split ';')) { $key, $value = $pair -split '=', 2; if ($value) { $values[$key] = $value } }
$serverLog = Join-Path $env:TEMP 'posflutter-mvc-lab-host.log'
$serverErrorLog = Join-Path $env:TEMP 'posflutter-mvc-lab-host.err.log'
$server = $null # Reutilizar Kestrel manual
try {
  $base = 'http://localhost:7105'; $login = $null
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(60)
  $ultimoErrorHttp = $null
  while (-not $login -and [DateTimeOffset]::UtcNow -lt $deadline) {
    try {
      $login = Invoke-WebRequest -Uri "$base/Home/Login" -UseBasicParsing -SessionVariable mvc -TimeoutSec 15 -ErrorAction Stop
      if ($login.StatusCode -ne 200) {
        throw "Login GET HTTP $($login.StatusCode)"
      }
    }
    catch {
      $ultimoErrorHttp = $_.Exception.Message
      Start-Sleep -Milliseconds 500
    }
  }
  if (-not $login) {
    throw "LOGIN_HTTP_FAILED: $ultimoErrorHttp"
  }
  if (-not $login) { if ($null -ne $server) { $server.Refresh() }; throw "MVC did not start (exited=NO_PROCESS_STARTED): $((Get-Content $serverErrorLog -Tail 3 -ErrorAction SilentlyContinue) -join ' ')" }
  $csrf = [regex]::Match($login.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"').Groups[1].Value

  # LOGIN_HTTP_NET: PowerShell 5.1 sin MaximumRedirectExceeded
  $camposLogin = [ordered]@{
      __RequestVerificationToken = $csrf
      BusinessGlobalId = $values.BUSINESS
      DeviceGlobalId = $values.DEVICE
      Username = 'web.lab'
      Password = $env:POSFLUTTER_LAB_PASSWORD
  }

  $pares = foreach ($campo in $camposLogin.GetEnumerator()) {
      [uri]::EscapeDataString([string]$campo.Key) + '=' +
      [uri]::EscapeDataString([string]$campo.Value)
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($pares -join '&'))

  $peticion = [System.Net.HttpWebRequest]::Create("$base/Home/Login")
  $peticion.Method = 'POST'
  $peticion.AllowAutoRedirect = $false
  $peticion.CookieContainer = $mvc.Cookies
  $peticion.ContentType = 'application/x-www-form-urlencoded'
  $peticion.ContentLength = $bytes.Length
  $peticion.Timeout = 15000

  $flujo = $peticion.GetRequestStream()
  try {
      $flujo.Write($bytes, 0, $bytes.Length)
  }
  finally {
      $flujo.Dispose()
  }

  try {
      $respuestaHttp = $peticion.GetResponse()
  }
  catch [System.Net.WebException] {
      if ($null -eq $_.Exception.Response) { throw }
      $respuestaHttp = $_.Exception.Response
  }

  try {
      $codigoHttp = [int]$respuestaHttp.StatusCode
      $rutaRedirect = [string]$respuestaHttp.Headers['Location']

      Write-Host "LOGIN_POST_HTTP=$codigoHttp"

      if ($rutaRedirect) {
          $rutaSegura = ($rutaRedirect -split '\?')[0]
          Write-Host "LOGIN_REDIRECT=$rutaSegura"
      }

      $response = [pscustomobject]@{
          StatusCode = $codigoHttp
      }
  }
  finally {
      $respuestaHttp.Dispose()
  }
  if ($response.StatusCode -ne 302) { throw "Login HTTP $($response.StatusCode)" }
  # P025_SESSION_DIAGNOSTIC
  $uriSesion = [uri]"$base/"
  $cookiesSesion = @($mvc.Cookies.GetCookies($uriSesion))

  Write-Host "SESSION_COOKIE_COUNT=$($cookiesSesion.Count)"

  foreach ($cookie in $cookiesSesion) {
      Write-Host "SESSION_COOKIE_NAME=$($cookie.Name)"
      Write-Host "SESSION_COOKIE_PATH=$($cookie.Path)"
      Write-Host "SESSION_COOKIE_SECURE=$($cookie.Secure)"
  }

  try {
      $mvcHomeResponse = Invoke-WebRequest -UseBasicParsing `
          -Uri "$base/" `
          -WebSession $mvc `
          -MaximumRedirection 0 `
          -ErrorAction Stop
  }
  catch {
      $ex = $_.Exception
      if ($ex -is [System.Net.WebException] -and $ex.Response) {
          Write-Host "HOME_HTTP_STATUS=$([int]$ex.Response.StatusCode)"
          $location = [string]$ex.Response.Headers['Location']
          if ($location) {
              Write-Host "HOME_REDIRECT_PATH=$(($location -split '\?')[0])"
          }
      }
      throw
  }
  $csrf = [regex]::Match($mvcHomeResponse.Content, 'meta name="pos-csrf" content="([^"]+)"').Groups[1].Value
  $products = Invoke-RestMethod "$base/data/products" -WebSession $mvc; $product = @($products.items)[0].globalId
  if (-not $product) { throw 'Catalog was not returned from MVC' }
  $headers = @{ 'X-CSRF-TOKEN'=$csrf }
  function Checkout([string] $method, [long] $received=0) { $request=@{idempotencyKey=[guid]::NewGuid();lines=@(@{productGlobalId=$product;quantity=1});payments=@(@{method=$method;amountCents=1250})}; if($method -eq 'Cash'){$request.receivedCashCents=$received}; Invoke-WebRequest -UseBasicParsing "$base/checkout" -WebSession $mvc -Method Post -ContentType 'application/json' -Headers $headers -Body ($request|ConvertTo-Json -Depth 5) }
  $card=Checkout Card; $transfer=Checkout Transfer
  $cashOpen=Invoke-WebRequest -UseBasicParsing "$base/cash-operations/open" -WebSession $mvc -Method Post -ContentType 'application/json' -Headers $headers -Body '{"openingBalanceCents":0}'
  $cash=Checkout Cash 2000
  # P033 - HTTP 400 es el resultado esperado del checkout invalido.
  $invalidStatus = $null
  try {
      $invalid = Invoke-WebRequest -UseBasicParsing "$base/checkout" -WebSession $mvc -Method Post -ContentType 'application/json' -Headers $headers -Body '{"idempotencyKey":"00000000-0000-0000-0000-000000000000","lines":[],"payments":[]}'
      $invalidStatus = [int]$invalid.StatusCode
  }
  catch [System.Net.WebException] {
      if ($_.Exception.Response) {
          $invalidStatus = [int]$_.Exception.Response.StatusCode
      } else {
          throw
      }
  }
  if ($invalidStatus -ne 400) {
      throw "INVALID_CHECKOUT_EXPECTED_400_ACTUAL_$invalidStatus"
  }
  $invalid = [pscustomobject]@{ StatusCode = $invalidStatus }
  Write-Host "INVALID_CHECKOUT_HTTP=400"
  "LOGIN=$($response.StatusCode);CATALOG=$(@($products).Count);CARD=$($card.StatusCode);TRANSFER=$($transfer.StatusCode);CASH_OPEN=$($cashOpen.StatusCode);CASH=$($cash.StatusCode);INVALID=$($invalid.StatusCode)"
} finally { if ($null -ne $server -and -not ($null -eq $server -or $server.HasExited)) { Stop-Process -Id $server.Id } }
