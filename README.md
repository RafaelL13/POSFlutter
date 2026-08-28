# POSFlutter

POSFlutter is a reconstructed, offline-first point-of-sale system designed first for Android tablets. The store's operational database is local SQLite; cloud connectivity is complementary and must never prevent sales.

This repository is the **controlled-reconstruction baseline** created after loss of a prior ephemeral runtime. It does not claim that reconstructed files are byte-identical to the lost originals. See `RECOVERY_MANIFEST.md` and `RECONSTRUCTION_REPORT.md` for provenance and validation details.

## Repository layout

```text
POSFlutter_CANONICAL/
├── client/pos_app/              Flutter/SQLite tablet application
├── server/                      ASP.NET Core + EF Core + SQL Server backend
├── docs/                        Reconstruction/Android documentation
├── tools/                       Reproducible structural and SQLite gates
├── RECOVERY_EVIDENCE/           Preserved authentic recovery evidence
├── RECOVERY_MANIFEST.md
├── PROJECT_STATUS.md
└── RECONSTRUCTION_REPORT.md
```

## Core architecture

```text
Android tablet
Flutter
  ↓
SQLite local + FIFO + SyncQueue
  ↓ when available, never required to complete local sale
HTTPS
  ↓
ASP.NET Core API
  ↓
SQL Server
```

Flutter never connects directly to SQL Server. Google Drive or other object storage is for backups/files only, not the operational database.

## Critical rules

- Sales work offline.
- Product quantities are integers only.
- Money is stored as integer cents.
- Purchases create immutable cost lots.
- Sales consume lots FIFO and permanently store sale→lot allocations/costs.
- Critical local operations use SQLite transactions and rollback completely on failure.
- Sync uses durable outbox operations and incremental pull.
- Pull cursor is based on monotonic server `SyncChange.Id`, not timestamp alone.
- Catalog conflicts preserve local and remote versions instead of silently overwriting pending local work.
- Business tenant is derived from authenticated server context, never trusted from an arbitrary client `BusinessId`.
- `AdminReadOnly` may authenticate/pull/read cloud data but cannot perform operational push/write actions server-side.

## Remote reports — FASE 17

Remote reports are separate from offline local reports. The cloud-admin client calls GET-only `/api/admin/reports/*` endpoints through ASP.NET Core; Flutter never connects to SQL Server and never sends an authoritative `BusinessId`. The server derives tenancy from authenticated claims.

Implemented report families: executive summary, sales by day/week/month and paged detail, products/low performance, categories, sellers, purchases, suppliers, current FIFO-valued inventory, expenses, cash sessions, payment methods, cancellations and product trends. Date presets plus tenant-safe `GlobalId` filters cover product/category/supplier/user where semantically applicable. Historical cost uses persisted sale-to-lot allocations; current inventory value uses remaining lot quantities.

See `docs/REMOTE_REPORTS.md` for accounting definitions, period semantics and the current server cash-model limitation.

## Flutter / Android client

Location:

```text
client/pos_app
```

Validated on the canonical Windows working copy with:

- Flutter 3.47.1 stable.
- Dart 3.13.1.
- DevTools 2.60.0.
- Java 17.0.12.
- Gradle 9.3.1.
- Android Gradle Plugin 9.1.1.
- Kotlin Gradle Plugin 2.4.0.
- compileSdk 37.
- targetSdk 36.
- minSdk 24.
- JVM target 17.
- Gradle heap validated at 4 GB with 1 GB metaspace.
- AndroidX enabled.
- Jetifier disabled.
- android.builtInKotlin=false.
- android.newDsl=false.

Actually executed:

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Results:

- flutter pub get: PASS.
- flutter analyze: PASS, 0 issues.
- flutter test: 22/22 PASS.
- flutter build apk --debug: PASS.
- Debug APK size: 190,927,071 bytes.
- Debug APK SHA-256: `4E239606C37C4941E2BFAE041A8CEB8507CF5F0D416236955F3E29881EACE8E5`.

Android runtime validation was executed on a Pixel Tablet AVD using Android 17 / API 37. The application successfully opened the real SQLite database and completed the offline-first operational flow without Internet connectivity.

Validated offline flow:

- first-run business, administrator and device creation;
- local administrator login;
- product and supplier creation;
- two purchases creating FIFO lots;
- cash-session opening;
- complete cash sale;
- inventory movement;
- cash movement;
- pending synchronization outbox;
- force-stop and cold restart;
- persistence verification after restart.

Validated FIFO sale:

- quantity sold: 7 integer units;
- sale price: 15,000 cents per unit;
- revenue: 105,000 cents;
- FIFO cost: 60,000 cents;
- gross profit: 45,000 cents;
- lot 1: 5 units at 8,000 cents, fully consumed;
- lot 2: 2 units at 10,000 cents consumed;
- lot 2 remaining: 3 units;
- final total stock: 3 units.

The sale, FIFO allocations, stock, open cash session, cash movement and pending synchronization survived a force-stop and cold restart.

A real SQLite Android runtime defect was found during validation. `PRAGMA journal_mode = WAL` failed when invoked through `execute`; it was corrected to use `rawQuery`. Runtime startup and the complete offline flow passed after the fix.

The Android Gradle wrapper is now present and executable:

- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`

Known tooling debt:

- `cryptography_flutter` currently applies the Kotlin Gradle Plugin directly. Flutter warns that a future Flutter release will require Built-in Kotlin compatibility.
- The current AGP/Kotlin Built-in Kotlin warnings are classified as future technical debt / plugin dependency; they did not block the validated release build.
- Android release signing is configured without debug-signing fallback. Release credentials are supplied externally through ignored `android/key.properties` or `POSFLUTTER_RELEASE_*` environment variables.
- The release keystore is stored outside the repository. No `.jks`, `.keystore` or `key.properties` file is tracked by Git.
- `flutter build apk --release`: PASS.
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`.
- Release APK size: 54,355,382 bytes.
- Release APK SHA-256: `772A83905B89DB559EE9693238712B8170069B0C66A8FACF487097C37B1A921B`.
- Android `apksigner` verification: PASS using APK Signature Scheme v2.
- Release certificate SHA-256: `1190414E227223377C1DAB5C199A0C3ECA70B57F193B27F82BE082C97843EFC4`.
- Post-release Flutter validation: `flutter analyze` PASS and 22/22 tests PASS.
- Post-release backend validation: build PASS and 28/28 tests PASS.
- Post-signing structural validation: `STRUCTURAL_GATE=PASS`, `HIGH_CONFIDENCE_SECRETS=0`.
- Post-signing SQLite validation: `SQLITE_VALIDATION=PASS`.
- The release APK is a signing-validation artifact, not yet a final production rollout artifact; production environment configuration and deployment remain separate work.

## Backend

Location:

```text
server
```

When .NET 10 SDK is installed:

```text
dotnet restore
dotnet build
dotnet test
```

The reconstructed runtime originally lacked the .NET SDK. The canonical Windows working copy was later validated with .NET SDK 10.0.303:

- restore: PASS
- build: PASS
- tests: **28/28 PASS**

FASE 17 report integration tests use isolated SQL Server LocalDB databases so SQL Server-specific LINQ translation is tested against the production database provider.

Required secrets/configuration must be supplied externally, for example through environment variables/User Secrets. Do not commit SQL passwords or JWT signing keys.

## SQLite validation

A real SQLite auxiliary gate is included:

```text
python3 tools/sqlite_validation.py
```

It validates the reconstructed SQLite migrations, preservation, FK/integrity, integer constraints, pull rollback/cursor, conflicts, enrollment retry identity and FIFO examples. The current canonical checkpoint reports `SQLITE_VALIDATION=PASS`; Flutter tests and Android runtime validation were executed independently.

## Structural gate

```text
python3 tools/structural_gate.py
```

The gate checks the project graph, formats/references/imports, obvious placeholders, high-confidence secrets, tenant/sync/AdminReadOnly structural semantics and known integration regressions. It is not a Dart/C# compiler.

## Git and backup policy

After this reconstructed baseline, meaningful development must occur inside Git. Intended hierarchy:

1. private remote Git repository;
2. local Git working tree;
3. verified Git bundle;
4. downloadable ZIP checkpoint;
5. additional File Library backup;
6. temporary runtime.

See `GIT_REMOTE_SETUP.md` to attach the baseline to a private GitHub repository.
