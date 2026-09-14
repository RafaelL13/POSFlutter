# POSFlutter V1 Physical Tablet UAT Report

Date: 2026-09-13
Candidate HEAD: `8c3f6a0dfa7aa0c01de41e05cd54a56ca676a34a`
APK SHA-256: `271296DE816EA3B70A2DAA0BABA17A8FA9B5346DA869273761CAD6A0B610C196`
Device: `JK132110000931`
Package: `com.posflutter.pos_app`
Evidence directory: `uat_artifacts/20260913_191150`

## Executive result

This is a partial but substantial physical-tablet UAT run against the exact candidate above. Core offline operations exercised in this run persisted correctly: local login/session, Seller purchase, FIFO lot creation, cash opening, five payment scenarios, invalid payment guards, cancellation, cash reconciliation, and force-stop/relaunch recovery.

The candidate is **not production-ready**. A reproducible unhandled Flutter exception occurs after a successful sale cancellation, and cold startup is consistently slow (8.3-10.2 seconds by Android instrumentation). Several required scenarios remain unexecuted, including a physical 6-to-7 upgrade, direct protected-route penetration checks, complete branding editing, manual cash movements, expenses, surplus/shortage closures, and safe online synchronization.

No crash, ANR, SQLite exception, database integrity failure, or confirmed data loss was observed.

## Scenario evidence

| Scenario | Executed | Result | Evidence | Duration | Severity | Notes |
|---|---:|---|---|---:|---|---|
| Candidate identity | Yes | PASS | HEAD/hash/device command output; `CURRENT.txt` | n/a | — | Exact expected HEAD, APK hash, and device matched. |
| Launch and branded login | Yes | PASS_WITH_PERF_ISSUE | `01_start.png`, `06_relaunch_after_18s.png` | 8.3-10.2 s instrumented cold start | P1 | Business name, subtitle, branch and device visible. Fallback logo used. |
| Login with keyboard, landscape | Yes | PASS_WITH_UX_ISSUE | `02_login_keyboard.png` | n/a | P2 | Layout did not overflow, but the primary button was only partially visible/reachable while the keyboard was open. |
| Administrator login | Yes | PASS_WITH_PERF_ISSUE | `07_login_filled.png`, `09_admin_login_after_25s.png` | Completion observed after approximately 25 s; includes polling delay | P1 | No final reliable authentication duration yet. |
| User list and role selector | Yes | PASS | `10_users.png`, `role_dropdown.xml` | n/a | — | IDs hidden; exactly Administrator, Manager, Supervisor, Seller options. |
| Create Seller UAT | Yes | PASS | `11_add_user_filled.png`, `13_seller_created_after_wait.png` | approximately 20-24 s | P1 | `uat_vendedor` persisted and was active. |
| Seller login and navigation | Yes | PASS | `15_seller_login.png`, `16_seller_drawer.png` | n/a | — | Purchases visible. User administration absent. Seller dashboard omits profit/margin. |
| Disable network | Yes | PASS | ADB reported Wi-Fi disabled and network unreachable | n/a | — | Network remained disabled for the offline transaction suite. |
| Seller purchase offline | Yes | PASS | `17_seller_purchases_offline.png` through `21_purchase_confirmed_offline.png` | approximately 25 s commit observation | P1 | Existing supplier/product loaded; purchase #2 confirmed; stock 49 -> 50. |
| Purchase persistence after restart | Yes | PASS | `22_restart_offline.png` | 8.6 s Android cold launch | — | Seller session and stock 50 survived force-stop/relaunch. |
| FIFO lot persistence | Yes | PASS | SQLite read-only snapshot query | n/a | — | Older lot cost 11500 cents was consumed; new 12000-cent lot remained available. `PRAGMA integrity_check=ok`, `foreign_key_check` empty. |
| Cash open offline | Yes | PASS | `23_cash_screen.png`, `24_cash_opened.png` | approximately 20 s commit observation | P1 | Opened with $500.00. |
| Cash sale | Yes | PASS | `27_cash_sale_completed.png` | approximately 25 s commit observation | P1 | $125 cash, $0 change. |
| Card sale | Yes | PASS | `28_card_sale_completed.png` | approximately 25 s commit observation | P1 | Card did not increase physical expected cash. |
| Transfer sale | Yes | PASS | `30_transfer_sale_completed.png` | approximately 25 s commit observation | P1 | Transfer did not increase physical expected cash. |
| Mixed Cash + Card | Yes | PASS | `33_mixed_sale_completed.png`, `34_cash_after_sales.png` | approximately 25 s commit observation | P1 | $50 cash + $75 card; only $50 increased expected cash. |
| Mixed Card + Transfer | Yes | PASS | `36_mixed_card_transfer_completed.png` | approximately 25 s commit observation | P1 | $50 card + $75 transfer; no physical cash component. |
| Mixed underpayment | Yes | PASS | `37_invalid_mixed_under.png`, `invalid_mixed_under.xml` | immediate | — | Assigned $50, remaining $75; charge button disabled. |
| Mixed overpayment | Yes | PASS | `38_invalid_mixed_over.png`, `invalid_mixed_over.xml` | immediate | — | Assigned $250, exceeds $125; charge button disabled with clear error. |
| Quantity over stock | Yes | PASS | `39_overstock_attempt.png`, `overstock_attempt.xml` | immediate | — | Quantity capped at 46 with clear validation message; no sale committed. |
| Sale cancellation with authorization | Yes | PASS_WITH_EXCEPTION | `40_cancel_auth_filled.png`, `42_cancel_success.png`, final logcat | approximately 25 s | P1 | Sale retained as Cancelled; special authorization recorded. Flutter emitted an unhandled `setState` Future exception afterward. |
| Cancellation inventory/FIFO restitution | Yes | PASS | SQLite query; `44_offline_restart_persistence.png` | n/a | — | Stock restored 45 -> 46; payment and lot allocation history retained. |
| Cancellation cash reversal | Yes | PASS_WITH_DISPLAY_ISSUE | `43_cash_after_cancel.png`; SQLite cash movements | n/a | P2 | Expected cash 675 -> 625 and a -$50 cancellation movement exists. “Ventas en efectivo” still displays gross $175, which is potentially confusing. |
| Exact cash close | Yes | PASS | `close_cash_exact_diff.xml`, `45_cash_closed_exact.png` | approximately 25 s | P1 | $625 expected and counted; UI reported “Caja cuadrada”; session closed. |
| Offline force-stop persistence | Yes | PASS | `44_offline_restart_persistence.png` | 8.3 s cold launch | — | 4 active sales/$500, open cash state before closure, stock 46, Seller session and branding persisted. |
| Sync reconnect/idempotency | No | BLOCKED_BY_ENVIRONMENT | `app_environment.dart` default | n/a | — | Debug APK points to `https://10.0.2.2:7043`, an emulator loopback address unsuitable for this tablet. Wi-Fi was not re-enabled for sync. |
| Manual cash deposit/withdrawal | No | NOT_EXECUTED | Seller cash UI | n/a | — | Actions are not exposed to Seller; administrator/special-authorization path remains to be tested. |
| Expenses | No | NOT_EXECUTED | Seller navigation | n/a | — | Not available to Seller in this run. |
| Surplus/shortage close | No | NOT_EXECUTED | — | n/a | — | Would require controlled additional cash sessions. |
| Physical database upgrade 6 -> 7 | No | NOT_PROVEN | SQLite reports schema version 7 | n/a | — | Current database integrity is proven; the physical transition itself was not observed in this run. |
| Full branding edit/logo/color/remove | No | PARTIAL | Login/dashboard screenshots | n/a | — | Existing business branding and fallback persisted; picker/color/remove flow not exercised. |

