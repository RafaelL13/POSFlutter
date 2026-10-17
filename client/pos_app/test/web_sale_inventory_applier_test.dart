import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_app/sync/web_sale_inventory_applier.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  const business = '11111111-1111-4111-8111-111111111111';
  const branch = '22222222-2222-4222-8222-222222222222';
  const sale = '33333333-3333-4333-8333-333333333333';
  const product = '44444444-4444-4444-8444-444444444444';
  const lot = '55555555-5555-4555-8555-555555555555';
  const date = '2026-10-17T12:00:00Z';
  final payload = <String, Object?>{
    'contractVersion': 1,
    'globalId': sale,
    'businessGlobalId': business,
    'branchGlobalId': branch,
    'date': date,
    'lines': [
      {
        'productGlobalId': product,
        'quantity': 2,
        'lots': [{'lotGlobalId': lot, 'quantity': 2}]
      }
    ],
  };
  late Database db;
  setUp(() async {
    db = await factory.openDatabase(inMemoryDatabasePath);
    for (final statement in [
      'CREATE TABLE businesses(id INTEGER PRIMARY KEY,global_id TEXT NOT NULL)',
      'CREATE TABLE products(id INTEGER PRIMARY KEY,global_id TEXT NOT NULL,business_id INTEGER NOT NULL,active INTEGER NOT NULL)',
      'CREATE TABLE inventory_lots(id INTEGER PRIMARY KEY,global_id TEXT NOT NULL,product_id INTEGER NOT NULL,branch_id INTEGER NOT NULL,available_quantity INTEGER NOT NULL,active INTEGER NOT NULL)',
      'CREATE TABLE inventory_movements(id INTEGER PRIMARY KEY,global_id TEXT NOT NULL,product_id INTEGER NOT NULL,branch_id INTEGER NOT NULL,movement_date TEXT NOT NULL,type TEXT NOT NULL,quantity_delta INTEGER NOT NULL,previous_stock INTEGER NOT NULL,new_stock INTEGER NOT NULL,reference_global_id TEXT NOT NULL,user_id INTEGER NOT NULL,device_id INTEGER NOT NULL,notes TEXT)',
      'CREATE TABLE sync_queue(id INTEGER PRIMARY KEY,entity_type TEXT NOT NULL,status TEXT NOT NULL)',
    ]) {
      await db.execute(statement);
    }
    await db.insert('businesses', {'id': 1, 'global_id': business});
    await db.insert('products', {'id': 11, 'global_id': product, 'business_id': 1, 'active': 1});
    await db.insert('inventory_lots', {'id': 20, 'global_id': lot, 'product_id': 11, 'branch_id': 2, 'available_quantity': 5, 'active': 1});
  });
  tearDown(() async => db.close());

  Future<void> apply([Map<String, Object?>? event, String globalId = sale]) =>
      db.transaction((tx) => WebSaleInventoryApplier.apply(
        tx,
        payload: event ?? payload,
        eventGlobalId: globalId,
        businessGlobalId: business,
        branchGlobalId: branch,
        branchId: 2,
        userId: 3,
        deviceId: 4,
        changedAt: date,
      ));

  Future<int> stock() async =>
      (await db.query('inventory_lots', columns: ['available_quantity'])).single['available_quantity'] as int;
  Future<int> movements() async =>
      (await db.rawQuery('SELECT COUNT(*) n FROM inventory_movements')).single['n'] as int;

  test('applies exactly once and records movement', () async {
    await apply();
    expect(await stock(), 3);
    expect(await movements(), 1);
    await apply();
    expect(await stock(), 3);
    expect(await movements(), 1);
  });

  test('rejects insufficient stock with atomic rollback', () async {
    await db.update('inventory_lots', {'available_quantity': 1});
    await expectLater(apply(), throwsStateError);
    expect(await stock(), 1);
    expect(await movements(), 0);
  });

  test('blocks offline sale queue without changing stock', () async {
    await db.insert('sync_queue', {'id': 1, 'entity_type': 'Sale', 'status': 'Pending'});
    await expectLater(apply(), throwsStateError);
    expect(await stock(), 5);
    expect(await movements(), 0);
  });

  test('rejects event ID mismatch and other tenant', () async {
    await expectLater(apply(payload, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), throwsStateError);
    await expectLater(apply({...payload, 'businessGlobalId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}), throwsStateError);
    expect(await stock(), 5);
    expect(await movements(), 0);
  });

  test('retries after a failed transaction', () async {
    await db.update('inventory_lots', {'available_quantity': 0});
    await expectLater(apply(), throwsStateError);
    await db.update('inventory_lots', {'available_quantity': 4});
    await apply();
    expect(await stock(), 2);
    expect(await movements(), 1);
  });
}
