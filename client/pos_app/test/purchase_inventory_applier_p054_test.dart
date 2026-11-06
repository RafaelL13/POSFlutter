import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:pos_app/database/schema_v4.dart';
import 'package:pos_app/database/schema_v5.dart';
import 'package:pos_app/database/schema_v6.dart';
import 'package:pos_app/database/schema_v7.dart';
import 'package:pos_app/database/schema_v8.dart';
import 'package:pos_app/sync/purchase_inventory_applier.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const business = '11111111-1111-4111-8111-111111111111';
const branch = '22222222-2222-4222-8222-222222222222';
const device = '33333333-3333-4333-8333-333333333333';
const user = '44444444-4444-4444-8444-444444444444';
const supplier = '55555555-5555-4555-8555-555555555555';
const product = '66666666-6666-4666-8666-666666666666';
const purchase = '77777777-7777-4777-8777-777777777777';
const detail = '88888888-8888-4888-8888-888888888888';
const lot = '99999999-9999-4999-8999-999999999999';
const when = '2026-10-18T10:00:00.000Z';

const context = LocalAppContext(
  businessId: 1, businessGlobalId: business,
  branchId: 1, branchGlobalId: branch,
  deviceId: 1, deviceGlobalId: device,
  deviceMode: 'PointOfSale', userId: 1, userGlobalId: user,
  role: 'Administrator',
);

SyncPullChange change({int quantity = 3, String branchId = branch}) {
  return SyncPullChange(
    cursor: 100, entityType: 'Purchase', entityGlobalId: purchase,
    operation: 'Create', version: 1, changedAt: DateTime.parse(when),
    payload: <String, Object?>{
      'globalId': purchase, 'businessGlobalId': business,
      'branchGlobalId': branchId, 'deviceGlobalId': device,
      'userGlobalId': user, 'supplierGlobalId': supplier,
      'date': when, 'totalCents': quantity * 125,
      'lines': <Map<String, Object?>>[{
        'detailGlobalId': detail, 'productGlobalId': product,
        'quantity': quantity, 'unitCostCents': 125,
        'subtotalCents': quantity * 125, 'lotGlobalId': lot,
      }],
    },
  );
}

Future<void> seed(Database db) async {
  await db.insert('businesses', {
    'global_id': business, 'name': 'Prueba V39', 'active': 1,
    'created_at': when, 'updated_at': when,
  });
  await db.insert('branches', {
    'global_id': branch, 'business_id': 1, 'name': 'Sucursal laboratorio',
    'active': 1, 'created_at': when, 'updated_at': when,
  });
  await db.insert('devices', {
    'global_id': device, 'branch_id': 1, 'name': 'Tablet V39',
    'mode': 'PointOfSale', 'active': 1, 'created_at': when,
  });
  await db.insert('users', {
    'global_id': user, 'business_id': 1, 'name': 'Usuario V39',
    'username': 'test-v39', 'password_hash': 'fixture',
    'password_salt': 'fixture', 'role': 'Administrator',
    'active': 1, 'created_at': when, 'updated_at': when,
  });
  await db.insert('suppliers', {
    'global_id': supplier, 'business_id': 1,
    'name': 'Proveedor V39', 'active': 1,
    'created_at': when, 'updated_at': when,
  });
  await db.insert('products', {
    'global_id': product, 'business_id': 1, 'code': 'V39-TEST',
    'name': 'Producto V39', 'presentation': 'Piece',
    'sale_price_cents': 250, 'minimum_stock': 0,
    'active': 1, 'created_at': when, 'updated_at': when,
  });
}

Future<int> count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
  return rows.single['n']! as int;
}

void main() {
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (database, _) async {
        await database.execute('PRAGMA foreign_keys = ON');
        for (final statements in [
          schemaV1Statements,
          schemaV2Statements,
          schemaV3Statements,
          schemaV4Statements,
          schemaV5Statements,
          schemaV6Statements,
          schemaV7Statements,
          schemaV8Statements,
        ]) {
          for (final ddl in statements) {
            await database.execute(ddl);
          }
        }
      }),
    );
    await seed(db);
  });
  tearDown(() async => db.close());

  test('V39 compra remota crea una compra, detalle, lote y movimiento', () async {
    await db.transaction((tx) => PurchaseInventoryApplier.apply(tx, change(), context));
    expect(await count(db, 'purchases'), 1);
    expect(await count(db, 'purchase_details'), 1);
    expect(await count(db, 'inventory_lots'), 1);
    expect(await count(db, 'inventory_movements'), 1);
    final stock = await db.rawQuery(
      'SELECT initial_quantity, available_quantity, unit_cost_cents FROM inventory_lots'
    );
    expect(stock.single['initial_quantity'], 3);
    expect(stock.single['available_quantity'], 3);
    expect(stock.single['unit_cost_cents'], 125);
    final movement = await db.rawQuery(
      'SELECT quantity_delta, previous_stock, new_stock FROM inventory_movements'
    );
    expect(movement.single['quantity_delta'], 3);
    expect(movement.single['previous_stock'], 0);
    expect(movement.single['new_stock'], 3);
  });

  test('V39 replay identico no duplica compra, lote, movimiento ni existencias', () async {
    await db.transaction((tx) => PurchaseInventoryApplier.apply(tx, change(), context));
    await db.transaction((tx) => PurchaseInventoryApplier.apply(tx, change(), context));
    for (final table in ['purchases', 'purchase_details', 'inventory_lots', 'inventory_movements']) {
      expect(await count(db, table), 1, reason: table);
    }
    final result = await db.rawQuery('SELECT SUM(available_quantity) AS n FROM inventory_lots');
    expect(result.single['n'], 3);
  });

  test('V39 replay conflictivo falla y conserva el inventario original', () async {
    await db.transaction((tx) => PurchaseInventoryApplier.apply(tx, change(), context));
    await expectLater(
      db.transaction((tx) => PurchaseInventoryApplier.apply(tx, change(quantity: 4), context)),
      throwsStateError,
    );
    final result = await db.rawQuery('SELECT SUM(available_quantity) AS n FROM inventory_lots');
    expect(result.single['n'], 3);
    expect(await count(db, 'inventory_movements'), 1);
  });

  test('V39 otra sucursal no importa inventario local', () async {
    await db.transaction((tx) => PurchaseInventoryApplier.apply(
      tx, change(branchId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), context));
    expect(await count(db, 'purchases'), 0);
    expect(await count(db, 'inventory_lots'), 0);
  });
}