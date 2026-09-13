import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'producto guarda category_id y SyncQueue envía categoryGlobalId',
    () async {
      final database = await _database();
      addTearDown(database.close);

      final catalog = CatalogRepository(database);

      final categoryGlobalId = await catalog.addCategory('Bebidas');

      final db = await database.open();

      final category = (await db.query(
        'categories',
        where: 'global_id = ?',
        whereArgs: [categoryGlobalId],
      )).single;

      final categoryId = category['id']! as int;

      final productGlobalId = await catalog.addProduct(
        code: 'REF-001',
        name: 'Refresco 600 ml',
        categoryId: categoryId,
        salePriceCents: 1850,
        minimumStock: 5,
      );

      final product = (await db.query(
        'products',
        where: 'global_id = ?',
        whereArgs: [productGlobalId],
      )).single;

      expect(product['category_id'], categoryId);
      expect(product['code'], 'REF-001');
      expect(product['name'], 'Refresco 600 ml');
      expect(product['sale_price_cents'], 1850);
      expect(product['minimum_stock'], 5);

      final queue = (await db.query(
        'sync_queue',
        where: 'entity_type = ? AND entity_global_id = ?',
        whereArgs: ['Product', productGlobalId],
      )).single;

      final payload =
          jsonDecode(queue['payload_json']! as String) as Map<String, dynamic>;

      expect(payload['globalId'], productGlobalId);
      expect(payload['categoryGlobalId'], categoryGlobalId);
      expect(payload['code'], 'REF-001');
      expect(payload['name'], 'Refresco 600 ml');
      expect(payload['salePriceCents'], 1850);
      expect(payload['minimumStock'], 5);
      expect(payload['active'], true);
    },
  );

  test('producto rechaza categoría inactiva', () async {
    final database = await _database();
    addTearDown(database.close);

    final catalog = CatalogRepository(database);

    final categoryGlobalId = await catalog.addCategory('Temporal');

    final db = await database.open();

    final category = (await db.query(
      'categories',
      where: 'global_id = ?',
      whereArgs: [categoryGlobalId],
    )).single;

    final categoryId = category['id']! as int;

    await db.update(
      'categories',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [categoryId],
    );

    await expectLater(
      catalog.addProduct(
        code: 'P-INVALID',
        name: 'No debe guardarse',
        categoryId: categoryId,
        salePriceCents: 100,
      ),
      throwsA(isA<StateError>()),
    );

    final products = await db.query(
      'products',
      where: 'code = ?',
      whereArgs: ['P-INVALID'],
    );

    expect(products, isEmpty);
  });
}

Future<AppDatabase> _database() async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );

  final db = await database.open();
  final now = DateTime.utc(2026, 9, 12).toIso8601String();

  final businessId = await db.insert('businesses', {
    'global_id': 'business-product-category',
    'name': 'Test Business',
    'created_at': now,
    'updated_at': now,
  });

  final branchId = await db.insert('branches', {
    'global_id': 'branch-product-category',
    'business_id': businessId,
    'name': 'Matriz',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('devices', {
    'global_id': 'device-product-category',
    'branch_id': branchId,
    'name': 'Tablet',
    'mode': 'PointOfSale',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('users', {
    'global_id': 'user-product-category',
    'business_id': businessId,
    'name': 'Administrador',
    'username': 'admin',
    'password_hash': 'hash',
    'password_salt': 'salt',
    'role': 'Administrator',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('app_settings', {
    'key': 'local_device_global_id',
    'value': 'device-product-category',
    'updated_at': now,
  });

  await db.insert('app_settings', {
    'key': 'active_user_global_id',
    'value': 'user-product-category',
    'updated_at': now,
  });

  return database;
}
