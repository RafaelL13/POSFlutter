# POSFlutter — Recovery and Reconstruction Manifest

Date: 2026-08-25 (America/Mazatlan)

## Provenance policy

The original complete ephemeral Git object database was not recoverable. The current project was produced by **controlled reconstruction** using this precedence:

1. authentic recovered source;
2. prior `PROJECT_STATUS.md` / recovery manifests and reports;
3. project README/backend documentation;
4. the original functional specification and documented historical phase behavior.

Provenance labels used below:

- **RECOVERED_AUTHENTIC** — byte/source content physically recovered from the prior project/runtime.
- **RECONSTRUCTED_FROM_AUTHENTIC** — functional copy based on recovered source but repaired/integrated for the reconstructed graph. The untouched recovered copy is retained under `RECOVERY_EVIDENCE/`.
- **RECONSTRUCTED** — recreated from documented behavior/architecture; it is not claimed to be the lost original file.
- **NEW_IMPLEMENTATION** — code/tests/tooling added during controlled reconstruction to close an explicitly documented requirement or validation gap.
- **PENDING_EXTERNAL_TOOL** — intentionally absent because an external official tool/artifact is required.

Historical hashes are documentary references only and are **not present in the new Git object database**:

- `339ba70 feat: add local reports exports and verified backups`
- `dd355f3 feat: add tenant-isolated incremental sync pull`
- `0e106fb feat: add tenant-safe cloud administration overview`

## Component provenance

| Component | Provenance | Notes |
|---|---|---|
| `RECOVERY_EVIDENCE/current_runtime/*` | RECOVERED_AUTHENTIC | Preserved evidence including recovered `SyncService.cs`, `DeviceEnrollmentService.cs`, `Program.cs`, `Entities.cs`, `PosDbContext.cs`, `sync_repository.dart` and pre-rebuild manifest/SHA list. Evidence is excluded from functional-source checks. |
| `client/pos_app/pubspec.yaml` | RECOVERED_AUTHENTIC / reconstructed placement | Dependency set was recovered from File Library and restored to the Flutter root. |
| `client/pos_app/lib/sync/sync_repository.dart` | RECONSTRUCTED_FROM_AUTHENTIC | Recovered implementation retained as basis; functional graph/schemas were reconstructed around it. Evidence copy remains immutable. |
| `server/src/Infrastructure/SyncService.cs` | RECONSTRUCTED_FROM_AUTHENTIC | Based on recovered FASE 15/16 service. Functional copy received only compatibility repairs documented in the reconstruction report; evidence copy remains unchanged. |
| `server/src/Infrastructure/DeviceEnrollmentService.cs` | RECONSTRUCTED_FROM_AUTHENTIC | Recovered enrollment/idempotency implementation integrated into the new graph; evidence copy preserved. |
| `server/src/Api/Program.cs`, `server/src/Domain/Entities.cs`, `server/src/Infrastructure/PosDbContext.cs` | RECONSTRUCTED_FROM_AUTHENTIC | Current-runtime copies were preserved before rebuilding; functional copies were integrated with the reconstructed solution. |
| Flutter app entrypoint, router, core services and feature tree | RECONSTRUCTED | Recreated from documented phase behavior: first run, auth, dashboard, POS, catalogs, purchases, FIFO/inventory, sales/cancellation, cash, expenses, reports/CSV, backups, users/settings and cloud admin. |
| SQLite `schema_v1.dart`, `schema_v2.dart`, `schema_v3.dart`, `AppDatabase` | RECONSTRUCTED | Recreated from documented 21-table offline-first schema and FASE 15/16 migrations; executed against real SQLite by `tools/sqlite_validation.py`. |
| Flutter sync models/client/secure storage/bootstrap/enrollment integration | RECONSTRUCTED | Recreated to satisfy the recovered `sync_repository.dart` contracts and documented push/pull/conflict behavior. |
| Flutter tests under `client/pos_app/test/` | NEW_IMPLEMENTATION / RECONSTRUCTED TEST COVERAGE | Meaningful tests for FIFO, money totals, DeviceMode, schema constraints, sync records/pull models and enrollment contract. Written but not executed without Flutter SDK. |
| Android source/config host | RECONSTRUCTED | Kotlin/Gradle source/config only. See `docs/ANDROID_RECONSTRUCTION.md`. |
| `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar` | PENDING_EXTERNAL_TOOL | Not fabricated; official wrapper artifacts required before Android build. |
| .NET solution and `.csproj` graph | RECONSTRUCTED | New coherent solution around recovered services; historical `.git` is not reproduced. |
| Application contracts/abstractions | RECONSTRUCTED | Contracts aligned with recovered sync/enrollment services and Flutter payloads. |
| Domain/EF model and tenant indexes | RECONSTRUCTED_FROM_AUTHENTIC / RECONSTRUCTED | Current-runtime entity/context evidence preserved; functional model completed for the new solution. |
| JWT/refresh/tenant claims/read service | RECONSTRUCTED | Recreated from FASE 14–16 documentation. |
| Backend tests | NEW_IMPLEMENTATION plus recovered test intent | Tenant isolation, pull pagination/cursor, push idempotency/conflict, enrollment/revocation/cross-tenant/Seller, and AdminReadOnly restrictions. Written but not executed without .NET SDK. |
| `tools/structural_gate.py` | NEW_IMPLEMENTATION | Reproducible auxiliary structural/security gate. Not a compiler/analyzer substitute. |
| `tools/sqlite_validation.py` | NEW_IMPLEMENTATION | Executes v1→v2→v3, data preservation, integer constraints, cursor rollback/conflicts, enrollment retry identity and FIFO using real Python SQLite. |
| Root/backend documentation and remote setup | RECONSTRUCTED | Records the controlled-reconstruction baseline and future canonical Git workflow. |

## Authentic evidence integrity

`RECOVERY_EVIDENCE/current_runtime/SHA256SUMS.txt` records the preserved evidence hashes captured before reconstruction in this runtime. Functional files may intentionally differ from those evidence copies; provenance is documented rather than hidden.

## External validation still required

The following cannot be represented as completed until their tools are available:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- `dotnet restore`
- `dotnet build`
- `dotnet test`
- `dotnet ef migrations add ...`
- Android Gradle build

The new Git baseline records a structurally validated reconstruction, **not a production release certification**.
