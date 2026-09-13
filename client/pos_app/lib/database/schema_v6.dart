const List<String> schemaV6Statements = [
  r'''CREATE TABLE sale_payments(id INTEGER PRIMARY KEY AUTOINCREMENT,global_id TEXT NOT NULL UNIQUE,sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,method TEXT NOT NULL CHECK(method IN('Cash','Card','Transfer')),amount_cents INTEGER NOT NULL CHECK(typeof(amount_cents)='integer' AND amount_cents>0),created_at TEXT NOT NULL,UNIQUE(sale_id,method))''',
  r'''CREATE INDEX ix_sale_payments_sale ON sale_payments(sale_id)''',
  r'''CREATE INDEX ix_sale_payments_method ON sale_payments(method,sale_id)''',
  r'''INSERT OR IGNORE INTO sale_payments(global_id,sale_id,method,amount_cents,created_at) SELECT global_id,id,'Cash',total_cents,created_at FROM sales WHERE total_cents>0''',
  r'''CREATE TRIGGER sale_confirmed_legacy_payment AFTER INSERT ON sales WHEN NEW.status='Confirmed' AND NEW.total_cents>0 BEGIN INSERT INTO sale_payments(global_id,sale_id,method,amount_cents,created_at) VALUES(NEW.global_id,NEW.id,NEW.payment_method,NEW.total_cents,NEW.created_at); END''',
  r'''CREATE TRIGGER sale_confirmed_requires_payments_update BEFORE UPDATE OF status,total_cents ON sales WHEN NEW.status='Confirmed' AND (SELECT COALESCE(SUM(amount_cents),0) FROM sale_payments WHERE sale_id=NEW.id)<>NEW.total_cents BEGIN SELECT RAISE(ABORT,'confirmed sale payments must equal total'); END''',
  r'''CREATE TRIGGER confirmed_sale_payment_insert BEFORE INSERT ON sale_payments WHEN (SELECT status FROM sales WHERE id=NEW.sale_id)='Confirmed' AND (SELECT COALESCE(SUM(amount_cents),0) FROM sale_payments WHERE sale_id=NEW.sale_id)+NEW.amount_cents<>(SELECT total_cents FROM sales WHERE id=NEW.sale_id) BEGIN SELECT RAISE(ABORT,'confirmed sale payments are immutable'); END''',
  r'''CREATE TRIGGER confirmed_sale_payment_update BEFORE UPDATE ON sale_payments WHEN (SELECT status FROM sales WHERE id=OLD.sale_id)='Confirmed' BEGIN SELECT RAISE(ABORT,'confirmed sale payments are immutable'); END''',
  r'''CREATE TRIGGER confirmed_sale_payment_delete BEFORE DELETE ON sale_payments WHEN (SELECT status FROM sales WHERE id=OLD.sale_id)='Confirmed' BEGIN SELECT RAISE(ABORT,'confirmed sale payments are immutable'); END''',
];
