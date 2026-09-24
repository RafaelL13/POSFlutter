# Reports functionality

## Local/offline

The dashboard and tablet report repository query SQLite. Confirmed sales are used for operational totals; cancelled sales are excluded from confirmed-sale totals. The local implementation is therefore intended to remain usable when the API is unavailable. The cash read repository derives cash-sale impact from `sale_payments` and does not treat Card or Transfer as physical cash.

## Central/API

Cloud administration report routes are protected API reads and require HTTPS/API availability. They must show a professional offline/error state and must never gate a sale.

## Payment interpretation

`sale_payments` stores Cash, Card, and Transfer rows in cents. A mixed sale is multiple rows, not a fake `Mixed` payment method. Legacy `sales.payment_method` remains a compatibility summary. Metrics must aggregate payment rows; cancelled sales must not inflate sales or expected cash.

## Validation pending

The release gate must execute report repository/API tests for date, branch, cancellation, cash-only expected balance, mixed payments, and offline behavior. Until then this document describes code behavior, not a production certification.
