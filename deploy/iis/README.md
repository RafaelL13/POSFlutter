# POSFlutter Web — IIS laboratory package

1. Install the .NET 10 ASP.NET Core Hosting Bundle and IIS URL Rewrite/ASP.NET Core Module on the laboratory server.
2. Copy the ZIP to the server and first run `Install-PosFlutterWeb.ps1 -PackagePath .\POSFlutter_Web_LasAguilas_CANDIDATO.zip`. This is preflight-only and changes nothing.
3. Only after written owner authorization and a verified IIS/SQL backup, run it from an elevated Windows PowerShell 5.1 session with `-Apply -OwnerAuthorized`, a new empty destination and a secret SQL Server connection string outside source control.
4. Create an IIS site with an HTTPS binding and an application pool set to **No Managed Code**.
5. Run `Verify-PosFlutterWeb.ps1 -BaseUrl https://your-lab-host`.

## Backup and staged reversal

Before changing an authorized LAB IIS PhysicalPath, capture the published
release with `Backup-PosFlutterWebLab.ps1`. It requires a **new** backup
directory and writes `backup-manifest.json` with SHA-256 values. Its default
mode is a non-mutating plan; file copying requires both `-Apply` and
`-OwnerAuthorized`.

`Rollback-PosFlutterWebLab.ps1` validates every hash and restores only into a
new staging directory. It never overwrites a deployment or changes IIS. After
the staged files have been verified, an authorized IIS administrator may point
the LAB site back to that release under the approved change procedure.

The package contains no database migration command and does not deploy, seed, or modify production databases.

## Read-only preflight

`Preflight-PosFlutterWebLab.ps1` validates a ZIP, checks the localhost HTTPS binding/listener and optionally requests `/health`. It never creates a site, changes IIS, modifies a connection string or copies files. Use it before asking for authorization to replace a laboratory deployment.

Visual acceptance and the authorized, destination-only SQL Server 2022 migration procedure are documented in `LAB_VISUAL_AND_MIGRATION_ACCEPTANCE.md`.
