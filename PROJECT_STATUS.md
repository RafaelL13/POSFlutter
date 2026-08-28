# POSFlutter — Project Status

Date: 2026-08-27 (America/Mazatlan)

## Canonical transition

**CONTROLLED RECONSTRUCTION: COMPLETED / FASE 17 CLOSED / BACKEND + FLUTTER + ANDROID OFFLINE RUNTIME VALIDATED**

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

The structural and SQLite gates are auxiliary checks and are now complemented by real Flutter analysis/tests/build, Android runtime execution and .NET compiler/xUnit validation.

## Windows backend SDK validation

Validated on the canonical Windows working copy with .NET SDK 10.0.303:

- `dotnet restore Pos.Server.sln` ? PASS.
- `dotnet build Pos.Server.sln --no-restore` ? PASS.
- `dotnet test Pos.Server.sln --no-build` ? **28/28 PASS, 0 failed, 0 skipped**.
- FASE 17 remote-report integration tests run against isolated SQL Server LocalDB databases.
- General infrastructure tests continue using SQLite where provider-specific SQL Server behavior is not required.
- Build currently reports xUnit1051 cancellation-token analyzer warnings; these do not fail compilation or tests.

## Flutter / Android validation

Validated on the canonical Windows working copy:

- Flutter 3.47.1 stable.
- Dart 3.13.1.
- DevTools 2.60.0.
- Java 17.0.12.
- flutter pub get: PASS.
- flutter analyze: PASS, 0 issues.
- flutter test: 22/22 PASS.
- flutter build apk --debug: PASS.
- Debug APK size: 190,927,071 bytes.
- Debug APK SHA-256: `4E239606C37C4941E2BFAE041A8CEB8507CF5F0D416236955F3E29881EACE8E5`.
- Gradle wrapper: 9.3.1.
- AGP: 9.1.1.
- KGP: 2.4.0.
- compileSdk: 37.
- targetSdk: 36.
- minSdk: 24.
- JVM target: 17.
- Gradle memory validated at -Xmx4G / MaxMetaspaceSize=1G.
- android.enableJetifier=false.
- Pixel Tablet AVD, Android 17 / API 37.
- SQLite Android runtime: PASS.
- SQLite WAL mode: PASS.
- Offline first-run business/admin/device creation: PASS.
- Offline administrator login: PASS.
- Offline product creation: PASS.
- Offline supplier creation: PASS.
- Two offline FIFO purchases: PASS.
- Cash-session requirement before cash sale: PASS.
- Offline cash-session opening: PASS.
- Offline cash sale: PASS.
- FIFO allocation and cost: PASS.
- Inventory movement and final stock: PASS.
- Cash movement: PASS.
- Sale synchronization queue persistence: PASS.
- Cash-session synchronization queue persistence: PASS.
- Force-stop / cold restart persistence: PASS.

Validated sale arithmetic:

- 7 units sold at 15,000 cents = 105,000 cents revenue.
- FIFO allocation: 5 units at 8,000 cents + 2 units at 10,000 cents.
- FIFO cost: 60,000 cents.
- Gross profit: 45,000 cents.
- Initial stock: 10.
- Final stock: 3.

Dashboard after restart reported:

- Sales: $1,050.00.
- Operations: 1.
- FIFO cost: $600.00.
- Gross profit: $450.00.
- Expenses: $0.
- Result: $450.00.

A real Android SQLite compatibility defect was found and corrected: `PRAGMA journal_mode = WAL` must use `rawQuery` with the current sqflite implementation instead of `execute`.

Known tooling debt:

- `cryptography_flutter` applies KGP directly and produces a future Built-in Kotlin compatibility warning.
- AGP reports `android.builtInKotlin=false`, `android.newDsl=false` and direct Kotlin Gradle Plugin usage as future compatibility debt. These warnings did not block the current release build and are not treated as current release blockers.

Android release signing checkpoint:

- Release no longer falls back to debug signing.
- Release signing accepts externally supplied `android/key.properties` values or `POSFLUTTER_RELEASE_*` environment variables.
- Release fails closed when required signing values are missing.
- The real release keystore is external to Git; no keystore or signing-password file is tracked.
- Real `flutter build apk --release`: PASS.
- Release APK size: 54,355,382 bytes.
- Release APK SHA-256: `772A83905B89DB559EE9693238712B8170069B0C66A8FACF487097C37B1A921B`.
- `apksigner verify`: PASS.
- APK signing certificate SHA-256: `1190414E227223377C1DAB5C199A0C3ECA70B57F193B27F82BE082C97843EFC4`.
- Signing environment cleanup: PASS; `POSFLUTTER_RELEASE_*` variables were removed after validation.
- Post-release Flutter analyze: PASS.
- Post-release Flutter tests: 22/22 PASS.
- Post-release backend build: PASS.
- Post-release backend tests: 28/28 PASS.
- Post-signing structural gate: PASS with `HIGH_CONFIDENCE_SECRETS=0`.
- Post-signing SQLite validation: PASS.
- This validates the Android signing microcheckpoint only. It does not claim final production deployment, production API configuration, rollout, AAB publication or production readiness closure.

## Final validation gates

Executed after Flutter/Android stabilization:

- `python tools/structural_gate.py` -> `STRUCTURAL_GATE=PASS`.
- `HIGH_CONFIDENCE_SECRETS=0`.
- Android host structural validation: PASS.
- Android wrapper presence validation: PASS.
- `python tools/sqlite_validation.py` -> `SQLITE_VALIDATION=PASS`.
- SQLite integrity: ok.
- Foreign keys: ok.
- Data preservation: yes.
- Rollback: verified.
- Conflict handling: verified.
- Integer constraints: verified.
- Enrollment device identity: verified.
- FIFO auxiliary scenarios: verified.

## Git policy from this baseline forward

1. private Git remote `https://github.com/RafaelL13/POSFlutter.git` — canonical source;
2. local Git working copy;
3. verified Git bundle;
4. downloadable ZIP checkpoint;
5. ChatGPT File Library as additional backup;
6. runtime filesystem only as temporary execution space.

FASE 17 development starts from canonical checkpoint `ee1c8f78b0f6e446f75b0b1a5ce7af79010aea97`. FASE 18 is not started by this phase.
