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

## Flutter client

Location:

```text
client/pos_app
```

When Flutter is installed, run from that directory:

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

These commands were **not executed in the reconstruction runtime** because Flutter/Dart were unavailable.

The reconstructed Android source/config host intentionally does not include fabricated `gradlew`, `gradlew.bat` or `gradle-wrapper.jar`. See `docs/ANDROID_RECONSTRUCTION.md` before the first Android build.

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

These commands were **not executed in the reconstruction runtime** because the .NET SDK was unavailable.

Required secrets/configuration must be supplied externally, for example through environment variables/User Secrets. Do not commit SQL passwords or JWT signing keys.

## SQLite validation

A real SQLite auxiliary gate is included:

```text
python3 tools/sqlite_validation.py
```

It validates reconstructed v1→v2→v3 migration, preservation, FK/integrity, integer constraints, pull rollback/cursor, conflicts, enrollment retry identity and FIFO examples. This does not substitute for `flutter test`.

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
