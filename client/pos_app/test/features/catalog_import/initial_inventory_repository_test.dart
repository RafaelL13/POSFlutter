import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';
import 'package:pos_app/features/catalog_import/data/initial_inventory_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('InitialInventoryRepository', () {
    test(
      'Manager creates catalog, FIFO lot, movement, audit and queue atomically',
      () async {
        final fixture = await _Fixture.create(role: 'Manager');
        addTearDown(fixture.dispose);

        final preview = _preview(
          fingerprint: 'fp-create',
          rows: const [
            CatalogImportRow(
              sku: 'P001',
              name: 'Producto Uno',
              category: 'General',
              supplier: 'Proveedor Uno',
              costCents: 10000,
              priceCents: 14000,
              quantity: 10,
            ),
          ],
        );

        final importGid = await InitialInventoryRepository(fixture.database)
            .import(
              preview: preview,
              policy: ExistingCatalogPolicy.skip,
              sourceName: 'productos.csv',
            );

        expect(await fixture.count('categories'), 1);
        expect(await fixture.count('suppliers'), 1);
        expect(await fixture.count('products'), 1);
        expect(await fixture.count('initial_inventory_imports'), 1);
        expect(await fixture.count('initial_inventory_lines'), 1);
        expect(await fixture.count('inventory_lots'), 1);
        expect(await fixture.count('inventory_movements'), 1);
        expect(await fixture.count('audit_logs'), 1);

        final product = (await fixture.db.query('products')).single;
        expect(product['code'], 'P001');
        expect(product['name'], 'Producto Uno');
        expect(product['sale_price_cents'], 14000);

        final header = (await fixture.db.query('initial_inventory_imports'))
            .single;
        expect(header['global_id'], importGid);
        expect(header['source_fingerprint'], 'fp-create');
        expect(header['source_name'], 'productos.csv');
        expect(header['valid_rows'], 1);
        expect(header['total_units'], 10);

        final lot = (await fixture.db.query('inventory_lots')).single;
        expect(lot['initial_quantity'], 10);
        expect(lot['available_quantity'], 10);
        expect(lot['unit_cost_cents'], 10000);
        expect(lot['branch_id'], fixture.branchId);

        final movement = (await fixture.db.query('inventory_movements')).single;
        expect(movement['type'], 'InitialInventory');
        expect(movement['quantity_delta'], 10);
        expect(movement['previous_stock'], 0);
        expect(movement['new_stock'], 10);
        expect(movement['reference_global_id'], importGid);

        final initialQueue = (await fixture.db.query(
          'sync_queue',
          where: "entity_type='InitialInventory'",
        )).single;

        final payload = jsonDecode(
          initialQueue['payload_json']! as String,
        ) as Map<String, dynamic>;

        expect(payload['globalId'], importGid);
        expect(payload['sourceFingerprint'], 'fp-create');

        final payloadLines = payload['lines']! as List<dynamic>;
        expect(payloadLines, hasLength(1));

        final payloadLine = payloadLines.single as Map<String, dynamic>;

        expect(payloadLine['quantity'], 10);
        expect(payloadLine['unitCostCents'], 10000);

        final localLine = (await fixture.db.query('initial_inventory_lines'))
            .single;

        expect(payloadLine['globalId'], localLine['global_id']);
        expect(payloadLine['lotGlobalId'], lot['global_id']);

        final queue = await fixture.db.query('sync_queue', orderBy: 'id');

        expect(queue.map((x) => x['entity_type']).toList(), [
          'Category',
          'Supplier',
          'Product',
          'InitialInventory',
        ]);
      },
    );

    test(
      'same fingerprint is idempotent and creates no duplicate stock',
      () async {
        final fixture = await _Fixture.create(role: 'Manager');
        addTearDown(fixture.dispose);

        final preview = _preview(
          fingerprint: 'fp-idempotent',
          rows: const [
            CatalogImportRow(
              sku: 'P001',
              name: 'Producto',
              category: 'General',
              supplier: 'Proveedor',
              costCents: 10000,
              priceCents: 14000,
              quantity: 10,
            ),
          ],
        );

        final repository = InitialInventoryRepository(fixture.database);

        final first = await repository.import(
          preview: preview,
          policy: ExistingCatalogPolicy.skip,
        );

        final queueAfterFirst = await fixture.count('sync_queue');

        final second = await repository.import(
          preview: preview,
          policy: ExistingCatalogPolicy.skip,
        );

        expect(second, first);
        expect(await fixture.count('products'), 1);
        expect(await fixture.count('initial_inventory_imports'), 1);
        expect(await fixture.count('initial_inventory_lines'), 1);
        expect(await fixture.count('inventory_lots'), 1);
        expect(await fixture.count('inventory_movements'), 1);
        expect(await fixture.count('sync_queue'), queueAfterFirst);
      },
    );

    test('existing SKU lookup is case insensitive', () async {
      final fixture = await _Fixture.create(role: 'Manager');
      addTearDown(fixture.dispose);

      final productId = await fixture.seedProduct(
        code: 'P001',
        name: 'Existente',
        priceCents: 9000,
      );

      final preview = _preview(
        fingerprint: 'fp-case',
        rows: const [
          CatalogImportRow(
            sku: 'p001',
            name: 'Nombre Archivo',
            category: 'General',
            supplier: 'Proveedor',
            costCents: 5000,
            priceCents: 8000,
            quantity: 4,
          ),
        ],
      );

      await InitialInventoryRepository(fixture.database)
          .import(preview: preview, policy: ExistingCatalogPolicy.skip);

      expect(await fixture.count('products'), 1);

      final lot = (await fixture.db.query('inventory_lots')).single;
      expect(lot['product_id'], productId);
      expect(lot['initial_quantity'], 4);

      final product = (await fixture.db.query(
        'products',
        where: 'id=?',
        whereArgs: [productId],
      )).single;

      expect(product['name'], 'Existente');
      expect(product['sale_price_cents'], 9000);
    });

    test('updateCatalogData updates existing name and sale price', () async {
      final fixture = await _Fixture.create(role: 'Manager');
      addTearDown(fixture.dispose);

      final productId = await fixture.seedProduct(
        code: 'P001',
        name: 'Anterior',
        priceCents: 9000,
      );

      final preview = _preview(
        fingerprint: 'fp-update',
        rows: const [
          CatalogImportRow(
            sku: 'P001',
            name: 'Actualizado',
            category: 'General',
            supplier: '',
            costCents: 0,
            priceCents: 15000,
            quantity: 0,
          ),
        ],
      );

      await InitialInventoryRepository(fixture.database).import(
        preview: preview,
        policy: ExistingCatalogPolicy.updateCatalogData,
      );

      final product = (await fixture.db.query(
        'products',
        where: 'id=?',
        whereArgs: [productId],
      )).single;

      expect(product['name'], 'Actualizado');
      expect(product['sale_price_cents'], 15000);
      expect(await fixture.count('inventory_lots'), 0);
      expect(await fixture.count('inventory_movements'), 0);
      expect(await fixture.count('initial_inventory_imports'), 0);
    });

    test('existing lot in current branch rejects initial inventory', () async {
      final fixture = await _Fixture.create(role: 'Manager');
      addTearDown(fixture.dispose);

      final productId = await fixture.seedProduct(
        code: 'P001',
        name: 'Existente',
        priceCents: 10000,
      );

      await fixture.seedLot(
        productId: productId,
        branchId: fixture.branchId,
        globalId: 'historic-lot',
        quantity: 1,
      );

      final before = await fixture.snapshot();

      await expectLater(
        InitialInventoryRepository(fixture.database).import(
          preview: _stockPreview('fp-current-lot'),
          policy: ExistingCatalogPolicy.skip,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await fixture.snapshot(), before);
    });

    test(
      'existing movement in current branch rejects even without lot',
      () async {
        final fixture = await _Fixture.create(role: 'Manager');
        addTearDown(fixture.dispose);

        final productId = await fixture.seedProduct(
          code: 'P001',
          name: 'Existente',
          priceCents: 10000,
        );

        await fixture.seedMovement(
          productId: productId,
          branchId: fixture.branchId,
          globalId: 'historic-movement',
        );

        final before = await fixture.snapshot();

        await expectLater(
          InitialInventoryRepository(fixture.database).import(
            preview: _stockPreview('fp-current-movement'),
            policy: ExistingCatalogPolicy.skip,
          ),
          throwsA(isA<StateError>()),
        );

        expect(await fixture.snapshot(), before);
      },
    );

    test('history in another branch does not block current branch', () async {
      final fixture = await _Fixture.create(role: 'Manager');
      addTearDown(fixture.dispose);

      final productId = await fixture.seedProduct(
        code: 'P001',
        name: 'Existente',
        priceCents: 10000,
      );

      final otherBranch = await fixture.createBranch(
        globalId: 'branch-2',
        name: 'Other',
      );

      await fixture.seedLot(
        productId: productId,
        branchId: otherBranch,
        globalId: 'other-lot',
        quantity: 5,
      );

      await fixture.seedMovement(
        productId: productId,
        branchId: otherBranch,
        globalId: 'other-movement',
      );

      await InitialInventoryRepository(fixture.database).import(
        preview: _stockPreview('fp-other-branch'),
        policy: ExistingCatalogPolicy.skip,
      );

      final currentLots = await fixture.db.query(
        'inventory_lots',
        where: 'product_id=? AND branch_id=?',
        whereArgs: [productId, fixture.branchId],
      );

      expect(currentLots, hasLength(1));
      expect(currentLots.single['initial_quantity'], 10);
    });

    test(
      'failure on later row rolls back earlier catalog and queue writes',
      () async {
        final fixture = await _Fixture.create(role: 'Manager');
        addTearDown(fixture.dispose);

        final existingProduct = await fixture.seedProduct(
          code: 'P002',
          name: 'Con historial',
          priceCents: 10000,
        );

        await fixture.seedLot(
          productId: existingProduct,
          branchId: fixture.branchId,
          globalId: 'existing-lot',
          quantity: 1,
        );

        final before = await fixture.snapshot();

        final preview = _preview(
          fingerprint: 'fp-rollback',
          rows: const [
            CatalogImportRow(
              sku: 'P001',
              name: 'Debe revertirse',
              category: 'Nueva Categoria',
              supplier: 'Nuevo Proveedor',
              costCents: 10000,
              priceCents: 14000,
              quantity: 10,
            ),
            CatalogImportRow(
              sku: 'P002',
              name: 'Debe fallar',
              category: 'General',
              supplier: 'Proveedor',
              costCents: 10000,
              priceCents: 14000,
              quantity: 5,
            ),
          ],
        );

        await expectLater(
          InitialInventoryRepository(fixture.database)
              .import(preview: preview, policy: ExistingCatalogPolicy.skip),
          throwsA(isA<StateError>()),
        );

        expect(await fixture.snapshot(), before);

        expect(
          await fixture.db.query(
            'products',
            where: 'code=?',
            whereArgs: ['P001'],
          ),
          isEmpty,
        );
      },
    );

    test('Seller is denied before any import mutation', () async {
      final fixture = await _Fixture.create(role: 'Seller');
      addTearDown(fixture.dispose);

      final before = await fixture.snapshot();

      await expectLater(
        InitialInventoryRepository(fixture.database).import(
          preview: _stockPreview('fp-seller'),
          policy: ExistingCatalogPolicy.skip,
        ),
        throwsA(isA<AuthorizationDeniedException>()),
      );

      expect(await fixture.snapshot(), before);
    });

    test('Administrator can create initial inventory', () async {
      final fixture = await _Fixture.create(role: 'Administrator');
      addTearDown(fixture.dispose);

      await InitialInventoryRepository(fixture.database).import(
        preview: _stockPreview('fp-admin'),
        policy: ExistingCatalogPolicy.skip,
      );

      expect(await fixture.count('initial_inventory_imports'), 1);
      expect(await fixture.count('inventory_lots'), 1);
    });

    test(
      'zero stock creates catalog only and no initial inventory operation',
      () async {
        final fixture = await _Fixture.create(role: 'Manager');
        addTearDown(fixture.dispose);

        final preview = _preview(
          fingerprint: 'fp-zero',
          rows: const [
            CatalogImportRow(
              sku: 'ZERO1',
              name: 'Sin existencia',
              category: 'General',
              supplier: '',
              costCents: 0,
              priceCents: 5000,
              quantity: 0,
            ),
          ],
        );

        await InitialInventoryRepository(fixture.database)
            .import(preview: preview, policy: ExistingCatalogPolicy.skip);

        expect(await fixture.count('products'), 1);
        expect(await fixture.count('categories'), 1);
        expect(await fixture.count('inventory_lots'), 0);
        expect(await fixture.count('inventory_movements'), 0);
        expect(await fixture.count('initial_inventory_imports'), 0);
        expect(await fixture.count('initial_inventory_lines'), 0);

        final initialQueue = await fixture.db.query(
          'sync_queue',
          where: "entity_type='InitialInventory'",
        );
        expect(initialQueue, isEmpty);
      },
    );
  });
}

