# Release process

1. Branch from `main`; do not alter `v1.0.0`.
2. Review small commits, run source gates, and build signed APK only after source changes.
3. Create immutable release evidence: APK hash/signature/version, test logs, clean DB result, installer dry-run, and bundle verification.
4. Create `C:\Backups\POSFlutter\<version>_FINAL` only after the candidate is approved. Include Git bundle, APK, SHA256 manifest, installer, server package, non-secret docs, and recovery/rollback instructions.
5. Verify `git bundle verify` and clone the bundle into a temporary directory; confirm target branch/tag/commit.
6. Stop before destructive clean UAT. Only the owner may authorize reset of tablet, IIS deployment replacement, or database replacement.

Rollback is a deliberate operation: reinstall the prior signed APK/server package only after verifying compatibility and restoring an approved SQL backup. Never overwrite the v1.0.0 artifact.
