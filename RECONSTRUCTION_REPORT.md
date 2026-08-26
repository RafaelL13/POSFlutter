# POSFlutter — Controlled Reconstruction Report

Date: 2026-08-25 (America/Mazatlan)

## Reason

The prior full source tree and ephemeral `.git` object database became unavailable. Recovery was exhausted and documented. The project then formally entered **CONTROLLED RECONSTRUCTION**: authentic recovered code was preserved first, and missing components were recreated from project status, recovery evidence and the original functional specification. Reconstructed files are not represented as lost originals.

## Source/provenance

Authentic evidence is retained in `RECOVERY_EVIDENCE/`. The functional tree uses the provenance classifications recorded in `RECOVERY_MANIFEST.md`: `RECOVERED_AUTHENTIC`, `RECONSTRUCTED_FROM_AUTHENTIC`, `RECONSTRUCTED`, `NEW_IMPLEMENTATION`, and `PENDING_EXTERNAL_TOOL`.

The historical hashes `339ba70`, `dd355f3`, and `0e106fb` belong to the lost ephemeral repository and are not objects in the new repository.

## Reconstructed architecture

### Flutter / SQLite

- Material 3 application structure with Riverpod and GoRouter.
- First run: create a new local business or enroll into an existing business.
- Local login remains authoritative for POS offline operation.
- Products/categories/suppliers/users, purchases, independent FIFO lots, inventory movements/adjustments.
- POS with integer quantities, money cents, discounts, cash/card/transfer/other payments.
- Atomic sale: sale + details + sale-lot allocations + inventory movement + cash movement + sync outbox.
- Cancellation preserves the sale record/status, restores exact original FIFO allocations, writes inverse movements/audit/cash reversal.
- Cash sessions, expenses, reports/CSV.
- Backup abstraction and local SQLite backup/restore with `VACUUM INTO`, integrity/version validation, preventive backup and rollback.
- Durable sync queue, retry state, push and incremental pull.
- Pull applies the complete batch and advances `sync_pull_cursor` in one SQLite transaction.
- Catalog conflicts preserve local and remote payloads/version/cursor.

### Backend

- .NET 10 solution with Domain/Application/Infrastructure/Api/Tests projects.
- EF Core SQL Server model with tenant/global uniqueness and integrity constraints.
- JWT + refresh tokens.
- Signed tenant context: Business/Branch/Device/User.
- `SyncChange.Id` monotonic pull sequence and `(BusinessId, Id)` index.
- Pull page clamp 1..200 with `limit+1` strategy and `hasMore`.
- Tenant-safe read endpoints for dashboard, sales, products, categories, suppliers, purchases, inventory/lots, expenses, cash and users.
- Operational writes funnel through sync.

### FASE 16 — AdminReadOnly enrollment

- Device modes: `PointOfSale` and `AdminReadOnly`.
- 256-bit random invitation, only SHA-256 hash stored.
- expiration and prepared revocation (`RevokedAt`).
- Administrator credentials required; Seller/cross-tenant redemption rejected.
- serializable redemption transaction.
- IP-partitioned rate limit (10/minute in reconstructed host configuration).
- stable client-generated `DeviceGlobalId`; lost-response retry with same token/credentials/GID recovers the same device and does not create another `SyncChange`.
- server checks current DB device state; only active `PointOfSale` can perform operational sync push.
- `AdminReadOnly` can authenticate, pull and read administration data.

## Real SQLite validation executed

Command:

```text
python3 tools/sqlite_validation.py
```

Observed result:

```text
SQLITE_VALIDATION=PASS
V1_STATEMENTS=24 V2_STATEMENTS=10 V3_STATEMENTS=2
INTEGRITY=ok FOREIGN_KEYS=ok DATA_PRESERVED=yes DEVICE_MODE=PointOfSale CURSOR=123
ROLLBACK=verified CONFLICT=verified INTEGER_CONSTRAINTS=verified ENROLLMENT_DEVICE_ID=verified
FIFO_CASE1=cost300_remaining7 FIFO_CASE2=cost440_remainingB3 FIFO_CASE3=rejected
```

This is a real SQLite/Python validation. It is **not** `flutter test`.

## Structural validation executed

`python3 tools/structural_gate.py` verifies the functional build tree while deliberately excluding `RECOVERY_EVIDENCE/` from source-quality assertions. The latest pre-packaging run returned:

```text
STRUCTURAL_GATE=PASS
HIGH_CONFIDENCE_SECRETS=0
```

It checked the required graph, JSON/YAML/XML, `.csproj` and solution references, Dart local imports/package declarations, placeholders/conflict markers/empty files/trailing whitespace, temporary artifacts, secret literals, Android source/config, sync cursor/pagination, server-side device mode guard, SQLite pull transaction, tenant reads, write surface, enrollment semantics, EF indexes/entities, contracts/DI and known integration regressions.

This structural gate is **not** a substitute for Dart/C# compilation.

## Tests

Flutter tests are written for FIFO/insufficient stock, cent-based sale totals, DeviceMode, schema constraints, sync operation retry record, pull cursor model and enrollment schema contract. Backend xUnit tests are written for tenant isolation, sync pull/pagination, sync push idempotency/version conflicts, enrollment hashing/idempotency/revocation/Seller/cross-tenant, and AdminReadOnly push/pull behavior.

They are **WRITTEN / NOT EXECUTED** because the required SDKs are absent.

## Android status

- source/config: reconstructed and structurally checked;
- declared Gradle: 9.3.1;
- AGP: 9.1.0;
- Kotlin: 2.4.0;
- JVM: 17;
- compile/target/min SDK: 36/36/24;
- wrapper scripts/JAR: intentionally pending, not fabricated;
- Android build: not executed.

See `docs/ANDROID_RECONSTRUCTION.md`.

## Tool/SDK status at finalization

Available: Git 2.47.3, Python 3.13.5, Java 21.0.11.

Unavailable in this runtime: Flutter, Dart, .NET SDK, Docker, Gradle, GitHub CLI.

Therefore the following remain **NOT EXECUTED**: Flutter pub/analyze/test/build, .NET restore/build/test/EF migration, Android Gradle build.


## Final source inventory before packaging

- total files: **129**
- Dart application files: **57**
- Flutter test files: **7**
- C# files: **20** (backend test/support C#: **8**)
- `.csproj`: **5**
- `.sln`: **1**
- Android source/config files: **11**
- Markdown documentation files: **9**
- recovery evidence files: **9**

A complete path inventory is stored in `docs/FILE_INVENTORY.txt`.

## Known limitations / required next validation

1. Install Flutter/Dart and execute the real analyzer/tests/release APK build.
2. Restore official Android Gradle wrapper artifacts before building; do not fabricate them.
3. Install .NET 10, execute restore/build/test, generate and review an EF Core migration from the reconstructed model.
4. Configure real SQL/JWT secrets externally.
5. Configure a private Git remote following `GIT_REMOTE_SETUP.md`.

This baseline must be treated as a structurally validated reconstructed source baseline, not a production-certified release.
