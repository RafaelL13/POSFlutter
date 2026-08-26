# POSFlutter — Recovery Manifest

Recovery date: 2026-08-24/25 (America/Mazatlan)

## Recovery policy

Only physically mounted files or files whose complete content was recovered from the ChatGPT File Library are placed in this staging tree. No missing Flutter/.NET source has been guessed or regenerated.

Status meanings:

- `RECUPERADO`: authentic content is present in this staging tree.
- `PARCIAL`: authentic evidence exists, but it is not a complete/usable representation of the original component.
- `FALTANTE`: the original file/component is known or strongly evidenced to have existed, but its authentic content was not recoverable.
- `CONFLICTO_DE_VERSION`: multiple authentic versions/evidence exist and the newest compatible build-path version cannot be proven from the available material.

The historical Git hashes below are documentary evidence only; the original `.git` object database is not physically available:

- `339ba70 feat: add local reports exports and verified backups`
- `dd355f3 feat: add tenant-isolated incremental sync pull`
- `0e106fb feat: add tenant-safe cloud administration overview`

## Recovered files

| Archivo / evidencia | Origen | Versión / fecha | Estado | Confianza | Destino / decisión |
|---|---|---|---|---|---|
| `README.md` | Runtime partial recovery + `POSFlutter_FASE16_runtime_recovery.zip` | post-`0e106fb` recovery, 2026-08-25 runtime copy | RECUPERADO | Alta | `README.md` |
| `PROJECT_STATUS.md` | Runtime partial recovery + File Library `file_00000000e6c881fd9d84dd68a3334fe4` | recovery state, File Library 2026-08-25 02:28:57Z | RECUPERADO | Alta | `PROJECT_STATUS.md` |
| `RUNTIME_RECOVERY_NOTE.md` | Runtime partial recovery + File Library `file_00000000a4fc823084d7696881043fc2` | 2026-08-25 02:29:00Z | RECUPERADO | Alta | `RUNTIME_RECOVERY_NOTE.md` |
| `client/pos_app/pubspec.yaml` | File Library `file_000000005f2c81fdadb9e3eb4fc07653` | 2026-08-24 01:26:07Z | RECUPERADO | Alta | `client/pos_app/pubspec.yaml`; complete file content recovered |
| `client/pos_app/lib/sync/sync_repository.dart` | Runtime partial recovery + File Library `file_000000000e5081fd9ee0c7763ec3b07a` | FASE 15-era source, 2026-08-24 02:18:27Z; preserved in later recovery | RECUPERADO | Alta | original build path |
| `server/README.md` | Runtime partial recovery + File Library `file_000000009f6881fd8aa6446981d81f33` | FASE 15/16 documentation, 2026-08-24 03:19:37Z evidence | RECUPERADO | Alta | original path |
| `server/src/Infrastructure/DeviceEnrollmentService.cs` | Runtime partial recovery; older File Library version `file_0000000002e481fba46313495648cfc2` exists | runtime version includes authentic post-library lost-response idempotency fix | RECUPERADO | Alta | runtime recovery version preferred; older library version not copied over it |
| `server/src/Infrastructure/SyncService.cs` | Runtime partial recovery; older File Library version `file_00000000e8ec81fd966c9aca5ac1300d` exists | runtime version includes authentic AdminReadOnly DB-mode enforcement + Device Mode pull fix | RECUPERADO | Alta | runtime recovery version preferred |
| `server/tests/Infrastructure.Tests/DeviceEnrollmentTests.cs` | Runtime partial recovery; older File Library version `file_000000004c1c8230ae3cca979f545333` exists | runtime version includes authentic retry/invalid/expired/Seller/AdminReadOnly tests | RECUPERADO | Alta | runtime recovery version preferred |
| Historical `Program.cs` | File Library `file_000000004a8c81fd8aa8ab29f73ef22c` | 2026-08-24 01:26:08Z, predates FASE 15 tenant-safe endpoints | CONFLICTO_DE_VERSION | Alta that content is authentic; Baja that it represents final state | archived as `RECOVERY_EVIDENCE/historical/Program.cs.pre_phase15`; deliberately **not** installed at build path |
| `POSFlutter_RUNTIME_RECOVERY_REPORT.md` | File Library `file_00000000335081fdb16be876c55593ad` | 2026-08-25 02:36:07Z | RECUPERADO (external evidence) | Alta | retained outside this staging tree as `/mnt/data/POSFlutter_RUNTIME_RECOVERY_REPORT.md`; its facts are summarized here |
| `.gitignore` | Newly created recovery-safety configuration per current recovery requirements | 2026-08-24/25 | RECUPERADO (new metadata/config) | Alta | root; does not attempt to recreate lost source |
| `RECOVERY_INCOMPLETE.md` | Newly created recovery marker | 2026-08-24/25 | RECUPERADO (new metadata) | Alta | root; prevents this partial tree being mistaken for a buildable baseline |
| `RECOVERY_MANIFEST.md` | Newly created from runtime/File Library inventory | 2026-08-24/25 | RECUPERADO (new metadata) | Alta | root |

