# Backup and restore

## Android / SQLite

POSFlutter supports portable local SQLite backups through the Android Storage Access Framework (SAF).

The backup flow creates a consistent SQLite backup and lets the user choose the destination through the native Android document picker. The resulting file is stored outside the private application sandbox at the location selected by the user.

Restore is destructive and requires an authorized capability, special reauthentication, explicit destructive confirmation, backup validation, supported schema compatibility, and SQLite integrity validation.

Before replacing the active database, the application creates a preventive pre-restore copy. If restore fails, that preventive copy is used by the recovery flow.

The special authorization used for restore is consumed by the operation and must not remain reusable.

P009.4 physically validated the Android SAF backup and restore flow on the release application. The backup remained externally accessible, could be selected again through the native Android picker, and a controlled real restore completed successfully.

If no usable local backup exists, recovery can use reinstall plus device enrollment and governed synchronization to recover centrally available state. This does not replace portable local backups for information that has not yet synchronized.

## SQL Server

Central SQL Server backup is independent from the Android SQLite backup.

P009.3 validated a FULL COPY_ONLY backup with CHECKSUM, RESTORE VERIFYONLY WITH CHECKSUM, an isolated restore, DBCC CHECKDB, schema and row-count comparison, controlled cleanup of the temporary recovery database, and confirmation that the production database remained ONLINE.

Certified P009.3 backup SHA-256:

FB84B56F28360D9C5B500E7285E19051E868B1D20303D04B77D155BDF250BA4B

The backup path recorded during certification is evidence of that specific test and is not a permanent storage-location contract.

## Release and secrets

The API package and non-secret configuration should be archived with the release bundle and version manifest.

Do not include SQL passwords, secret connection strings, JWT signing keys, Cloudflare credentials, Android signing material, or other secrets in backup documentation or release evidence.