CatalogImportPreview _stockPreview(String fingerprint) => _preview(
  fingerprint: fingerprint,
  rows: const [
    CatalogImportRow(
      sku: 'P001',
      name: 'Producto',
      category: 'General',
      supplier: 'Proveedor',
      costCents: 10000,
      priceCents: 14000,
      quantity: 10,
    ),
  ],
);

CatalogImportPreview _preview({
  required String fingerprint,
  required List<CatalogImportRow> rows,
}) => CatalogImportPreview(rows, const [], fingerprint);

final class _Fixture {
  _Fixture(
    this.database,
    this.db,
    this.now,
    this.businessId,
    this.branchId,
    this.deviceId,
    this.userId,
  );

  final AppDatabase database;
  final Database db;
  final String now;
  final int businessId;
  final int branchId;
  final int deviceId;
  final int userId;

  static const _snapshotTables = <String>[
    'categories',
    'suppliers',
    'products',
    'initial_inventory_imports',
    'initial_inventory_lines',
    'inventory_lots',
    'inventory_movements',
    'audit_logs',
    'sync_queue',
  ];

  static Future<_Fixture> create({required String role}) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await database.open();
    final now = DateTime.utc(2026, 9, 23, 20).toIso8601String();

    final businessId = await db.insert('businesses', {
      'global_id': 'business-1',
      'name': 'Test Business',
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

    final deviceId = await db.insert('devices', {
      'global_id': 'device-1',
      'branch_id': branchId,
      'name': 'Tablet',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });

    final userId = await db.insert('users', {
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

    return _Fixture(database, db, now, businessId, branchId, deviceId, userId);
  }

  Future<int> seedProduct({
    required String code,
    required String name,
    required int priceCents,
  }) => db.insert('products', {
    'global_id': 'product-$code',
    'business_id': businessId,
    'code': code,
    'name': name,
    'presentation': 'Piece',
    'sale_price_cents': priceCents,
    'minimum_stock': 0,
    'active': 1,
    'created_at': now,
    'updated_at': now,
  });

  Future<int> createBranch({required String globalId, required String name}) =>
      db.insert('branches', {
        'global_id': globalId,
        'business_id': businessId,
        'name': name,
        'created_at': now,
        'updated_at': now,
      });

  Future<void> seedLot({
    required int productId,
    required int branchId,
    required String globalId,
    required int quantity,
  }) async {
    await db.insert('inventory_lots', {
      'global_id': globalId,
      'product_id': productId,
      'branch_id': branchId,
      'entry_date': now,
      'initial_quantity': quantity,
      'available_quantity': quantity,
      'unit_cost_cents': 100,
      'active': 1,
      'created_at': now,
    });
  }

  Future<void> seedMovement({
    required int productId,
    required int branchId,
    required String globalId,
  }) async {
    await db.insert('inventory_movements', {
      'global_id': globalId,
      'product_id': productId,
      'branch_id': branchId,
      'movement_date': now,
      'type': 'Adjustment',
      'quantity_delta': 1,
      'previous_stock': 0,
      'new_stock': 1,
      'reference_global_id': 'historic-reference-$globalId',
      'user_id': userId,
      'device_id': deviceId,
    });
  }

  Future<int> count(String table) async {
    final result = await db.rawQuery('SELECT COUNT(*) count FROM $table');
    return result.single['count']! as int;
  }

  Future<Map<String, int>> snapshot() async {
    final result = <String, int>{};
    for (final table in _snapshotTables) {
      result[table] = await count(table);
    }
    return result;
  }

  Future<void> dispose() => database.close();
}