## Version conflicts resolved conservatively

### `SyncService.cs`

The File Library source from 2026-08-24 02:18:26Z is authentic but predates the later runtime-recovery fixes. Evidence in `RUNTIME_RECOVERY_NOTE.md` records that the mounted recovery copy subsequently added:

- current DB-backed device-mode validation before operational push;
- `AdminReadOnly` rejection for push;
- `PointOfSale` on normal operational device creation;
- `Mode` in `DevicePullPayload`.

Decision: preserve the mounted recovery file at the original build path.

### `DeviceEnrollmentService.cs`

The File Library source is authentic but its redemption logic rejects an already-created `DeviceGlobalId`. The later recovery note documents the authentic lost-response recovery fix using the same `DeviceGlobalId` without duplicate Device/SyncChange.

Decision: preserve the mounted recovery file at the original build path.

### `DeviceEnrollmentTests.cs`

The mounted recovery copy contains the later test additions described by the recovery note.

Decision: preserve the mounted recovery file at the original build path.

### `Program.cs`

Only a pre-FASE-15 copy was recovered. It has `/api/sync/push`, `/api/sales` and dashboard queries without the later `SyncTenantContext` signatures documented by FASE 15/16. Installing it as the current API entrypoint would regress tenant isolation.

Decision: archive as historical evidence only. Current `server/src/Api/Program.cs` remains `FALTANTE`.

## Critical missing authentic files/components

The project status records validation of 64 Dart and 20 C# source files before runtime loss. The recoverable staging tree contains only one Dart implementation file and three current C# implementation/test files. Therefore the following are not assumed or recreated.

| Archivo / componente esperado | Evidencia de existencia | Estado | Confianza | Destino propuesto when recovered |
|---|---|---|---|---|
| Original `.git/` object database/history | historical commits documented; runtime report confirms it was lost | FALTANTE | Alta | root `.git/` or recover from remote/bundle |
| `client/pos_app/analysis_options.yaml` | requested/search target; Flutter project structure | FALTANTE | Media | original Flutter root |
| `client/pos_app/lib/main.dart` | documented Flutter app | FALTANTE | Alta | original path |
| app/router files (`app.dart`, GoRouter routes) | FASE 0 says GoRouter implemented | FALTANTE | Alta | `client/pos_app/lib/app/...` |
| `core/config/app_environment.dart` | explicitly referenced by previous validation/recovery discussions | FALTANTE | Alta | original core config path |
| `core/context/local_app_context.dart` | direct import from recovered `sync_repository.dart` | FALTANTE | Alta | `client/pos_app/lib/core/context/local_app_context.dart` |
| `core/utils/id_generator.dart` | direct import from recovered `sync_repository.dart` | FALTANTE | Alta | `client/pos_app/lib/core/utils/id_generator.dart` |
| `database/app_database.dart` / `AppDatabase` | direct import + FASE 1 status | FALTANTE | Alta | `client/pos_app/lib/database/app_database.dart` |
| SQLite `schema_v1.dart` | FASE 1/15 status explicitly names SchemaV1 | FALTANTE | Alta | database schema path |
| SQLite `schema_v2.dart` | FASE 15 gate explicitly names `schema_v2.dart` | FALTANTE | Alta | database schema path |
| SQLite v3 DeviceMode migration | never completed before runtime loss | FALTANTE / NOT IMPLEMENTED | Alta | must be implemented only after authentic v2 tree is restored |
| `sync/sync_operation.dart` | direct import from recovered `sync_repository.dart` | FALTANTE | Alta | original sync path |
| `sync/sync_pull.dart` | direct import from recovered `sync_repository.dart` | FALTANTE | Alta | original sync path |
| remote sync / `CloudApiClient` / refresh/secure token client | FASE 11/16 status | FALTANTE | Alta | original sync/core network paths |
| `local_backup_provider.dart` + backup abstraction files | FASE 10 + explicit earlier checker discussion | FALTANTE | Alta | original backup feature path |
| first-run/bootstrap/login/session screens/services | FASE 0/2 status | FALTANTE | Alta | original feature paths |
| dashboard/POS/product/category/supplier/purchase/inventory/sales/cash/expenses/report/settings screens/services/repos | FASE 3–10 status | FALTANTE | Alta | original `lib/features/...` paths |
| cloud administration screen/repository | FASE 16 status says implemented at `0e106fb` | FALTANTE | Alta | original FASE 16 Flutter paths |
| Flutter tests (FIFO, DB, sync, cloud admin, etc.) | status says written | FALTANTE | Alta | `client/pos_app/test/...` |
| `server/Pos.Server.sln` | server README exact commands | FALTANTE | Alta | `server/Pos.Server.sln` |
| `server/src/Api/Program.cs` current FASE15/16 | later tenant-safe behavior documented; only stale copy recovered | CONFLICTO_DE_VERSION / FALTANTE current | Alta | original path after authentic current copy is found |
| `server/src/Api/*.csproj` + settings/launch config | server solution documented | FALTANTE | Alta | original paths |
| `server/src/Application/*.csproj` | server architecture documented | FALTANTE | Alta | original path |
| `Contracts.cs` / `DevicePullPayload`, sync/auth/enrollment contracts | current services reference these types | FALTANTE | Alta | Application path |
| `Abstractions.cs` / service interfaces | current services implement/use interfaces | FALTANTE | Alta | Application path |
| `TenantClaims.cs` / tenant context builder | FASE 15 status | FALTANTE | Alta | authentic prior path |
| `server/src/Domain/*.csproj` | solution architecture documented | FALTANTE | Alta | original path |
| `Entities.cs` / Business/Branch/Device/User/Product/.../SyncChange/DeviceEnrollmentToken | current C# files reference these | FALTANTE | Alta | Domain path |
| `server/src/Infrastructure/*.csproj` | solution architecture documented | FALTANTE | Alta | original path |
| `PosDbContext.cs` | current C# files depend on it | FALTANTE | Alta | Infrastructure path |
| `JwtTokenService.cs` / auth service | server/auth status | FALTANTE | Alta | Infrastructure path |
| `TenantReadService.cs` / tenant-safe cloud reads | FASE 16 endpoint implementation status | FALTANTE | Alta | Infrastructure/Application path as originally authored |
| DI registration / Infrastructure service collection | Program/server architecture | FALTANTE | Alta | original path |
| server automated tests other than recovered enrollment tests | FASE 15/16 test matrix documented | FALTANTE | Alta | `server/tests/...` |
| test `.csproj` / `TestDatabase` helpers | recovered test depends on them | FALTANTE | Alta | original test paths |
| `server/.env.example` | server README explicitly names it | FALTANTE | Alta | original path |
| `appsettings.json` / `appsettings.Development.json` current | FASE 15 status/security discussion | FALTANTE | Alta | Api path |
| Dockerfile / docker-compose artifacts | FASE 12 status says Dockerfile existed | FALTANTE | Alta for Dockerfile; Medium for compose | original server/root paths |
| ADR/docs files | FASE 0 says ADRs existed | FALTANTE | Alta | `docs/...` |

