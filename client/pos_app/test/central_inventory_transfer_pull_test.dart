import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('central transfer pull creates exact lot and movement once', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final change = fixture.change(cursor: 1);

    await fixture.repository.applyPullBatch(fixture.batch(change));
    await fixture.repository.applyPullBatch(fixture.batch(change));

    final lots = await fixture.db.query(
      'inventory_lots',
      where: 'global_id=?',
      whereArgs: ['central-lot-1'],
    );
    final movements = await fixture.db.query(
      'inventory_movements',
      where: 'type=? AND reference_global_id=?',
      whereArgs: ['CentralTransferIn', 'transfer-1'],
    );
    expect(lots, hasLength(1));
    expect(lots.single['initial_quantity'], 7);
    expect(lots.single['available_quantity'], 7);
    expect(lots.single['unit_cost_cents'], 1234);
    expect(movements, hasLength(1));
    expect(movements.single['previous_stock'], 0);
    expect(movements.single['new_stock'], 7);
    expect(await fixture.repository.currentPullCursor(), 1);
  });

  test(
    'central transfer for another branch is consumed without stock',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final change = fixture.change(cursor: 1, branchGlobalId: 'branch-2');

      await fixture.repository.applyPullBatch(fixture.batch(change));

      expect(await fixture.count('inventory_lots'), 0);
      expect(await fixture.count('inventory_movements'), 0);
      expect(await fixture.repository.currentPullCursor(), 1);
    },
  );


  test('fractional central transfer quantity is rejected without mutation', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final change = fixture.change(cursor: 1, quantity: 7.5);

    await expectLater(
      fixture.repository.applyPullBatch(fixture.batch(change)),
      throwsStateError,
    );

    expect(await fixture.count('inventory_lots'), 0);
    expect(await fixture.count('inventory_movements'), 0);
    expect(await fixture.repository.currentPullCursor(), 0);
  });

  test('invalid central transfer rolls back stock and cursor', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final change = fixture.change(cursor: 1, productGlobalId: 'missing');

    await expectLater(
      fixture.repository.applyPullBatch(fixture.batch(change)),
      throwsStateError,
    );

    expect(await fixture.count('inventory_lots'), 0);
    expect(await fixture.count('inventory_movements'), 0);
    expect(await fixture.repository.currentPullCursor(), 0);
  });
}

final class _Fixture {
  _Fixture(this.database, this.db, this.repository);

  final AppDatabase database;
  final Database db;
  final SyncRepository repository;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.open();
    final now = DateTime.utc(2026, 9, 25).toIso8601String();
    final businessId = await db.insert('businesses', {
      'global_id': 'business-1',
      'name': 'Business',
      'created_at': now,
      'updated_at': now,
    });
    final branchId = await db.insert('branches', {
      'global_id': 'branch-1',
      'business_id': businessId,
      'name': 'Main',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('devices', {
      'global_id': 'device-1',
      'branch_id': branchId,
      'name': 'POS',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'global_id': 'user-1',
      'business_id': businessId,
      'name': 'Manager',
      'username': 'manager',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': 'Manager',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('products', {
      'global_id': 'product-1',
      'business_id': businessId,
      'code': 'P1',
      'name': 'Product',
      'presentation': 'Piece',
      'sale_price_cents': 2000,
      'minimum_stock': 0,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'local_device_global_id',
      'value': 'device-1',
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'active_user_global_id',
      'value': 'user-1',
      'updated_at': now,
    });
    return _Fixture(database, db, SyncRepository(database: database));
  }

  SyncPullChange change({
    required int cursor,
    String branchGlobalId = 'branch-1',
    String productGlobalId = 'product-1',
    num quantity = 7,
  }) => SyncPullChange(
    cursor: cursor,
    entityType: 'CentralTransferIn',
    entityGlobalId: 'transfer-1',
    operation: 'Create',
    version: 1,
    changedAt: DateTime.utc(2026, 9, 25, 2),
    payload: {
      'globalId': 'transfer-1',
      'businessGlobalId': 'business-1',
      'branchGlobalId': branchGlobalId,
      'date': '2026-09-25T02:00:00Z',
      'serverVersion': 1,
      'lines': [
        {
          'productGlobalId': productGlobalId,
          'lotGlobalId': 'central-lot-1',
          'quantity': quantity,
          'unitCostCents': 1234,
        },
      ],
    },
  );

  SyncPullBatch batch(SyncPullChange change) => SyncPullBatch(
    nextCursor: change.cursor,
    hasMore: false,
    changes: [change],
    serverTime: DateTime.utc(2026, 9, 25, 2, 1),
  );

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) count FROM $table');
    return rows.single['count']! as int;
  }

  Future<void> dispose() => database.close();
}
