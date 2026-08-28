import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/backup/data/local_backup_provider.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:pos_app/features/expenses/data/expense_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/features/purchases/data/purchase_repository.dart';
import 'package:pos_app/features/sales/data/sales_repository.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _mutationTables = <String>[
  'sales',
  'sale_details',
  'sale_detail_lots',
  'purchases',
  'purchase_details',
  'expenses',
  'products',
  'categories',
  'suppliers',
  'inventory_lots',
  'inventory_movements',
  'inventory_adjustments',
  'cash_sessions',
  'cash_movements',
  'audit_logs',
  'sync_queue',
];

void main() {
  sqfliteFfiInit();

  test('Seller denied writes leave SQLite and SyncQueue unchanged', () async {
    final database = await _database(role: 'Seller');
    addTearDown(database.close);

    await _expectDenied(
      PurchaseRepository(database).create(
        supplierId: 999,
        supplierGlobalId: 'supplier-denied',
        lines: const [PurchaseLineInput(999, 'product-denied', 1, 100)],
      ),
    );
    await _expectDenied(
      ExpenseRepository(database)
          .create(concept: 'Denied', amountCents: 100, paymentMethod: 'Card'),
    );
    await _expectDenied(
      CatalogRepository(database)
          .addProduct(code: 'P1', name: 'Denied', salePriceCents: 100),
    );
    await _expectDenied(CatalogRepository(database).addCategory('Denied'));
    await _expectDenied(CatalogRepository(database).addSupplier('Denied'));
    await _expectDenied(
      InventoryRepository(database)
          .adjust(productId: 999, delta: 1, reason: 'Denied'),
    );
    await _expectDenied(LocalBackupProvider(database).createBackup());

    expect(await _counts(database), everyElement(0));
  });

  test('Supervisor catalog writes leave SQLite unchanged', () async {
    final database = await _database(role: 'Supervisor');
    addTearDown(database.close);

    await _expectDenied(
      CatalogRepository(database)
          .addProduct(code: 'P1', name: 'Denied', salePriceCents: 100),
    );
    await _expectDenied(CatalogRepository(database).addCategory('Denied'));
    await _expectDenied(CatalogRepository(database).addSupplier('Denied'));

    expect(await _counts(database), everyElement(0));
  });

  test('Manager allowed operations still commit atomically', () async {
    final database = await _database(role: 'Manager');
    addTearDown(database.close);
    final catalog = CatalogRepository(database);
    final supplierGlobalId = await catalog.addSupplier('Supplier');
    final productGlobalId = await catalog.addProduct(
      code: 'P1',
      name: 'Product',
      salePriceCents: 200,
    );
    final db = await database.open();
    final supplier = (await db.query(
      'suppliers',
      where: 'global_id = ?',
      whereArgs: [supplierGlobalId],
    )).single;
    final product = (await db.query(
      'products',
      where: 'global_id = ?',
      whereArgs: [productGlobalId],
    )).single;

    await PurchaseRepository(database).create(
      supplierId: supplier['id']! as int,
      supplierGlobalId: supplierGlobalId,
      lines: [
        PurchaseLineInput(product['id']! as int, productGlobalId, 2, 100),
      ],
    );
    await ExpenseRepository(
      database,
    ).create(concept: 'Card expense', amountCents: 50, paymentMethod: 'Card');

    expect(await _tableCount(db, 'suppliers'), 1);
    expect(await _tableCount(db, 'products'), 1);
    expect(await _tableCount(db, 'purchases'), 1);
    expect(await _tableCount(db, 'inventory_lots'), 1);
    expect(await _tableCount(db, 'inventory_movements'), 1);
    expect(await _tableCount(db, 'expenses'), 1);
    expect(await _tableCount(db, 'sync_queue'), 4);
  });

  test('AdminReadOnly blocks every operational repository write', () async {
    final database = await _database(
      role: 'Administrator',
      mode: 'AdminReadOnly',
    );
    addTearDown(database.close);

    await _expectDenied(
      PosRepository(database).completeSale([
        CartLine(
          productId: 999,
          productGlobalId: 'product-denied',
          name: 'Denied',
          quantity: 1,
          unitPriceCents: 100,
        ),
      ], paymentMethod: 'Card'),
    );
    await _expectDenied(SalesRepository(database).cancel('sale-denied', 'x'));
    await _expectDenied(
      PurchaseRepository(database).create(
        supplierId: 999,
        supplierGlobalId: 'supplier-denied',
        lines: const [PurchaseLineInput(999, 'product-denied', 1, 100)],
      ),
    );
    await _expectDenied(
      ExpenseRepository(database)
          .create(concept: 'Denied', amountCents: 100, paymentMethod: 'Card'),
    );
    await _expectDenied(
      CatalogRepository(database)
          .addProduct(code: 'P1', name: 'Denied', salePriceCents: 100),
    );
    await _expectDenied(CatalogRepository(database).addCategory('Denied'));
    await _expectDenied(CatalogRepository(database).addSupplier('Denied'));
    await _expectDenied(
      InventoryRepository(database)
          .adjust(productId: 999, delta: 1, reason: 'Denied'),
    );
    await _expectDenied(CashRepository(database).open(0));
    await _expectDenied(
      LocalBackupProvider(database).restoreBackup('backup-denied.db'),
    );
    await _expectDenied(SyncRepository(database: database).nextBatch());

    expect(await _counts(database), everyElement(0));
  });

  test('AdminReadOnly still permits pull without operational push', () async {
    final database = await _database(
      role: 'Administrator',
      mode: 'AdminReadOnly',
    );
    addTearDown(database.close);
    final repository = SyncRepository(database: database);

    await repository.applyPullBatch(
      SyncPullBatch(
        nextCursor: 0,
        hasMore: false,
        changes: const [],
        serverTime: DateTime.utc(2026, 8, 27),
      ),
    );

    expect(await repository.currentPullCursor(), 0);
    expect(await _counts(database), everyElement(0));
  });

  test('special authorization denial occurs before sale mutation', () async {
    final database = await _database(role: 'Seller');
    addTearDown(database.close);

    await expectLater(
      SalesRepository(database).cancel('sale-denied', 'Denied'),
      throwsA(isA<AdditionalAuthorizationRequiredException>()),
    );

    expect(await _counts(database), everyElement(0));
  });

  test('cash difference authorization is checked before closing', () async {
    final database = await _database(role: 'Seller');
    addTearDown(database.close);
    final repository = CashRepository(database);
    await repository.open(0);
    final db = await database.open();
    final queueBefore = await _tableCount(db, 'sync_queue');

    await expectLater(
      repository.close(1),
      throwsA(isA<AdditionalAuthorizationRequiredException>()),
    );

    final sessions = await db.query('cash_sessions', columns: ['status']);
    expect(sessions.single['status'], 'Open');
    expect(await _tableCount(db, 'cash_movements'), 0);
    expect(await _tableCount(db, 'sync_queue'), queueBefore);
  });

  test('AdminReadOnly cannot mutate interrupted push state', () async {
    final database = await _database(
      role: 'Administrator',
      mode: 'AdminReadOnly',
    );
    addTearDown(database.close);
    final db = await database.open();
    final now = DateTime.utc(2026, 8, 27).toIso8601String();
    await db.insert('sync_queue', {
      'global_id': 'sync-1',
      'entity_type': 'Product',
      'entity_global_id': 'product-1',
      'operation': 'Create',
      'payload_version': 1,
      'payload_json': '{}',
      'created_at': now,
      'status': 'Syncing',
    });

    await _expectDenied(
      SyncRepository(database: database).recoverInterrupted(),
    );

    final rows = await db.query('sync_queue', columns: ['status']);
    expect(rows.single['status'], 'Syncing');
  });
}

Future<AppDatabase> _database({
  required String role,
  String mode = 'PointOfSale',
}) async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final db = await database.open();
  final now = DateTime.utc(2026, 8, 27).toIso8601String();
  final businessId = await db.insert('businesses', {
    'global_id': 'business-1',
    'name': 'Test',
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
    'name': 'Tablet',
    'mode': mode,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('users', {
    'global_id': 'user-1',
    'business_id': businessId,
    'name': 'User',
    'username': 'user',
    'password_hash': 'hash',
    'password_salt': 'salt',
    'role': role,
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
  return database;
}

Future<void> _expectDenied(Future<Object?> operation) async {
  await expectLater(operation, throwsA(isA<AuthorizationDeniedException>()));
}

Future<List<int>> _counts(AppDatabase database) async {
  final db = await database.open();
  return Future.wait(_mutationTables.map((table) => _tableCount(db, table)));
}

Future<int> _tableCount(Database db, String table) async {
  final result = await db.rawQuery('SELECT COUNT(*) count FROM $table');
  return result.first['count']! as int;
}
