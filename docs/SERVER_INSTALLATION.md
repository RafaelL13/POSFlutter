# Server installation

`Install-POSFlutterServer.ps1` publishes `server/src/Api`, migrates the supplied SQL Server database, creates the dedicated `POSFlutterApiPool` and `POSFlutterApi` IIS site, and checks local health. It refuses the `SistemaVentas` site and refuses to replace an existing POSFlutter site unless `-Upgrade` is explicit.

Run from an elevated PowerShell with source root and no secret in command history:

```powershell
./installer/server/Install-POSFlutterServer.ps1 -SourceRoot C:\Release\POSFlutter
```

The installer asks interactively for connection and JWT values if omitted. IIS needs those values available to the worker process; access to the installation directory and IIS configuration must therefore be restricted to administrators and the app pool identity. Do not place real values in Git, logs, `.env.example`, or release manifests.

Cloudflare Tunnel/public DNS is deliberately separate: it needs its own least-privilege deployment and token management and is not configured by this repository script.
