# Clean installation runbook

Do not execute this runbook against an existing tablet, IIS site, or SQL Server database without an explicit recovery window and approval.

1. Prepare a clean Windows Server with IIS, ASP.NET Core Hosting Bundle, SQL Server connectivity, and a dedicated service account.
2. Copy the release bundle, verify `SHA256SUMS.txt`, clone the bundle, and verify the intended tag and commit.
3. Use `installer/server/Install-POSFlutterServer.ps1`; provide the SQL connection string and JWT key only through interactive secure prompts or an approved secret store.
4. Confirm local `/health`, then configure the public TLS/tunnel endpoint separately and verify public `/health`.
5. On a clean tablet, use `installer/tablet/Install-POSFlutterTablet.ps1` with the release APK hash, certificate digest, version name, and version code.
6. Complete first-run/enrollment while the API is reachable. Then disable connectivity and verify local sale, inventory/FIFO, cash, restart persistence, and queued synchronization.

The reset script intentionally requires `-Confirm`; it clears Android app data and is never part of an automatic install.
