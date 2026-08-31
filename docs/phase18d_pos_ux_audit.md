# FASE 18D — POS UX audit map

Audit performed from `1c6ed459b3f5ba3f58cdce8a2b7aa437ab5e00a9` before implementation.

| Area | Current flow | Problem | Tablet impact | Target behavior | Business-rule risk | Change required |
|---|---|---|---|---|---|---|
| Product selection | FAB opens a modal list | Context switching and no persistent catalog | Slow repeated sales | Inline local catalog; tap adds one | Low | Presentation + local read helper |
| Search | None | Seller scans a list of up to 100 rows | Poor with large catalog | Immediate offline name/code filter | Low | Controller filter |
| Categories | Not exposed | No quick narrowing | More scrolling | Active category chips from existing schema | Low | Local category read |
| Product card | Text row in modal | Weak price/stock hierarchy | Small touch target | Name, code, MXN price and availability | Low | POS widget |
| Cart | ListTile collection | Duplicate lines and no removal | Dense and error-prone | One row per product with integer controls | Medium | Controller owns UI cart state |
| Stock | Shown but not enforced in UI | Quantity can exceed availability | Failure delayed until checkout | Disable exhausted products and enforce displayed limit | Medium | UI guard; repository FIFO remains final authority |
| Totals | Total only | No subtotal/discount/change | Incomplete checkout context | Subtotal, authorized discount, total and change | Medium | Reuse existing cents semantics |
| Cash | Received automatically equals total | No real cash-entry workflow; open cash discovered late | Operational surprise | Show cash state early; require received >= total | Medium | Bootstrap cash read; repository revalidates |
| Checkout | Single button | Raw errors and no success state | Unclear outcome | Sticky checkout, busy lock, human error, success/reset | High | Controller + existing transaction |
| Double submit | Busy flag in widget | Not independently testable | Duplicate-tap risk | Controller rejects concurrent submit | High | Central `isSubmitting` guard |
| Offline/sync | No POS indicator | Connectivity state invisible | Seller uncertainty | Non-blocking sync summary; never gates local sale | Low | Reuse SyncStatusPanel |
| Abandon cart | Navigation silently drops widget state | Accidental sale loss | Common tablet navigation error | Confirm discard on back and clear | Low | PopScope + destructive dialog |
| Transaction | PosRepository critical transaction | Correct but UI showed raw exceptions | Must not regress | Keep repository/FIFO/cash/audit/sync unchanged | High | Regression tests only |

The implementation does not add schema V6, network catalog queries, payment types, scanner hardware, fractional quantities, or backend features.
