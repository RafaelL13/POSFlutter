# POSFlutter production readiness

This branch prepares post-v1.0.0 release material. It does not authorize a destructive tablet reset, SQL database replacement, IIS deployment, merge, or push.

## Product boundaries

The Android app persists operations in SQLite first. The API is an HTTPS synchronization boundary; Flutter does not connect to SQL Server. Sales, FIFO allocations, inventory, cash, and SyncQueue must not wait for network availability.

## Evidence required before clean production UAT

- Flutter formatter, analyzer, and full suite pass on the release commit.
- API build and the Infrastructure test runner pass on the release commit.
- A new, explicitly named non-production SQL database completes the complete EF migration chain and health check.
- Server and tablet installer scripts pass syntax and `-WhatIf`/verification checks without contacting or replacing the current installation.
- Release APK is signed, hash-verified, certificate-verified, and built with the production HTTPS API define.
- A Git bundle verifies and is clone-tested.

Until each item has command evidence, its state is `NOT_RUN`, not PASS.