## Recovery search coverage

The File Library was searched by filename and semantic content for:

- Flutter roots: `pubspec.yaml`, `analysis_options.yaml`, `main.dart`, app/router/routes, first-run/login/dashboard;
- SQLite: `AppDatabase`, SchemaV1, SchemaV2, migration, backup provider;
- sync: `sync_repository`, `sync_operation`, `sync_pull`, `RemoteSyncRepository`, `CloudApiClient`;
- server projects: `.sln`, `.csproj`, Program, Contracts, Abstractions, Entities, TenantClaims, PosDbContext, JwtTokenService, TenantReadService;
- configuration: appsettings, `.env.example`, Docker/compose, `.gitignore`;
- feature/domain terms: products/categories/suppliers/purchases/FIFO/sales/cash/expenses/reports/admin cloud;
- recent File Library uploads from 2026-08-23 through 2026-08-25.

No complete source archive, Git bundle, `.git` directory, current FASE15/16 `Program.cs`, schema files, solution/project files, or the missing Flutter feature tree was found.

## Consistency observations on the partial staging tree

- `pubspec.yaml` parses as YAML.
- Recovered `sync_repository.dart` has **5 unresolved local imports** because the corresponding authentic files are missing:
  - `core/context/local_app_context.dart`
  - `core/utils/id_generator.dart`
  - `database/app_database.dart`
  - `sync/sync_operation.dart`
  - `sync/sync_pull.dart`
- The C# sources reference missing Domain/Application/DbContext/project files, so the backend cannot be built from this recovery.
- Secret scan of the staging tree found no high-confidence real secret. Test strings such as `StrongPass123!`, `test-access-token`, and `test-refresh-token` are explicit test fixtures/placeholders, not production credentials.
- No code `TODO`, `UnimplementedError`, `NotImplementedException`, or Git conflict markers were found in the recovered staging source/config files.

## Baseline decision

**DO NOT initialize the canonical Git repository from this staging tree.**

Reason: essential build graph files are missing (Flutter entrypoint/database/schemas/features/tests and .NET solution/projects/contracts/entities/DbContext/API entrypoint). A Git baseline created now would only canonize a fragment and could later be mistaken for the recovered application.

The correct deliverable at this point is `POSFlutter_RECOVERED_PARTIAL.zip`. A canonical Git baseline and Git bundle must wait until the authentic full tree is recovered from an external copy, remote, original machine, prior ZIP, or Git bundle.
