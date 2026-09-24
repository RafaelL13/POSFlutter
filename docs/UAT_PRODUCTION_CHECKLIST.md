# Production clean-UAT checklist

- [ ] Verify server/package hashes and signed APK metadata.
- [ ] Start empty SQL database; apply migrations; verify health locally and publicly over TLS.
- [ ] On reset tablet: install, first-run, enrollment, administrator login and logout.
- [ ] Disable Wi-Fi: open cash; make cash/card/transfer/mixed sale as supported; verify FIFO, inventory, expense, deposit/withdrawal, close, and restart persistence.
- [ ] Restore Wi-Fi without manual sync: verify push/retry/pull, SQL records, cursor progression, and no duplicate operations.
- [ ] Cancel authorized sale: verify sale status, FIFO restitution, cash effect, audit, and sync.
- [ ] Validate local and central reports: date/range, branch, status, payment method, cancelled amount, costs/profit if authorized, expenses, cash, and inventory.
- [ ] Stop API/SQL/connectivity temporarily: confirm new local sale remains available and no crash occurs.
- [ ] Record screenshots, hashes, logs sanitized of secrets, device version, commit, and test operator.
