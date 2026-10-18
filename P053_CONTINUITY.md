# P053 continuity

Status: IN_PROGRESS. Branch: `feature/posflutter-web-aspnet-integration`.

Completed in this working tree:

- `WebCheckoutService` publishes one `WebSaleInventoryV1` `SyncChange` inside the existing serializable SQL transaction.
- A retry returns before publication; validation failures roll back sale, FIFO movement and event together.
- `Program` registers `WebCheckoutEndpoint` using its fully qualified `Pos.Api` namespace. The prior compile error was namespace resolution, not an excluded source file.
- API Release build passed with zero warnings/errors.
- Backend SQL regression passed: 124/124, no skips. Evidence: `C:\POSFlutter_Web\tests\BUILD_EVIDENCE\P053_BACKEND_SQL_REGRESSION.log`.
- Flutter full regression was still running at the end of this turn; inspect `C:\POSFlutter_Web\tests\BUILD_EVIDENCE\P053_FLUTTER_REGRESSION.log` before claiming its result.

Uncommitted files:

- `server/src/Api/Program.cs`
- `server/src/Infrastructure/WebCheckoutService.cs`
- `server/tests/Infrastructure.Tests/WebCheckoutSqlTests.cs`

Required next action: add an authenticated HTTP integration test against a disposable SQL Server database which posts `/api/web/checkout`, verifies `/api/sync/pull` hides `WebSaleInventory`, verifies capability-gated `/api/sync/pull-v2` returns it, then hands the payload to the existing Android SQLite applier fixture. Only then commit and close P053.
