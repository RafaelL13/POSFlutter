import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:pos_app/database/schema_v4.dart';
import 'package:pos_app/database/schema_v5.dart';
import 'package:pos_app/database/schema_v6.dart';
import 'package:pos_app/database/schema_v7.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('fresh V8 creates initial inventory schema and constraints', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final db = await database.open();

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(AppDatabase.schemaVersion, 8);

    await _expectTable(db, 'initial_inventory_imports');
    await _expectTable(db, 'initial_inventory_lines');

    final importIndexes = await db.rawQuery(
      "PRAGMA index_list('initial_inventory_imports')",
    );
    final lineIndexes = await db.rawQuery(
      "PRAGMA index_list('initial_inventory_lines')",
    );

    expect(importIndexes, isNotEmpty);
    expect(lineIndexes, isNotEmpty);

    final now = DateTime.utc(2026, 9, 24).toIso8601String();

    final businessId = await db.insert('businesses', {
      'global_id': 'business-v8',
      'name': 'Business V8',
      'created_at': now,
      'updated_at': now,
    });

    final branchId = await db.insert('branches', {
      'global_id': 'branch-v8',
      'business_id': businessId,
      'name': 'Main',
      'created_at': now,
      'updated_at': now,
    });

    final deviceId = await db.insert('devices', {
      'global_id': 'device-v8',
      'branch_id': branchId,
      'name': 'Tablet',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });

    final userId = await db.insert('users', {
      'global_id': 'user-v8',
      'business_id': businessId,
      'name': 'Admin',
      'username': 'admin-v8',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': 'Administrator',
      'created_at': now,
      'updated_at': now,
    });

    final categoryId = await db.insert('categories', {
      'global_id': 'category-v8',
      'business_id': businessId,
      'name': 'General',
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });

    final productId = await db.insert('products', {
      'global_id': 'product-v8',
      'business_id': businessId,
      'category_id': categoryId,
      'code': 'P001',
      'name': 'Producto',
      'presentation': 'Piece',
      'sale_price_cents': 14000,
      'minimum_stock': 0,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });

    final lotId = await db.insert('inventory_lots', {
      'global_id': 'lot-v8',
      'product_id': productId,
      'branch_id': branchId,
      'entry_date': now,
      'initial_quantity': 10,
      'available_quantity': 10,
      'unit_cost_cents': 10000,
      'active': 1,
      'created_at': now,
    });

    final importId = await db.insert('initial_inventory_imports', {
      'global_id': 'import-v8',
      'business_id': businessId,
      'branch_id': branchId,
      'device_id': deviceId,
      'user_id': userId,
      'source_fingerprint': 'fingerprint-v8',
      'source_name': 'productos.csv',
      'valid_rows': 1,
      'total_units': 10,
      'created_at': now,
    });

    await db.insert('initial_inventory_lines', {
      'global_id': 'line-v8',
      'import_id': importId,
      'product_id': productId,
      'inventory_lot_id': lotId,
      'quantity': 10,
      'unit_cost_cents': 10000,
    });

    await expectLater(
      db.insert('initial_inventory_imports', {
        'global_id': 'import-v8-duplicate-fingerprint',
        'business_id': businessId,
        'branch_id': branchId,
        'device_id': deviceId,
        'user_id': userId,
        'source_fingerprint': 'fingerprint-v8',
        'source_name': 'duplicate.csv',
        'valid_rows': 1,
        'total_units': 10,
        'created_at': now,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await expectLater(
      db.insert('initial_inventory_lines', {
        'global_id': 'line-invalid-zero',
        'import_id': importId,
        'product_id': productId,
        'inventory_lot_id': lotId,
        'quantity': 0,
        'unit_cost_cents': 10000,
      }),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
  });

  test(
    'upgrade V7 to V8 preserves existing data and creates V8 schema',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pos_v8_migration_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final path = '${directory.path}${Platform.pathSeparator}v7.db';

      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys=ON');
          },
          onCreate: (db, _) async {
            for (final statement in [
              ...schemaV1Statements,
              ...schemaV2Statements,
              ...schemaV3Statements,
              ...schemaV4Statements,
              ...schemaV5Statements,
              ...schemaV6Statements,
              ...schemaV7Statements,
            ]) {
              await db.execute(statement);
            }
          },
        ),
      );

      final now = DateTime.utc(2026, 9, 24).toIso8601String();

      final businessId = await legacy.insert('businesses', {
        'global_id': 'preserved-business-v7',
        'name': 'Preserved V7',
        'created_at': now,
        'updated_at': now,
      });

      await legacy.insert('branches', {
        'global_id': 'preserved-branch-v7',
        'business_id': businessId,
        'name': 'Legacy Branch',
        'created_at': now,
        'updated_at': now,
      });

      final categoryId = await legacy.insert('categories', {
        'global_id': 'preserved-category-v7',
        'business_id': businessId,
        'name': 'Legacy Category',
        'active': 1,
        'created_at': now,
        'updated_at': now,
      });

      await legacy.insert('products', {
        'global_id': 'preserved-product-v7',
        'business_id': businessId,
        'category_id': categoryId,
        'code': 'LEGACY001',
        'name': 'Legacy Product',
        'presentation': 'Piece',
        'sale_price_cents': 12345,
        'minimum_stock': 0,
        'active': 1,
        'created_at': now,
        'updated_at': now,
      });

      await legacy.insert('sync_queue', {
        'global_id': 'preserved-queue-v7',
        'entity_type': 'Product',
        'entity_global_id': 'preserved-product-v7',
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': '{}',
        'created_at': now,
      });

      await legacy.close();

      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(database.close);

      final upgraded = await database.open();

      expect(await upgraded.getVersion(), 8);

      expect(
        await upgraded.query(
          'businesses',
          columns: ['name'],
          where: 'global_id=?',
          whereArgs: ['preserved-business-v7'],
        ),
        [containsPair('name', 'Preserved V7')],
      );

      expect(
        await upgraded.query(
          'products',
          columns: ['code', 'name', 'sale_price_cents'],
          where: 'global_id=?',
          whereArgs: ['preserved-product-v7'],
        ),
        [
          allOf(
            containsPair('code', 'LEGACY001'),
            containsPair('name', 'Legacy Product'),
            containsPair('sale_price_cents', 12345),
          ),
        ],
      );

      expect(
        await upgraded.query(
          'sync_queue',
          where: 'global_id=?',
          whereArgs: ['preserved-queue-v7'],
        ),
        hasLength(1),
      );

      await _expectTable(upgraded, 'initial_inventory_imports');
      await _expectTable(upgraded, 'initial_inventory_lines');

      expect(
        (await upgraded.rawQuery('PRAGMA integrity_check'))
            .single
            .values
            .single,
        'ok',
      );
    },
  );
}

Future<void> _expectTable(Database db, String name) async {
  expect(
    await db.query(
      'sqlite_master',
      where: "type='table' AND name=?",
      whereArgs: [name],
    ),
    hasLength(1),
  );
}
