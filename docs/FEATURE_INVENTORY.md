# Feature inventory

Status is based on route/drawer/repository inspection. `TESTED` means a release gate still requires recorded command/UAT evidence; it is not implied by visibility.

| Module | Visible | Functional path | Offline | Requires API | Role-gated | Status |
|---|---:|---|---:|---:|---:|---|
| Dashboard | Yes | local home/report repositories | Yes | No | Yes | IMPLEMENTED |
| POS / sales | Yes | POS repository → SQLite/FIFO/SyncQueue | Yes | No | Yes | IMPLEMENTED |
| Products, categories, suppliers | Yes | local repositories → SQLite/SyncQueue | Yes | No | Yes | IMPLEMENTED |
| Purchases / inventory | Yes | purchase/FIFO/inventory repositories | Yes | No | Yes | IMPLEMENTED |
| Cash / expenses | Yes | cash and expense repositories | Yes | No | Yes | IMPLEMENTED |
| Local reports | Yes | report repository → SQLite | Yes | No | Yes | IMPLEMENTED; scope validation pending |
| Cloud admin/reports | Yes | HTTPS API endpoints | No | Yes | Yes | IMPLEMENTED; offline-state validation pending |
| Users / backup / settings / about | Yes | route-specific repositories/providers | Varies | Varies | Yes | IMPLEMENTED; clean-UAT validation pending |
| First run / enrollment | Conditional | bootstrap/enrollment flow | Setup needs API | Yes | N/A | IMPLEMENTED; clean device test pending |

There are no product-visible placeholders approved for release. Any discovered PARTIAL/BROKEN action must be implemented or removed before release certification.
