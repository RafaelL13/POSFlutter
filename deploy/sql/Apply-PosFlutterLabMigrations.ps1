#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SqlConnection,
    [Parameter(Mandatory = $true)][string]$DatabaseName,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [switch]$Apply,
    [switch]$OwnerAuthorized
)

$ErrorActionPreference = 'Stop'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Require ($DatabaseName -match '^POSFlutter_MvcLab_A14_[0-9a-fA-F]{32}$') 'DATABASE_NAME_MUST_BE_A_NEW_A14_LAB_GUID'
Require ($DatabaseName -notmatch '(?i)(^POSFlutterDB$|MigrationTest|Production|Shared)') 'PROTECTED_DATABASE_NAME_REJECTED'
Require (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\server\src\Infrastructure\Infrastructure.csproj')) 'INFRASTRUCTURE_PROJECT_MISSING'

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $SqlConnection
Require (-not [string]::IsNullOrWhiteSpace($builder.DataSource)) 'SQL_DATA_SOURCE_MISSING'
if (-not [string]::IsNullOrWhiteSpace($builder.Database) -and $builder.Database -ne $DatabaseName) {
    throw 'CONNECTION_DATABASE_MUST_MATCH_DATABASE_NAME'
}
$builder.Database = 'master'

if (-not $Apply) {
    [pscustomobject]@{
        Database = $DatabaseName
        DataSourceConfigured = $true
        DatabaseCreation = 'NONE (plan mode)'
        MigrationApply = 'NONE (plan mode)'
        NextStep = 'Written owner authorization for a new disposable LAB database, then re-run with -Apply -OwnerAuthorized.'
    } | Format-List
    return
}

Require $OwnerAuthorized 'OWNER_AUTHORIZATION_REQUIRED'
Require (-not (Test-Path -LiteralPath $EvidencePath)) 'EVIDENCE_PATH_MUST_BE_NEW'
New-Item -ItemType Directory -Path $EvidencePath | Out-Null

$databaseExists = $false
$connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = 'SELECT CASE WHEN DB_ID(@databaseName) IS NULL THEN 0 ELSE 1 END;'
    [void]$command.Parameters.AddWithValue('@databaseName', $DatabaseName)
    $databaseExists = ([int]$command.ExecuteScalar() -eq 1)
}
finally { $connection.Dispose() }
Require (-not $databaseExists) 'DATABASE_ALREADY_EXISTS_NO_WRITE_PERFORMED'

$migrationProject = Join-Path $PSScriptRoot '..\..\server\src\Infrastructure\Infrastructure.csproj'
$applyBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $SqlConnection
$applyBuilder.Database = $DatabaseName
$previous = $env:POSFLUTTER_EF_CONNECTION_STRING
try {
    $env:POSFLUTTER_EF_CONNECTION_STRING = $applyBuilder.ConnectionString
    $output = @(& dotnet ef database update --project $migrationProject --startup-project $migrationProject --no-build --context PosDbContext 2>&1)
    Require ($LASTEXITCODE -eq 0) 'EF_DATABASE_UPDATE_FAILED'
    $output | ForEach-Object {
        $_.ToString() -replace '(?i)(password|pwd)\s*=\s*[^;\s]+', '$1=***'
    } | Set-Content -LiteralPath (Join-Path $EvidencePath 'ef-migrations.log') -Encoding UTF8

    [pscustomobject]@{
        Database = $DatabaseName
        MigrationResult = 'PASS'
        CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Production = $false
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidencePath 'result.json') -Encoding UTF8
}
finally {
    if ($null -eq $previous) { Remove-Item Env:POSFLUTTER_EF_CONNECTION_STRING -ErrorAction SilentlyContinue }
    else { $env:POSFLUTTER_EF_CONNECTION_STRING = $previous }
}
