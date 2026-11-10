# Clean installation runbook

Do not execute this runbook against an existing tablet, IIS site, or SQL Server database without an explicit recovery window and approval.

1. Prepare a clean Windows Server with IIS, ASP.NET Core Hosting Bundle, SQL Server connectivity, and a dedicated service account.
2. Copy the release bundle, verify `SHA256SUMS.txt`, clone the bundle, and verify the intended tag and commit.
3. Use `installer/server/Install-POSFlutterServer.ps1`; provide the SQL connection string and JWT key only through interactive secure prompts or an approved secret store.
4. Confirm local `/health`, then configure the public TLS/tunnel endpoint separately and verify public `/health`.
5. On a clean tablet, use `installer/tablet/Install-POSFlutterTablet.ps1` with the release APK hash, certificate digest, version name, and version code.
6. Complete first-run/enrollment while the API is reachable. Then disable connectivity and verify local sale, inventory/FIFO, cash, restart persistence, and queued synchronization.

The reset script intentionally requires `-Confirm`; it clears Android app data and is never part of an automatic install.

## POSFlutter Web IIS LAB package

The IIS package is a LAB candidate, not a production deployment. First run
`iis\Install-PosFlutterWeb.ps1 -PackagePath <candidate.zip>` without `-Apply`.
It validates the archive and makes no changes. An approved LAB installation
requires a new empty directory, a secure LAB-only connection string, and the
explicit `-Apply -OwnerAuthorized` switches from an elevated session.

Before an authorized IIS PhysicalPath change, capture the current published
release with `iis\Backup-PosFlutterWebLab.ps1`; it writes a SHA-256 manifest to
a new backup directory. `iis\Rollback-PosFlutterWebLab.ps1` verifies that
manifest and stages a restore only into a new directory. Neither script changes
IIS or overwrites an existing deployment. Pointing IIS at either directory is a
separate authorized LAB change followed by `iis\Verify-PosFlutterWeb.ps1`.

For a new disposable SQL Server LAB database, use
`sql\Apply-PosFlutterLabMigrations.ps1` first in plan mode. It accepts only a
new `POSFlutter_MvcLab_A14_<GUID>` database name and refuses protected or
existing names. Applying migrations requires the same written LAB authorization
and `-Apply -OwnerAuthorized`; it never targets production by default.
