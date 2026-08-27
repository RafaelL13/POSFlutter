# FASE 17 — Remote Reports

## Security and tenancy

Remote reports are read-only and live under `/api/admin/reports`. The route group requires the `Administrator` authorization policy. An `AdminReadOnly` device can therefore read reports when its authenticated user is an Administrator, while operational push remains blocked by the existing server-side device-mode guard.

The client never sends `BusinessId`. Every report receives `SyncTenantContext` from signed JWT claims and validates the active Business/Branch/Device/User chain before querying. Report queries scope SQL data by the authenticated `BusinessId`.

## Time model

Report contracts use two UTC instants:

- `from`: inclusive.
- `to`: exclusive.

The API rejects empty/negative periods and periods longer than 366 days. Flutter presets build local calendar boundaries on the tablet and convert those boundaries to UTC before calling the server. The current `Business` model does not yet contain a business timezone, so the client explicitly exposes this behavior instead of pretending that a server-side business timezone exists.

## Accounting definitions

- `GrossSalesCents`: original value of sales whose status is `Confirmed` or `Cancelled` in the selected period.
- `NetSalesCents`: only `Confirmed` sales.
- `CancelledSalesCents`: original amount of `Cancelled` sales; cancelled sales remain historical and are not deleted.
- `CancellationRatePercent`: cancelled original sales / all original sales (`Confirmed + Cancelled`) by count.
- Historical FIFO cost: sum of persisted `SaleLotAllocation.TotalCostCents`. It is never recomputed from current product price or latest purchase cost.
- Gross profit: net confirmed revenue minus persisted FIFO allocation cost.
- Inventory value: sum of `InventoryLot.AvailableQuantity × InventoryLot.UnitCostCents` for remaining quantities.
- Trend: current period versus the immediately preceding period of equal duration. Revenue change >= +5% is `Growing`, <= -5% is `Declining`, otherwise `Stable`.

## API

All routes below are GET/read-only and require Administrator:

```text
/api/admin/reports/summary
/api/admin/reports/sales
/api/admin/reports/sales/details
/api/admin/reports/products
/api/admin/reports/products/low-performance
/api/admin/reports/categories
/api/admin/reports/users
/api/admin/reports/purchases
/api/admin/reports/suppliers
/api/admin/reports/inventory
/api/admin/reports/expenses
/api/admin/reports/cash
/api/admin/reports/payment-methods
/api/admin/reports/cancellations
/api/admin/reports/trends/products
```

Sales aggregation supports `day`, `week`, and `month`. Purchases support `supplier`, `product`, `day`, and `month`. Low-performance product criteria are explicit: lowest revenue, lowest units, no sales, or negative gross margin. Detail endpoints are paginated and cap page size at 200.

## Cash limitation in the reconstructed domain

The server model currently synchronizes `CashSession`, sales, and expenses, but it does not contain a server-side entity for arbitrary local manual `cash_movements`. For that reason the remote cash report does not invent those missing movements. It calculates:

```text
calculated expected cash = opening balance + confirmed cash sales - cash expenses
```

and also returns the recorded `ExpectedCashCents`, counted cash, and difference from the synchronized cash session when present. A future server cash-movement model can extend this report without changing the current accounting meaning.

## Filtros dimensionales

Además del periodo, la API acepta filtros por `GlobalId` únicamente donde la semántica es inequívoca: producto/categoría en productos, bajo rendimiento, inventario y tendencias; categoría en categorías; proveedor en compras/proveedores; y usuario en ventas, vendedores, gastos, caja y cancelaciones. El servidor vuelve a resolver esos identificadores dentro de `BusinessId` obtenido del JWT, por lo que un `GlobalId` de otro negocio produce cero filas y nunca cambia el tenant. Flutter obtiene las opciones desde los catálogos autenticados existentes y nunca envía `BusinessId`.

## Flutter

Local reports under `/reports` remain unchanged and usable by PointOfSale offline. Remote reports live under:

```text
/cloud-admin/reports
/cloud-admin/reports/:kind
```

The remote UI provides date presets, custom ranges, summary cards, tablet-friendly tables, simple charts for sales/categories/payment methods, and CSV export of the DTO rows already downloaded. No chart dependency was added.

Remote report errors distinguish authentication, authorization, not-found, rate-limit, server, timeout, and network failures. The shared cloud client retries one request after a successful refresh-token exchange on HTTP 401. Tokens and credentials are never rendered in report errors.

## Performance

Aggregations are performed in SQL/EF projections and grouping queries. Sales are first aggregated by day in SQL and only the small daily result is rolled into week/month buckets in memory. Product/category/user/supplier/inventory reporting aggregates server-side or merges bounded aggregate sets; raw transaction histories are not downloaded just to calculate totals.

No EF schema change was required for FASE 17. Existing report queries should be profiled against production-like SQL Server volume before adding date/report indexes; no speculative migration is included.

## Validation status

Available in the reconstruction runtime:

```text
python3 tools/structural_gate.py
python3 tools/sqlite_validation.py
```

Compiler/SDK validation still depends on Flutter/Dart/.NET availability. Tests are written but must not be reported as executed until those SDKs actually run them.