## Persisted data checks

- SQLite schema version: 7.
- `PRAGMA integrity_check`: `ok`.
- `PRAGMA foreign_key_check`: no rows.
- Pending synchronization records after cancellation: 21.
- Recent payment rows correctly preserve Cash, Card, Transfer, Cash+Card, and Card+Transfer components in cents.
- Cancelled mixed sale retains its two payment rows and sale status `Cancelled`.
- Cancellation audit rows exist for both `Cancel` and `SpecialAuthorization`.
- FIFO allocation for all exercised sales used the older 11500-cent lot; the new purchase created a 12000-cent lot that remained untouched.

## Defects and findings

### P1-01: unhandled exception after cancellation

At 21:53:36 logcat recorded:

`Unhandled Exception: setState() callback argument returned a Future.`

Stack origin:

- `features/sales/presentation/sales_screen.dart:23` in `_SalesScreenState._reload`
- called from `sales_screen.dart:128` in `_SalesScreenState._cancel`

The database transaction completed correctly and the application remained usable, but an unhandled UI exception is not acceptable for production.

### P1-02: slow local operations

- Reproducible Android cold launch: 8327 ms and 10188 ms in this session; an additional run was 8623 ms.
- User creation, purchase commit, sale commit, cancellation, and cash operations visibly remained busy for many seconds. The exact internal duration was not instrumented; the observation windows included deliberate polling waits, so they must not be treated as precise timings.
- Administrator login was visibly pending at 5 seconds and complete by the 25-second observation.

### P2-01: cash summary semantics after cancellation

After cancelling a mixed sale with $50 cash, expected cash correctly decreased by $50 and the cancellation movement was visible, but the “Ventas en efectivo” KPI remained at its gross pre-cancellation value. The summary should label gross/cancelled values or display net cash sales consistently.

### P2-02: login keyboard reachability

At 1920x1080 landscape with the keyboard open, no RenderFlex overflow was logged, but the sign-in action was partially obscured. The primary action should remain fully reachable without relying on keyboard dismissal.

## Runtime diagnostics

- Crashes: 0 confirmed.
- ANRs: 0 confirmed.
- RenderFlex overflows: 0 observed/logged.
- SQLite/Database exceptions: 0 observed/logged.
- Unhandled Flutter exceptions: 1, attributable to the cancellation reload defect above.
- `gfxinfo`: 4 frames rendered, 2 janky (50%). This sample is too small to generalize; one 700 ms frame was recorded.
- Final memory snapshot: total PSS 321479 KB, total RSS 362152 KB, swap PSS 50116 KB. This is a single observation and does not establish a leak.

