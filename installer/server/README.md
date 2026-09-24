# POSFlutter server installer

Run the installer only on an approved clean Windows Server or approved upgrade window. It never targets `SistemaVentas` and an existing `POSFlutterApi` site requires `-Upgrade` explicitly.

```powershell
Set-Location C:\Release\POSFlutter
.\installer\server\Install-POSFlutterServer.ps1 -SourceRoot (Get-Location)
```

The script prompts for the SQL connection string and JWT signing key without echoing them. It requires elevation, IIS, .NET/ASP.NET Core 10, `dotnet ef`, and SQL access. Use `Test-POSFlutterServer.ps1` for local health and optionally a separately configured public HTTPS health URL.

`Restore-POSFlutterServer.ps1` overwrites its target database after confirmation; run it only under an approved recovery plan.
