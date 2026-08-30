#!/usr/bin/env python3
"""Real SQLite validation for reconstructed POSFlutter schemas.
This auxiliary validation is not a replacement for flutter test.
"""
from __future__ import annotations
import ast, re, sqlite3, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DB=ROOT/'client/pos_app/lib/database'

def read_statements(path:Path)->list[str]:
    text=path.read_text(encoding='utf-8')
    # Dart schema files contain only raw triple/single-line string literals inside a list.
    values=[]
    pattern=re.compile(r"r(?:'''(.*?)'''|\"\"\"(.*?)\"\"\"|'([^']*)'|\"([^\"]*)\")",re.S)
    for m in pattern.finditer(text):
        value=next(g for g in m.groups() if g is not None)
        if value.lstrip().upper().startswith(('CREATE ','ALTER ','UPDATE ','INSERT ')):
            values.append(value)
    if not values:
        raise AssertionError(f'No SQL statements parsed from {path}')
    return values

def exec_all(db, stmts):
    for sql in stmts: db.execute(sql)

def stock(db, product_id, branch_id):
    return db.execute('SELECT COALESCE(SUM(available_quantity),0) FROM inventory_lots WHERE product_id=? AND branch_id=?',(product_id,branch_id)).fetchone()[0]

def fifo_allocate(db, product_id, branch_id, quantity):
    rows=db.execute('SELECT id,available_quantity,unit_cost_cents FROM inventory_lots WHERE product_id=? AND branch_id=? AND available_quantity>0 AND active=1 ORDER BY entry_date,id',(product_id,branch_id)).fetchall()
    remaining=quantity; allocations=[]; cost=0
    for lot_id,available,unit_cost in rows:
        if remaining<=0: break
        take=min(remaining,available); allocations.append((lot_id,take,unit_cost)); cost+=take*unit_cost; remaining-=take
    if remaining: raise ValueError('insufficient stock')
    return allocations,cost