## Product/UX review (1-5)

| Dimension | Score | Evidence-based assessment |
|---|---:|---|
| Visual hierarchy | 4 | Primary actions and KPI cards are clear. |
| Consistency | 4 | Shared cards, chips and dialogs are visually coherent. |
| Spacing | 4 | Good tablet spacing overall; lower content often requires scrolling. |
| Typography | 4 | Labels and totals are readable at the tested landscape size. |
| Color contrast | 4 | Status and primary controls remained legible. |
| Button clarity | 4 | Payment and cash actions are explicit; keyboard can obscure login action. |
| Form clarity | 4 | Purchase and mixed-payment forms explain remaining/excess amounts well. |
| Error messages | 4 | Invalid totals and stock errors explain what must change. |
| Empty/loading states | 3 | Busy states exist, but waits are long and do not provide progress context. |
| Navigation intuitiveness | 4 | Core Seller flows were discoverable; logout requires scrolling to drawer bottom. |
| POS touch usability | 4 | Large product/payment controls work well on landscape tablet. |
| Checkout usability | 4 | Cash, card, transfer and mixed allocation are understandable and safe. |
| Purchase usability | 4 | Supplier/product selection is legible and IDs remain hidden. |
| Cash usability | 4 | Expected/count/difference are understandable; cancelled-cash KPI semantics need refinement. |
| Settings usability | 2 | Not exercised sufficiently in this run. |
| Branding quality | 3 | Existing name/fallback look professional; complete editing/persistence flow remains untested. |

Overall UX score from executed flows: **3.8/5 (provisional)**.

## Readiness score (provisional)

| Area | Score |
|---|---:|
| Functional correctness | 26/30 |
| Data integrity | 19/20 |
| Offline resilience | 15/15 |
| Security/permissions | 7/10 |
| Performance | 3/10 |
| UX/design | 8/10 |
| Production readiness | 2/5 |
| **Total** | **80/100** |

The score is provisional because several mandatory scenarios are not executed. It must not be interpreted as production certification.

## Required next actions

Must fix before production:

1. Correct and regression-test the async `setState` cancellation reload defect.
2. Profile and reduce cold start and local transaction/login latency.
3. Run remaining security route/repository checks on the physical candidate.
4. Validate the actual 6-to-7 device migration on a preserved version-6 dataset.
5. Configure an explicitly safe test API/SQL environment before reconnecting; then prove sync idempotency and zero duplicate sales, purchases and cash movements.

Should improve:

1. Clarify net versus gross cash-sale KPIs after cancellation.
2. Keep login primary action fully reachable with the landscape keyboard open.
3. Add progress/detail for operations that take longer than one second.

Remaining UAT before a pilot decision:

- Manual deposit/withdrawal and special authorization.
- Expense lifecycle.
- Surplus and shortage closures.
- Full branding picker/color/remove/fallback sequence.
- Portrait matrix for all primary screens and keyboard scenarios.
- Stable multi-screen frame sample and repeated memory observations.

## Decision

- Production ready: **NO**.
- Pilot ready: **NO, pending P1 cancellation fix and completion of the blocked/unexecuted gates**.
- Recommended next action: fix only P1-01 in a small reviewed change with a focused cancellation widget test, rerun Flutter gates, rebuild the candidate, and resume the remaining physical UAT against an explicitly safe sync environment.

## FASE F1 correction history

The original failure remains documented above because it belongs to the physical UAT APK with SHA-256 `271296DE816EA3B70A2DAA0BABA17A8FA9B5346DA869273761CAD6A0B610C196`.

Root cause: `_SalesScreenState._reload` used an expression-bodied `setState` callback whose assignment evaluated to a `Future`. Flutter therefore rejected the asynchronous value returned by the callback after the cancellation had already committed successfully.

Correction: `_reload` now assigns the new loading future inside a block-bodied, synchronous `setState` callback. No repository, FIFO, cash, cancellation, authorization, or synchronization logic changed. A behavioral widget test exercises the cancellation dialog, invokes one injected cancellation, awaits all work, verifies the refreshed `Cancelled` row, and asserts `tester.takeException()` is null.

Pre-commit validation of the correction:

- Directed cancellation widget test: PASS, 1/1.
- Flutter analyzer: PASS, 0 issues.
- Flutter full suite: PASS, 341/341.
- Backend build: PASS with 18 pre-existing xUnit analyzer warnings.
- Backend tests: PASS, 78/78.
- Structural gate: PASS; `HIGH_CONFIDENCE_SECRETS=0`.
- SQLite validation: PASS, integrity/foreign keys/data preservation/rollback/FIFO verified.
- `git diff --check`: PASS.

Status: the source-level correction is validated, but P1-01 remains open until a new APK is built, installed with `adb install -r` without clearing application data, and the cancellation is repeated physically with clean logcat. The new corrective commit and candidate SHA-256 are recorded after creation; physical retest is pending at this point in the history.
