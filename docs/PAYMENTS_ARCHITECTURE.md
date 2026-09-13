# POSFlutter Payment Architecture

## 1. Model

A sale owns one or more immutable `SalePayment` rows. The closed method domain is `Cash`, `Card`, and `Transfer`; `Mixed` is only a legacy summary on `sales.payment_method`, never a payment-line method. Monetary values remain integer cents.

SQLite stores `sale_payments(global_id, sale_id, method, amount_cents, created_at)`. SQL Server stores the equivalent `SalePayment` entity with a required 1:N relationship to `Sale`. A sale permits at most one row per method, so the UI can combine repeated tender entries before repository submission.

## 2. Invariants

- A confirmed sale has at least one payment.
- Every payment amount is greater than zero.
- Every method belongs to the closed domain.
- Payment global IDs and `(sale, method)` are unique.
- The exact sum of payment amounts equals `sales.total_cents`.
- Sale, payments, details, FIFO allocations, lot changes, inventory movements, cash movement, audit, and SyncQueue entry commit in one SQLite critical transaction.
- Any failure rolls the complete operation back.

The domain/repository validates before persistence; SQLite constraints and confirmation triggers provide a second integrity boundary; the backend validates the complete aggregate again before EF persistence.

## 3. SQLite and migration

Schema version 6 creates `sale_payments`, indexes by sale and method, and integrity triggers. Upgrade from version 5 deterministically backfills one Cash payment for every positive-total historical sale. The payment uses the sale global ID, making the backfill stable, and `INSERT OR IGNORE` prevents duplicates. The legacy `payment_method` column remains during rollout.

Historical totals, details, allocations, stock, cash movements, SyncQueue records, and audit data are not rewritten. Migration tests open a representative version-5 database, upgrade it, verify integrity and foreign keys, then reopen it to prove the payment is not duplicated.

## 4. SQL Server / EF

`SalePayment` has a required cascade relationship to `Sale`, a unique global ID, a unique `(SaleId, Method)` index, and database checks for positive integer cents and the closed method domain. The additive `AddSalePayments` migration validates legacy rows before backfilling them; it fails visibly rather than guessing an invalid historical method or amount. The original migration and legacy sale column are unchanged.

## 5. Sync

Payments travel inside the Sale aggregate in payload version 2. They are not independent queue operations, preventing partial sale/payment synchronization and ordering races. Each payment has a stable global ID. The server accepts legacy Sale payload version 1 by deriving one payment from its valid legacy method and total; version 2 is accepted only for `Sale/Create`. Other entity payload versions remain unchanged.

Inbound operation IDs and sale idempotency keys preserve retry safety. A duplicate retry returns `AlreadyProcessed` and cannot add payment rows. Invalid sums or lines roll back the inbound marker, sale, payments, and inventory mutations together.

Operational sales are device-originated aggregates and are not pulled back into another POS database by the current architecture. Pull remains for centrally mastered entities. Replaying a cloud sale into SQLite would apply FIFO and stock a second time, so adding cross-device operational replication requires a separate read-model design and is outside this rollout.

## 6. Legacy compatibility

`LEGACY_PAYMENT_STRATEGY=ADDITIVE_BACKFILL_AND_V1_SERVER_FALLBACK`.

- SQLite version 6 backfills historical sales as Cash, matching the only previously supported checkout behavior.
- SQL Server migration backfills only valid positive legacy rows and aborts on ambiguous data.
- Server v1 Sale payloads remain accepted and become one payment row.
- `sales.payment_method` remains populated (`Cash`, `Card`, `Transfer`, or aggregate `Mixed`) for transitional consumers, but new payment reports read `SalePayments`.

Older servers that accept only Sale payload v1 are not compatible with a client emitting v2. Rollout order is therefore: database backup, deploy/migrate server, verify health, then deploy the Phase-C-capable client.

## 7. Cash behavior

Only the sum of `Cash` payment rows affects physical drawer cash. Card and Transfer create no cash movement. For mixed sales, the local Sale cash movement equals only the Cash component.

`receivedCents` is tender metadata on the sale, not payment value. The Cash payment records the amount owed in cash; received cash may be larger, and `change_cents = received_cents - cash_payment_cents`. No-cash sales reject received/change data. This preserves the distinction between tender, revenue, and change without adding mutable payment metadata.

## 8. Cancellation behavior

Cancellation preserves all payment rows for traceability and retains the existing sale status/audit model. SQLite restores the original FIFO allocations and inventory, then creates a negative cash movement for only the original Cash component. Card and Transfer are accounting records only; POSFlutter does not call a banking gateway or claim to execute an external refund. Backend cancellation likewise retains the payment children while restoring inventory under its existing transaction and idempotency rules.

## 9. Reports

Payment-method reports group payment rows, so a mixed sale contributes each component to its real method instead of reporting `Mixed 100%`. Transaction count is distinct per sale within each method. Cash reports calculate sale cash from Cash payment rows only. Cancelled sales remain excluded/reversed according to existing report status semantics.

Legacy detail/list contracts may still expose the aggregate `sales.payment_method` during transition. It is display compatibility, not the source of payment accounting.

## 10. Risks

- Server-before-client deployment ordering is mandatory for payload v2.
- A production database containing invalid legacy payment text or non-positive completed totals blocks the EF migration and requires an audited data repair decision.
- Supporting multiple rows of the same method later would require removing the `(sale, method)` uniqueness rule and defining merge/order semantics.
- Cross-device pull of operational sales cannot reuse mutation payloads safely because it would double-apply inventory.

## 11. Rollout

1. Back up SQL Server and validate legacy sale payment values/totals.
2. Deploy server code and apply `AddSalePayments`.
3. Verify backfill counts, sums, constraints, reports, and sync v1 compatibility.
4. Deploy schema-v6 client; verify local migration and existing Cash operation.
5. Complete Phase C UI and its operational/UAT gates before exposing Card, Transfer, or mixed payment controls.
6. Monitor rejected v2 operations and duplicate/idempotency metrics without logging credentials or sensitive payloads.