def main():
    v1=read_statements(DB/'schema_v1.dart'); v2=read_statements(DB/'schema_v2.dart'); v3=read_statements(DB/'schema_v3.dart'); v4=read_statements(DB/'schema_v4.dart'); v5=read_statements(DB/'schema_v5.dart')
    with tempfile.TemporaryDirectory() as td:
        path=Path(td)/'migration.db'
        db=sqlite3.connect(path); db.execute('PRAGMA foreign_keys=ON'); exec_all(db,v1)
        now='2026-08-25T12:00:00Z'
        bid=db.execute("INSERT INTO businesses(global_id,name,created_at,updated_at) VALUES('business-gid','Business',?,?)",(now,now)).lastrowid
        brid=db.execute("INSERT INTO branches(global_id,business_id,name,created_at,updated_at) VALUES('branch-gid',?,'Main',?,?)",(bid,now,now)).lastrowid
        did=db.execute("INSERT INTO devices(global_id,branch_id,name,created_at) VALUES('device-gid',?,'POS',?)",(brid,now)).lastrowid
        uid=db.execute("INSERT INTO users(global_id,business_id,name,username,password_hash,password_salt,role,created_at,updated_at) VALUES('user-gid',?,'Admin','admin','h','s','Administrator',?,?)",(bid,now,now)).lastrowid
        cid=db.execute("INSERT INTO categories(global_id,business_id,name,created_at,updated_at) VALUES('category-gid',?,'Seafood',?,?)",(bid,now,now)).lastrowid
        sid=db.execute("INSERT INTO suppliers(global_id,business_id,name,created_at,updated_at) VALUES('supplier-gid',?,'Supplier',?,?)",(bid,now,now)).lastrowid
        pid=db.execute("INSERT INTO products(global_id,business_id,code,name,category_id,presentation,sale_price_cents,minimum_stock,created_at,updated_at) VALUES('product-gid',?,'P1','Product',?,'Piece',18050,2,?,?)",(bid,cid,now,now)).lastrowid
        purchase=db.execute("INSERT INTO purchases(global_id,supplier_id,branch_id,device_id,user_id,purchase_date,total_cents,created_at) VALUES('purchase-gid',?,?,?,?,?,12000,?)",(sid,brid,did,uid,now,now)).lastrowid
        pd=db.execute("INSERT INTO purchase_details(global_id,purchase_id,product_id,quantity,unit_cost_cents,subtotal_cents) VALUES('pd-gid',?,?,10,1200,12000)",(purchase,pid)).lastrowid
        lot=db.execute("INSERT INTO inventory_lots(global_id,product_id,purchase_detail_id,branch_id,entry_date,initial_quantity,available_quantity,unit_cost_cents,created_at) VALUES('lot-gid',?,?,?,?,10,7,1200,?)",(pid,pd,brid,now,now)).lastrowid
        sale=db.execute("INSERT INTO sales(global_id,idempotency_key,folio,sale_datetime,user_id,device_id,branch_id,subtotal_cents,total_cents,fifo_cost_cents,gross_profit_cents,payment_method,change_cents,created_at,updated_at) VALUES('sale-gid','idem-gid','V1',?,?,?,?,18050,18050,1200,16850,'Cash',0,?,?)",(now,uid,did,brid,now,now)).lastrowid
        sd=db.execute("INSERT INTO sale_details(global_id,sale_id,product_id,quantity,unit_price_cents,total_cents,fifo_cost_cents) VALUES('sd-gid',?,?,1,18050,18050,1200)",(sale,pid)).lastrowid
        db.execute("INSERT INTO sale_detail_lots(global_id,sale_detail_id,inventory_lot_id,quantity,unit_cost_cents,total_cost_cents) VALUES('sdl-gid',?,?,1,1200,1200)",(sd,lot))
        db.commit()
        before={'business':db.execute('SELECT global_id,name FROM businesses').fetchone(),'device':db.execute('SELECT global_id FROM devices').fetchone(),'product':db.execute('SELECT global_id,sale_price_cents,minimum_stock FROM products').fetchone(),'sale':db.execute('SELECT global_id,total_cents,fifo_cost_cents FROM sales').fetchone(),'lot':db.execute('SELECT global_id,initial_quantity,available_quantity,unit_cost_cents FROM inventory_lots').fetchone()}
        exec_all(db,v2); db.execute("UPDATE app_settings SET value='123' WHERE key='sync_pull_cursor'"); exec_all(db,v3); exec_all(db,v4); exec_all(db,v5); db.commit(); db.close()
        db=sqlite3.connect(path); db.execute('PRAGMA foreign_keys=ON')
        assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        assert db.execute('PRAGMA foreign_key_check').fetchall()==[]
        after={'business':db.execute('SELECT global_id,name FROM businesses').fetchone(),'device':db.execute('SELECT global_id FROM devices').fetchone(),'product':db.execute('SELECT global_id,sale_price_cents,minimum_stock FROM products').fetchone(),'sale':db.execute('SELECT global_id,total_cents,fifo_cost_cents FROM sales').fetchone(),'lot':db.execute('SELECT global_id,initial_quantity,available_quantity,unit_cost_cents FROM inventory_lots').fetchone()}
        assert before==after
        assert db.execute("SELECT mode FROM devices WHERE global_id='device-gid'").fetchone()[0]=='PointOfSale'
        assert db.execute("SELECT value FROM app_settings WHERE key='sync_pull_cursor'").fetchone()[0]=='123'
        assert db.execute('SELECT server_version FROM products').fetchone()[0]==0
        assert db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='special_authorization_grants'").fetchone()[0]=='special_authorization_grants'
        db.execute("INSERT INTO special_authorization_grants(global_id,capability,requirement,performed_by_user_global_id,authorized_by_user_global_id,business_global_id,device_global_id,reason,authorized_at) VALUES('grant-1','saleCancel','SecondUserAuthorization','user-gid','manager-gid','business-gid','device-gid','Reason',?)",(now,)); db.commit()
        assert db.execute("UPDATE special_authorization_grants SET consumed_at=?,operation='Cancel',entity_type='Sale',entity_global_id='sale-gid' WHERE global_id='grant-1' AND consumed_at IS NULL",(now,)).rowcount==1
        assert db.execute("UPDATE special_authorization_grants SET consumed_at=? WHERE global_id='grant-1' AND consumed_at IS NULL",(now,)).rowcount==0
        db.commit()
        try:
            db.execute("INSERT INTO special_authorization_grants(global_id,capability,requirement,performed_by_user_global_id,authorized_by_user_global_id,business_global_id,device_global_id,reason,authorized_at) VALUES('grant-empty','saleCancel','SecondUserAuthorization','user-gid','manager-gid','business-gid','device-gid','   ',?)",(now,)); db.commit(); raise AssertionError('empty authorization reason accepted')
        except sqlite3.IntegrityError: db.rollback()
        columns={r[1] for r in db.execute('PRAGMA table_info(sync_queue)')}
        assert {'error_category','error_code','requires_action'} <= columns
        db.execute("INSERT INTO sync_queue(global_id,entity_type,entity_global_id,operation,payload_json,created_at,status,error_category,error_code,requires_action) VALUES('terminal-op','Sale','sale-terminal','Create','{}',?,'Error','AUTHORIZATION_REJECTED','RoleDenied',1)",(now,)); db.commit()
        assert db.execute("SELECT COUNT(*) FROM sync_queue WHERE status='Pending' OR (status='Error' AND next_attempt_at IS NOT NULL AND next_attempt_at<=?)",(now,)).fetchone()[0]==0
        assert db.execute("SELECT error_category,error_code,requires_action,next_attempt_at FROM sync_queue WHERE global_id='terminal-op'").fetchone()==('AUTHORIZATION_REJECTED','RoleDenied',1,None)
        # SQLite-level integer enforcement.
        try:
            db.execute("UPDATE products SET sale_price_cents=1.5 WHERE id=?",(pid,)); db.commit(); raise AssertionError('fractional money accepted')
        except sqlite3.IntegrityError: db.rollback()
        try:
            db.execute("UPDATE inventory_lots SET available_quantity=1.5 WHERE id=?",(lot,)); db.commit(); raise AssertionError('fractional quantity accepted')
        except sqlite3.IntegrityError: db.rollback()
        # Cursor/data/conflict must rollback atomically.
        try:
            db.execute('BEGIN')
            db.execute("UPDATE products SET name='Remote name',server_version=2 WHERE id=?",(pid,))
            db.execute("INSERT INTO sync_conflicts(global_id,entity_type,entity_global_id,source,local_payload_json,remote_payload_json,remote_version,remote_cursor,detected_at,status) VALUES('conflict-rollback','Product','product-gid','Pull','{\"name\":\"Local\"}','{\"name\":\"Remote\"}',2,124,?,'Pending')",(now,))
            db.execute("UPDATE app_settings SET value='124' WHERE key='sync_pull_cursor'")
            raise RuntimeError('forced')
        except RuntimeError: db.rollback()
        assert db.execute("SELECT name,server_version FROM products WHERE id=?",(pid,)).fetchone()==('Product',0)
        assert db.execute("SELECT value FROM app_settings WHERE key='sync_pull_cursor'").fetchone()[0]=='123'
        assert db.execute("SELECT COUNT(*) FROM sync_conflicts WHERE global_id='conflict-rollback'").fetchone()[0]==0
        db.execute("INSERT INTO sync_conflicts(global_id,entity_type,entity_global_id,source,local_payload_json,remote_payload_json,remote_version,remote_cursor,detected_at,status) VALUES('conflict-persist','Product','product-gid','Pull','{\"name\":\"Local\"}','{\"name\":\"Remote\"}',3,125,?,'Pending')",(now,)); db.commit()
        c=db.execute("SELECT local_payload_json,remote_payload_json,remote_version,remote_cursor,status FROM sync_conflicts WHERE global_id='conflict-persist'").fetchone()
        assert c==('{"name":"Local"}','{"name":"Remote"}',3,125,'Pending')
        assert db.execute('SELECT name FROM products WHERE id=?',(pid,)).fetchone()[0]=='Product'
        # Enrollment retry identity is persisted in SQLite so a lost response can reuse the same DeviceGlobalId.
        db.execute("INSERT OR REPLACE INTO app_settings(key,value,updated_at) VALUES('pending_enrollment_device_global_id','enrollment-device-gid',?)",(now,)); db.commit(); db.close()
        db=sqlite3.connect(path)
        assert db.execute("SELECT value FROM app_settings WHERE key='pending_enrollment_device_global_id'").fetchone()[0]=='enrollment-device-gid'
        db.close()

    # Auxiliary FIFO scenarios against real SQLite rows.
    for lots,qty,expected_cost,expected_remaining in [([(10,100)],3,300,[7]), ([(2,100),(5,120)],4,440,[0,3])]:
        db=sqlite3.connect(':memory:'); db.execute('CREATE TABLE inventory_lots(id INTEGER PRIMARY KEY,product_id INTEGER,branch_id INTEGER,entry_date TEXT,available_quantity INTEGER,unit_cost_cents INTEGER,active INTEGER)')
        for i,(available,cost) in enumerate(lots,1): db.execute('INSERT INTO inventory_lots VALUES(?,?,?,?,?,?,1)',(i,1,1,f'2026-01-{i:02d}',available,cost))
        alloc,cost=fifo_allocate(db,1,1,qty); assert cost==expected_cost
        for lot_id,take,_ in alloc: db.execute('UPDATE inventory_lots SET available_quantity=available_quantity-? WHERE id=?',(take,lot_id))
        assert [r[0] for r in db.execute('SELECT available_quantity FROM inventory_lots ORDER BY id')]==expected_remaining
        db.close()
    db=sqlite3.connect(':memory:'); db.execute('CREATE TABLE inventory_lots(id INTEGER PRIMARY KEY,product_id INTEGER,branch_id INTEGER,entry_date TEXT,available_quantity INTEGER,unit_cost_cents INTEGER,active INTEGER)'); db.execute("INSERT INTO inventory_lots VALUES(1,1,1,'2026-01-01',7,100,1)")
    try: fifo_allocate(db,1,1,8); raise AssertionError('insufficient FIFO stock accepted')
    except ValueError: pass
    print('SQLITE_VALIDATION=PASS')
    print(f'V1_STATEMENTS={len(v1)} V2_STATEMENTS={len(v2)} V3_STATEMENTS={len(v3)} V4_STATEMENTS={len(v4)} V5_STATEMENTS={len(v5)}')
    print('INTEGRITY=ok FOREIGN_KEYS=ok DATA_PRESERVED=yes DEVICE_MODE=PointOfSale CURSOR=123')
    print('ROLLBACK=verified CONFLICT=verified INTEGER_CONSTRAINTS=verified ENROLLMENT_DEVICE_ID=verified GRANT_REPLAY=blocked TERMINAL_SYNC_RETRY=blocked')
    print('FIFO_CASE1=cost300_remaining7 FIFO_CASE2=cost440_remainingB3 FIFO_CASE3=rejected')

if __name__=='__main__': main()
