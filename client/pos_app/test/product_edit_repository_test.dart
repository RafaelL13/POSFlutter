import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'editar producto actualiza catálogo y genera SyncQueue Update',
    () async {
      final database = await _database();
      addTearDown(database.close);

      final catalog = CatalogRepository(database);

      final bebidasGlobalId = await catalog.addCategory('Bebidas');

      final congeladosGlobalId = await catalog.addCategory('Congelados');

      final db = await database.open();

      final bebidas = (await db.query(
        'categories',
        where: 'global_id = ?',
        whereArgs: [bebidasGlobalId],
      )).single;

      final congelados = (await db.query(
        'categories',
        where: 'global_id = ?',
        whereArgs: [congeladosGlobalId],
      )).single;

      final productGlobalId = await catalog.addProduct(
        code: 'P-001',
        name: 'Producto inicial',
        categoryId: bebidas['id']! as int,
        salePriceCents: 1000,
        minimumStock: 2,
      );

      final product = (await db.query(
        'products',
        where: 'global_id = ?',
        whereArgs: [productGlobalId],
      )).single;

      final productId = product['id']! as int;

      await catalog.updateProduct(
        productId: productId,
        code: 'P-EDIT',
        name: 'Producto editado',
        barcode: '7501234567890',
        categoryId: congelados['id']! as int,
        salePriceCents: 1250,
        minimumStock: 7,
        active: false,
      );

      final updated = (await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
      )).single;

      expect(updated['code'], 'P-EDIT');
      expect(updated['name'], 'Producto editado');
      expect(updated['barcode'], '7501234567890');
      expect(updated['category_id'], congelados['id']);
      expect(updated['sale_price_cents'], 1250);
      expect(updated['minimum_stock'], 7);
      expect(updated['active'], 0);

      final queue = await db.query(
        'sync_queue',
        where: 'entity_type = ? AND entity_global_id = ? AND operation = ?',
        whereArgs: ['Product', productGlobalId, 'Update'],
        orderBy: 'id DESC',
        limit: 1,
      );

      expect(queue, hasLength(1));

      final payload = jsonDecode(
        queue.single['payload_json']! as String,
      ) as Map<String, dynamic>;

      expect(payload['globalId'], productGlobalId);
      expect(payload['categoryGlobalId'], congeladosGlobalId);
      expect(payload['code'], 'P-EDIT');
      expect(payload['barcode'], '7501234567890');
      expect(payload['name'], 'Producto editado');
      expect(payload['salePriceCents'], 1250);
      expect(payload['minimumStock'], 7);
      expect(payload['active'], false);
    },
  );

  test('editar producto no altera inventario ni lotes FIFO', () async {
    final database = await _database();
    addTearDown(database.close);

    final catalog = CatalogRepository(database);

    final categoryGlobalId = await catalog.addCategory('General');

    final db = await database.open();

    final category = (await db.query(
      'categories',
      where: 'global_id = ?',
      whereArgs: [categoryGlobalId],
    )).single;

    final productGlobalId = await catalog.addProduct(
      code: 'FIFO-1',
      name: 'Producto FIFO',
      categoryId: category['id']! as int,
      salePriceCents: 500,
    );

    final product = (await db.query(
      'products',
      where: 'global_id = ?',
      whereArgs: [productGlobalId],
    )).single;

    final productId = product['id']! as int;

    final lotCountBefore = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM inventory_lots WHERE product_id = ?',
        [productId],
      ),
    );

    final movementCountBefore = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM inventory_movements WHERE product_id = ?',
        [productId],
      ),
    );

    await catalog.updateProduct(
      productId: productId,
      code: 'FIFO-EDIT',
      name: 'Producto FIFO editado',
      categoryId: category['id']! as int,
      salePriceCents: 500,
      minimumStock: 4,
      active: true,
    );

    final lotCountAfter = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM inventory_lots WHERE product_id = ?',
        [productId],
      ),
    );

    final movementCountAfter = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM inventory_movements WHERE product_id = ?',
        [productId],
      ),
    );

    expect(lotCountAfter, lotCountBefore);
    expect(movementCountAfter, movementCountBefore);
  });
}

Future<AppDatabase> _database() async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );

  final db = await database.open();
  final now = DateTime.utc(2026, 9, 13).toIso8601String();

  final businessId = await db.insert('businesses', {
    'global_id': 'business-edit-product',
    'name': 'Test Business',
    'created_at': now,
    'updated_at': now,
  });

  final branchId = await db.insert('branches', {
    'global_id': 'branch-edit-product',
    'business_id': businessId,
    'name': 'Matriz',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('devices', {
    'global_id': 'device-edit-product',
    'branch_id': branchId,
    'name': 'Tablet',
    'mode': 'PointOfSale',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('users', {
    'global_id': 'user-edit-product',
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
    'value': 'device-edit-product',
    'updated_at': now,
  });

  await db.insert('app_settings', {
    'key': 'active_user_global_id',
    'value': 'user-edit-product',
    'updated_at': now,
  });

  return database;
}

int _firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) {
    return 0;
  }

  final value = rows.first.values.first;

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  throw StateError('El resultado SQL no contiene un valor entero.');
}
