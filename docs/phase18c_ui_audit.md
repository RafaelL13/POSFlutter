# FASE 18C — UI audit map

Audit performed before migration from HEAD `ae02400fa2812cd388f2f99c539da434db95b15c`.

| Screen | Current style | Inconsistencies | Density | Tablet usability | Reusable pattern | Target component |
|---|---|---|---|---|---|---|
| Login | Centered default Card | Uppercase copy, fixed width, no offline context | Low | Adequate but generic | Authentication panel | AppCard, AppTextField, AppPrimaryButton |
| First run | Centered Card | Inline fields/dialog and magic spacing | Low | Adequate | Onboarding panel | Theme, AppDialog, AppTextField |
| Home/dashboard | Custom cards/grid | Local breakpoints and repeated card styles | Medium | Good | Header, KPI, quick actions, sync | AppBreakpoints, AppKpiCard, AppSection |
| POS | Two-column Scaffold | Fixed checkout width overflows phone | High | Good landscape only | Cart row, checkout summary | Global theme, responsive composition |
| Sales | Generic database list | Raw map subtitle and destructive action styled as normal | Medium | Touch rows acceptable | Entity list | AppPage, AppErrorState, AppDialog |
| Cash | Nested Scaffolds | Competing headers and raw cents in forms | Medium | Wasted vertical space | List plus actions | AppPage, AppPrimaryButton, AppSecondaryButton |
| Products/categories/suppliers | Generic database list | Raw map, FAB-only action, no descriptions | Medium | Sparse | Catalog list/form | AppPage, AppTextField, AppEmptyState |
| Purchases/inventory/expenses | Generic database list | Technical values and inconsistent fields | Medium | Sparse | Entity list/form | AppPage, AppTextField, AppDialog |
| Reports | Loose ListTiles | No grouping/loading system | Low | Too narrow visually | Metrics and export action | AppPage, AppCard, AppLoadingState |
| Users | Generic database list | Raw database fields | Medium | Sparse | Entity list | AppPage, AppEmptyState |
| Backup | Single centered button | No impact/context hierarchy | Low | Underuses canvas | Protected operation | AppPage, AppCard, AppPrimaryButton |
| Cloud admin | Cards/ListTiles | Raw payloads and ad-hoc errors | Medium | Functional | Remote resource list | Global theme and shared states |
| Sync status | ListTile and ad-hoc dialog | Status not semantically centralized | Compact | Good | Operational status | AppStatusChip, AppDialog |
| Navigation | Drawer/ListTiles | Plain brand header and weak selected hierarchy | Medium | Good | Grouped destinations | Themed Drawer and group labels |
| Dialogs/forms | AlertDialog/TextField inline | Repeated padding, mixed numeric keyboards | Medium | Adequate | Form/confirmation | AppDialog, AppTextField |
| Empty/loading/error | Text or spinner per screen | No retry/action consistency | Low | Inconsistent | State feedback | AppEmptyState, AppLoadingState, AppErrorState |

No backend, database, sync, FIFO, authorization policy, or role-based visibility change is part of this migration.
