import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:pos_app/database/schema_v4.dart';
import 'package:pos_app/database/schema_v5.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'v5 Cash sale migrates once without changing commercial history',
    () async {
      final root = await databaseFactoryFfi.getDatabasesPath();
      final path = p.join(
        root,
        'payments-migration-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      addTearDown(() => databaseFactoryFfi.deleteDatabase(path));
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, _) async {
            for (final statement in [
              ...schemaV1Statements,
              ...schemaV2Statements,
              ...schemaV3Statements,
              ...schemaV4Statements,
              ...schemaV5Statements,
            ]) {
              await db.execute(statement);
            }
          },
        ),
      );
      final ids = await _seedLegacySale(legacy);
      await legacy.close();

      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(database.close);
      var db = await database.open();
      await _assertMigrated(db, ids);
      await database.close();
      db = await database.open();
      await _assertMigrated(db, ids);
      expect(await _count(db, 'sale_payments'), 1);
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}

Future<({int saleId, int productId})> _seedLegacySale(Database db) async {
  final now = DateTime.utc(2026, 9, 13).toIso8601String();
  final businessId = await db.insert('businesses', {
    'global_id': 'legacy-business',
    'name': 'Legacy',
    'created_at': now,
    'updated_at': now,
  });
  final branchId = await db.insert('branches', {
    'global_id': 'legacy-branch',
    'business_id': businessId,
    'name': 'Main',
    'created_at': now,
    'updated_at': now,
  });
  final deviceId = await db.insert('devices', {
    'global_id': 'legacy-device',
    'branch_id': branchId,
    'name': 'POS',
    'mode': 'PointOfSale',
    'created_at': now,
    'updated_at': now,
  });
  final userId = await db.insert('users', {
    'global_id': 'legacy-user',
    'business_id': businessId,
    'name': 'User',
    'username': 'user',
    'password_hash': 'h',
    'password_salt': 's',
    'role': 'Administrator',
    'created_at': now,
    'updated_at': now,
  });
  final productId = await db.insert('products', {
    'global_id': 'legacy-product',
    'business_id': businessId,
    'code': 'P',
    'name': 'Product',
    'presentation': 'Piece',
    'sale_price_cents': 100,
    'created_at': now,
    'updated_at': now,
  });
  final lotId = await db.insert('inventory_lots', {
    'global_id': 'legacy-lot',
    'product_id': productId,
    'branch_id': branchId,
    'entry_date': now,
    'initial_quantity': 5,
    'available_quantity': 4,
    'unit_cost_cents': 40,
    'created_at': now,
  });
  final sessionId = await db.insert('cash_sessions', {
    'global_id': 'legacy-session',
    'branch_id': branchId,
    'device_id': deviceId,
    'user_id': userId,
    'opened_at': now,
    'opening_balance_cents': 0,
    'status': 'Open',
    'updated_at': now,
  });
  final saleId = await db.insert('sales', {
    'global_id': '11111111-1111-1111-1111-111111111111',
    'idempotency_key': '22222222-2222-2222-2222-222222222222',
    'folio': 'V1',
    'sale_datetime': now,
    'user_id': userId,
    'device_id': deviceId,
    'branch_id': branchId,
    'subtotal_cents': 100,
    'total_cents': 100,
    'fifo_cost_cents': 40,
    'gross_profit_cents': 60,
    'payment_method': 'Cash',
    'received_cents': 120,
    'change_cents': 20,
    'created_at': now,
    'updated_at': now,
  });
  final detailId = await db.insert('sale_details', {
    'global_id': 'legacy-detail',
    'sale_id': saleId,
    'product_id': productId,
    'quantity': 1,
    'unit_price_cents': 100,
    'total_cents': 100,
    'fifo_cost_cents': 40,
  });
  await db.insert('sale_detail_lots', {
    'global_id': 'legacy-allocation',
    'sale_detail_id': detailId,
    'inventory_lot_id': lotId,
    'quantity': 1,
    'unit_cost_cents': 40,
    'total_cost_cents': 40,
  });
  await db.insert('cash_movements', {
    'global_id': 'legacy-cash',
    'cash_session_id': sessionId,
    'movement_date': now,
    'type': 'Sale',
    'amount_cents': 100,
    'reference_global_id': '11111111-1111-1111-1111-111111111111',
    'user_id': userId,
  });
  await db.insert('sync_queue', {
    'global_id': 'legacy-sync',
    'entity_type': 'Sale',
    'entity_global_id': '11111111-1111-1111-1111-111111111111',
    'operation': 'Create',
    'payload_json': '{}',
    'created_at': now,
  });
  return (saleId: saleId, productId: productId);
}

Future<void> _assertMigrated(
  Database db,
  ({int saleId, int productId}) ids,
) async {
  final payment = (await db.query('sale_payments')).single;
  expect(payment['sale_id'], ids.saleId);
  expect(payment['global_id'], '11111111-1111-1111-1111-111111111111');
  expect(payment['method'], 'Cash');
  expect(payment['amount_cents'], 100);
  expect((await db.query('sales')).single['total_cents'], 100);
  expect((await db.query('inventory_lots')).single['available_quantity'], 4);
  expect(await _count(db, 'cash_movements'), 1);
  expect(await _count(db, 'sync_queue'), 1);
}

Future<int> _count(Database db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS count FROM $table')).single['count']
        as int;
