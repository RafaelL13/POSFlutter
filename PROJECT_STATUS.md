# POSFlutter — Project Status

Date: 2026-08-26 (America/Mazatlan)

## Canonical transition

**CONTROLLED RECONSTRUCTION: COMPLETED / FASE 17 IMPLEMENTED / BACKEND SDK VALIDATED / FLUTTER SDK VALIDATION PENDING**

The original complete runtime and `.git` object database were lost before this reconstruction. Recovery was exhausted first; controlled reconstruction then rebuilt a coherent source tree while preserving authentic recovered files under `RECOVERY_EVIDENCE/` and recording provenance in `RECOVERY_MANIFEST.md`.

The following are historical references from the lost ephemeral Git repository only:

- `339ba70 feat: add local reports exports and verified backups` — **HISTORICAL / NOT PRESENT IN CURRENT GIT OBJECT DATABASE**
- `dd355f3 feat: add tenant-isolated incremental sync pull` — **HISTORICAL / NOT PRESENT IN CURRENT GIT OBJECT DATABASE**
- `0e106fb feat: add tenant-safe cloud administration overview` — **HISTORICAL / NOT PRESENT IN CURRENT GIT OBJECT DATABASE**

The new Git repository starts with a new reconstructed baseline. Its real hash is reported after Git initialization/commit and is intentionally not pre-written here, avoiding a second documentation commit only to record its own hash.

## Reconstructed functional scope

- Flutter tablet application with Material 3/Riverpod/GoRouter structure.
- SQLite offline-first operational database, schema v1→v2→v3.
- Business/branch/device/user model and roles.
- Local authentication and first-run paths for new business or existing-business enrollment.
- POS with integer quantities, cent-based money, FIFO lots and transactional sale recording.
- Products, categories, suppliers, purchases/lots, inventory adjustments/kardex.
- Sale cancellation restoring original FIFO allocations and reversing relevant movements.
- Cash sessions/movements, expenses, local reports and CSV.
- Local SQLite backup/restore abstraction with integrity validation and preventive backup.
- Persistent `SyncQueue`, retry/backoff, push and incremental pull.
- Monotonic server `SyncChange.Id` cursor, pagination and SQLite atomic cursor advancement.
- Catalog conflict preservation using local/remote payloads and server versions.
- ASP.NET Core/.NET 10 solution with EF Core SQL Server model, JWT/refresh tokens, health/OpenAPI.
- Multi-tenant isolation derived from signed/authenticated context.
- Tenant-safe remote administration reads.
- FASE 16 `PointOfSale` / `AdminReadOnly` device modes and secure enrollment with hashed one-time invitations, expiry/revocation, Administrator reauthentication, cross-tenant rejection, IP rate limit and idempotent retry using stable `DeviceGlobalId`.
- FASE 17 tenant-safe remote reports: executive summary, sales periods/details, product/category/user performance, purchases/suppliers, FIFO-valued inventory, expenses, cash sessions, payment methods, cancellations, product trends, tenant-safe `GlobalId` dimension filters, remote CSV and tablet cloud-admin presentation.
- Remote report API is GET-only under `/api/admin/reports`, protected by `Administrator`; tenant authority remains claim-derived.
- Remote FIFO cost comes from persisted `SaleLotAllocation`; inventory valuation comes from remaining `InventoryLot` quantities. See `docs/REMOTE_REPORTS.md`.

## Actually executed in this runtime

- `python3 tools/structural_gate.py` → `STRUCTURAL_GATE=PASS` after FASE 17 additions.
- High-confidence secret scan → `0` findings.
- Dart local import resolution → `0` unresolved local imports.
- JSON/YAML/XML/project/solution/reference checks → passed by structural gate.
- `python3 tools/sqlite_validation.py` → `SQLITE_VALIDATION=PASS`.
- Real SQLite v1→v2→v3 migration with representative existing data.
- `PRAGMA integrity_check` → `ok`.
- `PRAGMA foreign_key_check` → no violations.
- SQLite integer money/quantity constraints verified.
- Pull rollback/cursor immobility/conflict preservation verified.
- Stable pending enrollment `DeviceGlobalId` persistence verified through close/reopen.
- Auxiliary FIFO scenarios: 300 cost / 7 remaining; 440 cost / lot B 3 remaining; insufficient stock rejected.

These auxiliary structural/SQLite checks do **not** replace Flutter/.NET compiler or test execution.

## Windows backend SDK validation

Validated on the canonical Windows working copy with .NET SDK 10.0.303:

- `dotnet restore Pos.Server.sln` ? PASS.
- `dotnet build Pos.Server.sln --no-restore` ? PASS.
- `dotnet test Pos.Server.sln --no-build` ? **28/28 PASS, 0 failed, 0 skipped**.
- FASE 17 remote-report integration tests run against isolated SQL Server LocalDB databases.
- General infrastructure tests continue using SQLite where provider-specific SQL Server behavior is not required.
- Build currently reports xUnit1051 cancellation-token analyzer warnings; these do not fail compilation or tests.

## Still not executed due missing Flutter/Android tooling

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- Android Flutter/Gradle build

Flutter/Dart SDK validation remains pending. Backend xUnit validation is now **EXECUTED / 28 OF 28 PASS**.

## Android

Source/config host reconstructed. Standard wrapper executables/JAR are intentionally missing because official artifacts could not be obtained in this runtime. See `docs/ANDROID_RECONSTRUCTION.md`.

## Git policy from this baseline forward

1. private Git remote `https://github.com/RafaelL13/POSFlutter.git` — canonical source;
2. local Git working copy;
3. verified Git bundle;
4. downloadable ZIP checkpoint;
5. ChatGPT File Library as additional backup;
6. runtime filesystem only as temporary execution space.

FASE 17 development starts from canonical checkpoint `ee1c8f78b0f6e446f75b0b1a5ce7af79010aea97`. FASE 18 is not started by this phase.
