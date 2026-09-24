# Backup and restore

Server backup uses SQL Server `BACKUP DATABASE ... WITH CHECKSUM, COPY_ONLY` and records a SHA-256. Restore is destructive, requires confirmation, and must target an approved recovery database before any production use.

The API package and non-secret configuration should be archived with the release bundle and version manifest. Keep SQL passwords, JWT keys, Cloudflare tokens, and Android signing material out of those archives.

Android release data cannot be safely promised as a filesystem copy: Android Keystore/SecureStorage and app sandbox guarantees vary. Recovery is the supported path: reinstall the signed APK, enroll, allow pull/sync, and validate local state. Test this procedure during clean UAT.
