import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/backup/data/local_backup_provider.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/features/catalog/data/catalog_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/features/sales/data/sales_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late PasswordHash _validPassword;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    _validPassword = await PasswordHasher().hash('correct-password');
  });

  group('SpecialAuthorizationService', () {
    test(
      'Manager and Administrator can authorize Seller cancellation',
      () async {
        final fixture = await _Fixture.create(actor: 'seller');
        addTearDown(fixture.dispose);
        final service = SpecialAuthorizationService(fixture.database);

        final managerGrant = await service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'manager',
          password: 'correct-password',
          reason: 'Manager approval',
        );
        final adminGrant = await service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'admin',
          password: 'correct-password',
          reason: 'Administrator approval',
        );

        expect(managerGrant.performedByUserGlobalId, 'user-seller');
        expect(managerGrant.authorizedByUserGlobalId, 'user-manager');
        expect(adminGrant.authorizedByUserGlobalId, 'user-admin');
        expect(
          managerGrant.requirement,
          SpecialAuthorizationRequirement.secondUserAuthorization,
        );
      },
    );

    test('fails closed for invalid authorizers and credentials', () async {
      final fixture = await _Fixture.create(actor: 'seller');
      addTearDown(fixture.dispose);
      final service = SpecialAuthorizationService(fixture.database);

      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'other-seller',
          password: 'correct-password',
          reason: 'No privilege',
        ),
        SpecialAuthorizationFailure.authorizerNotAllowed,
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'supervisor',
          password: 'correct-password',
          reason: 'Also requires approval',
        ),
        SpecialAuthorizationFailure.authorizerNotAllowed,
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'inactive-manager',
          password: 'correct-password',
          reason: 'Inactive',
        ),
        SpecialAuthorizationFailure.invalidCredentials,
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'manager',
          password: 'wrong-password',
          reason: 'Wrong password',
        ),
        SpecialAuthorizationFailure.invalidCredentials,
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'unknown',
          password: 'correct-password',
          reason: 'Unknown',
        ),
        SpecialAuthorizationFailure.invalidCredentials,
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'outside-manager',
          password: 'correct-password',
          reason: 'Other business',
        ),
        SpecialAuthorizationFailure.invalidCredentials,
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'seller',
          password: 'correct-password',
          reason: 'Self',
        ),
        SpecialAuthorizationFailure.selfAuthorization,
      );

      await fixture.db.execute('PRAGMA ignore_check_constraints=ON');
      await fixture.db.update(
        'users',
        {'role': 'UnknownRole'},
        where: 'global_id=?',
        whereArgs: ['user-manager'],
      );
      await _expectSpecialFailure(
        service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'manager',
          password: 'correct-password',
          reason: 'Unknown role',
        ),
        SpecialAuthorizationFailure.authorizerNotAllowed,
      );
    });

    test(
      'binds grant to capability, actor, persisted data and one use',
      () async {
        final fixture = await _Fixture.create(actor: 'supervisor');
        addTearDown(fixture.dispose);
        final service = SpecialAuthorizationService(fixture.database);
        final grant = await service.authorizeSecondUser(
          capability: Capability.saleCancel,
          username: 'manager',
          password: 'correct-password',
          reason: 'Specific cancellation',
        );
        var effective = await AuthorizationService(fixture.database).load();

        await _expectSpecialFailure(
          service.prepare(
            effective: effective,
            capability: Capability.inventoryAdjust,
            grant: grant,
          ),
          SpecialAuthorizationFailure.invalidGrant,
        );
        final tampered = SpecialAuthorizationGrant(
          globalId: grant.globalId,
          capability: grant.capability,
          requirement: grant.requirement,
          performedByUserGlobalId: grant.performedByUserGlobalId,
          authorizedByUserGlobalId: grant.authorizedByUserGlobalId,
          businessGlobalId: grant.businessGlobalId,
          deviceGlobalId: grant.deviceGlobalId,
          reason: 'Changed reason',
          authorizedAt: grant.authorizedAt,
        );
        await _expectSpecialFailure(
          service.prepare(
            effective: effective,
            capability: Capability.saleCancel,
            grant: tampered,
          ),
          SpecialAuthorizationFailure.invalidGrant,
        );

        await fixture.useActor('other-seller');
        effective = await AuthorizationService(fixture.database).load();
        await _expectSpecialFailure(
          service.prepare(
            effective: effective,
            capability: Capability.saleCancel,
            grant: grant,
          ),
          SpecialAuthorizationFailure.invalidGrant,
        );

        await fixture.useActor('supervisor');
        effective = await AuthorizationService(fixture.database).load();
        final prepared = await service.prepare(
          effective: effective,
          capability: Capability.saleCancel,
          grant: grant,
        );
        final metadata = await fixture.database.criticalTransaction(
          (tx) => service.consumeInTransaction(
            tx,
            prepared: prepared,
            effective: effective,
            capability: Capability.saleCancel,
            operation: 'Cancel',
            entityType: 'Sale',
            entityGlobalId: 'sale-specific',
          ),
        );
        expect(metadata?['authorizedByUserGlobalId'], 'user-manager');
        expect(metadata?['entityGlobalId'], 'sale-specific');
        await _expectSpecialFailure(
          service.prepare(
            effective: effective,
            capability: Capability.saleCancel,
            grant: grant,
          ),
          SpecialAuthorizationFailure.consumedGrant,
        );
      },
    );

    test(
      'Administrator reauthentication works and DeviceMode cannot bypass',
      () async {
        final fixture = await _Fixture.create(actor: 'admin');
        addTearDown(fixture.dispose);
        final service = SpecialAuthorizationService(fixture.database);

        await _expectSpecialFailure(
          service.reauthenticate(
            capability: Capability.backupRestore,
            username: 'admin',
            password: 'wrong-password',
            reason: 'Restore',
          ),
          SpecialAuthorizationFailure.invalidCredentials,
        );
        final grant = await service.reauthenticate(
          capability: Capability.backupRestore,
          username: 'admin',
          password: 'correct-password',
          reason: 'Restore approved',
        );
        expect(grant.authorizedByUserGlobalId, grant.performedByUserGlobalId);
        expect(
          grant.requirement,
          SpecialAuthorizationRequirement.reauthentication,
        );

        await fixture.setDeviceMode('AdminReadOnly');
        await expectLater(
          service.reauthenticate(
            capability: Capability.backupRestore,
            username: 'admin',
            password: 'correct-password',
            reason: 'Blocked restore',
          ),
          throwsA(isA<AuthorizationDeniedException>()),
        );
      },
    );
  });

  group('repository integration', () {
    test(
      'sale cancellation enforces grant, restores exact lots and audits',
      () async {
        final fixture = await _Fixture.create(actor: 'seller');
        addTearDown(fixture.dispose);
        await fixture.seedCancelledSaleScenario();
        final repository = SalesRepository(fixture.database);

        await expectLater(
          repository.cancel('sale-1', 'Customer request'),
          throwsA(isA<AdditionalAuthorizationRequiredException>()),
        );
        expect(
          await fixture.value('sales', 'status', 'global_id', 'sale-1'),
          'Confirmed',
        );
        expect(
          await fixture.value(
            'inventory_lots',
            'available_quantity',
            'global_id',
            'lot-1',
          ),
          7,
        );
        expect(await fixture.count('sync_queue'), 0);

        final grant = await fixture.authorize(Capability.saleCancel);
        await repository.cancel(
          'sale-1',
          'Customer request',
          authorizationGrant: grant,
        );
        expect(
          await fixture.value('sales', 'status', 'global_id', 'sale-1'),
          'Cancelled',
        );
        expect(
          await fixture.value(
            'inventory_lots',
            'available_quantity',
            'global_id',
            'lot-1',
          ),
          10,
        );
        expect(await fixture.count('sync_queue'), 1);
        final audits = await fixture.db.query('audit_logs', orderBy: 'id');
        expect(audits, hasLength(2));
        final details = jsonDecode(
          audits.first['details_json']! as String,
        ) as Map<String, dynamic>;
        expect(details['performedByUserGlobalId'], 'user-seller');
        expect(details['authorizedByUserGlobalId'], 'user-manager');
        expect(details['reason'], isNotEmpty);
        expect(details['authorizedAt'], isNotNull);
        expect(details.toString(), isNot(contains('correct-password')));
      },
    );

    test('Supervisor cancel requires grant while Manager is direct', () async {
      final fixture = await _Fixture.create(actor: 'supervisor');
      addTearDown(fixture.dispose);
      await fixture.seedCancelledSaleScenario();
      final repository = SalesRepository(fixture.database);
      await expectLater(
        repository.cancel('sale-1', 'Denied'),
        throwsA(isA<AdditionalAuthorizationRequiredException>()),
      );
      await fixture.useActor('manager');
      await repository.cancel('sale-1', 'Manager direct');
      expect(
        await fixture.value('sales', 'status', 'global_id', 'sale-1'),
        'Cancelled',
      );
    });

    test(
      'discount zero is normal, positive requires grant, invalid stays invalid',
      () async {
        final fixture = await _Fixture.create(actor: 'seller');
        addTearDown(fixture.dispose);
        final product = await fixture.seedProductAndLot(quantity: 10);
        final repository = PosRepository(fixture.database);
        final line = CartLine(
          productId: product,
          productGlobalId: 'product-1',
          name: 'Product',
          quantity: 1,
          unitPriceCents: 100,
        );
        await repository.completeSale([line], paymentMethod: 'Card');
        await expectLater(
          repository.completeSale(
            [line],
            paymentMethod: 'Card',
            discountCents: 10,
          ),
          throwsA(isA<AdditionalAuthorizationRequiredException>()),
        );
        expect(await fixture.count('sales'), 1);
        final grant = await fixture.authorize(Capability.saleDiscount);
        await repository.completeSale(
          [line],
          paymentMethod: 'Card',
          discountCents: 10,
          authorizationGrant: grant,
        );
        expect(await fixture.count('sales'), 2);
        await expectLater(
          repository.completeSale(
            [line],
            paymentMethod: 'Card',
            discountCents: 101,
          ),
          throwsA(anything),
        );
        await fixture.useActor('manager');
        await repository.completeSale(
          [line],
          paymentMethod: 'Card',
          discountCents: 5,
        );
        expect(await fixture.count('sales'), 3);
      },
    );

    test('inventory and price obey none/requires/full policy', () async {
      final fixture = await _Fixture.create(actor: 'supervisor');
      addTearDown(fixture.dispose);
      final product = await fixture.seedProductAndLot(quantity: 5);
      final inventory = InventoryRepository(fixture.database);
      final catalog = CatalogRepository(fixture.database);

      await expectLater(
        inventory.adjust(productId: product, delta: 1, reason: 'Count'),
        throwsA(isA<AdditionalAuthorizationRequiredException>()),
      );
      final inventoryGrant = await fixture.authorize(
        Capability.inventoryAdjust,
      );
      await inventory.adjust(
        productId: product,
        delta: 1,
        reason: 'Count',
        authorizationGrant: inventoryGrant,
      );
      await expectLater(
        catalog.changeProductPrice(productId: product, salePriceCents: 150),
        throwsA(isA<AdditionalAuthorizationRequiredException>()),
      );
      final priceGrant = await fixture.authorize(Capability.productPriceChange);
      await catalog.changeProductPrice(
        productId: product,
        salePriceCents: 150,
        authorizationGrant: priceGrant,
      );

      final unusedGrant = await fixture.authorize(Capability.inventoryAdjust);
      await fixture.useActor('seller');
      await expectLater(
        inventory.adjust(
          productId: product,
          delta: 1,
          reason: 'Seller denied',
          authorizationGrant: unusedGrant,
        ),
        throwsA(isA<AuthorizationDeniedException>()),
      );
      await expectLater(
        catalog.changeProductPrice(
          productId: product,
          salePriceCents: 175,
          authorizationGrant: priceGrant,
        ),
        throwsA(isA<AuthorizationDeniedException>()),
      );

      await fixture.useActor('manager');
      await inventory.adjust(
        productId: product,
        delta: 1,
        reason: 'Manager direct',
      );
      await catalog.changeProductPrice(productId: product, salePriceCents: 200);
      expect(
        await fixture.value('products', 'sale_price_cents', 'id', product),
        200,
      );
    });

    test(
      'cash closes normally and requires grant only for real difference',
      () async {
        final fixture = await _Fixture.create(actor: 'seller');
        addTearDown(fixture.dispose);
        final cash = CashRepository(fixture.database);
        await cash.open(100);
        await cash.close(100);
        await cash.open(100);
        await expectLater(
          cash.close(101),
          throwsA(isA<AdditionalAuthorizationRequiredException>()),
        );
        expect(await fixture.value('cash_sessions', 'status', 'id', 2), 'Open');
        final grant = await fixture.authorize(
          Capability.cashCloseWithDifference,
        );
        await cash.close(101, authorizationGrant: grant);
        expect(
          await fixture.value('cash_sessions', 'difference_cents', 'id', 2),
          1,
        );

        await fixture.useActor('manager');
        await cash.open(50);
        await cash.close(49);
        expect(
          await fixture.value('cash_sessions', 'difference_cents', 'id', 3),
          -1,
        );
      },
    );

    test(
      'backup restore requires reauth, strong confirmation and permits Admin',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'pos_auth_backup_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final fixture = await _Fixture.create(
          actor: 'admin',
          databasePath: '${directory.path}${Platform.pathSeparator}target.db',
        );
        addTearDown(fixture.dispose);
        final sourcePath =
            '${directory.path}${Platform.pathSeparator}source.db';
        final escapedSource = sourcePath.replaceAll("'", "''");
        await fixture.db.execute("VACUUM INTO '$escapedSource'");
        await fixture.db.insert('app_settings', {
          'key': 'marker-after-backup',
          'value': 'must-disappear',
          'updated_at': fixture.now,
        });
        final provider = LocalBackupProvider(fixture.database);

        await expectLater(
          provider.restoreBackup(sourcePath, confirmedDestructiveRestore: true),
          throwsA(isA<AdditionalAuthorizationRequiredException>()),
        );
        await _expectSpecialFailure(
          SpecialAuthorizationService(fixture.database).reauthenticate(
            capability: Capability.backupRestore,
            username: 'admin',
            password: 'wrong-password',
            reason: 'Restore',
          ),
          SpecialAuthorizationFailure.invalidCredentials,
        );
        final grant = await SpecialAuthorizationService(fixture.database)
            .reauthenticate(
              capability: Capability.backupRestore,
              username: 'admin',
              password: 'correct-password',
              reason: 'Disaster recovery',
            );
        await expectLater(
          provider.restoreBackup(sourcePath, reauthenticationGrant: grant),
          throwsA(isA<StateError>()),
        );
        expect(
          await fixture.value(
            'special_authorization_grants',
            'consumed_at',
            'global_id',
            grant.globalId,
          ),
          isNull,
        );

        await fixture.setDeviceMode('AdminReadOnly');
        await expectLater(
          provider.restoreBackup(sourcePath, confirmedDestructiveRestore: true),
          throwsA(isA<AuthorizationDeniedException>()),
        );
        await fixture.setDeviceMode('PointOfSale');
        await provider.restoreBackup(
          sourcePath,
          reauthenticationGrant: grant,
          confirmedDestructiveRestore: true,
        );
        final reopened = await fixture.database.open();
        expect(
          await reopened.query(
            'app_settings',
            where: 'key=?',
            whereArgs: ['marker-after-backup'],
          ),
          isEmpty,
        );
        expect(
          await fixture.value(
            'special_authorization_grants',
            'consumed_at',
            'global_id',
            grant.globalId,
          ),
          isNotNull,
        );
        final audit = (await reopened.query(
          'audit_logs',
          where: "action='SpecialAuthorization'",
        ));
        expect(audit, hasLength(1));
        expect(audit.single['details_json'], contains('Reauthentication'));
        expect(
          audit.single['details_json'],
          isNot(contains('correct-password')),
        );
      },
    );
  });
}

Future<void> _expectSpecialFailure(
  Future<Object?> operation,
  SpecialAuthorizationFailure failure,
) => expectLater(
  operation,
  throwsA(
    isA<SpecialAuthorizationException>().having(
      (exception) => exception.failure,
      'failure',
      failure,
    ),
  ),
);

final class _Fixture {
  _Fixture(this.database, this.db, this.now);

  final AppDatabase database;
  Database db;
  final String now;

  static Future<_Fixture> create({
    required String actor,
    String? databasePath,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath ?? inMemoryDatabasePath,
    );
    final db = await database.open();
    final now = DateTime.utc(2026, 8, 29, 12).toIso8601String();
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
    Future<void> user(String username, String role, {bool active = true}) =>
        db.insert('users', {
          'global_id': 'user-$username',
          'business_id': businessId,
          'name': username,
          'username': username,
          'password_hash': _validPassword.hash,
          'password_salt': _validPassword.salt,
          'role': role,
          'active': active ? 1 : 0,
          'created_at': now,
          'updated_at': now,
        });
    await user('seller', 'Seller');
    await user('other-seller', 'Seller');
    await user('supervisor', 'Supervisor');
    await user('manager', 'Manager');
    await user('admin', 'Administrator');
    await user('inactive-manager', 'Manager', active: false);
    final otherBusinessId = await db.insert('businesses', {
      'global_id': 'business-2',
      'name': 'Other Business',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'global_id': 'user-outside-manager',
      'business_id': otherBusinessId,
      'name': 'Outside Manager',
      'username': 'outside-manager',
      'password_hash': _validPassword.hash,
      'password_salt': _validPassword.salt,
      'role': 'Manager',
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
      'value': 'user-$actor',
      'updated_at': now,
    });
    return _Fixture(database, db, now);
  }

  Future<void> useActor(String username) => db.update(
    'app_settings',
    {'value': 'user-$username', 'updated_at': now},
    where: 'key=?',
    whereArgs: ['active_user_global_id'],
  );

  Future<void> setDeviceMode(String mode) => db.update(
    'devices',
    {'mode': mode, 'updated_at': now},
    where: 'global_id=?',
    whereArgs: ['device-1'],
  );

  Future<SpecialAuthorizationGrant> authorize(Capability capability) =>
      SpecialAuthorizationService(database).authorizeSecondUser(
        capability: capability,
        username: 'manager',
        password: 'correct-password',
        reason: 'Approved $capability',
      );

  Future<int> seedProductAndLot({required int quantity}) async {
    final businessId =
        await value('businesses', 'id', 'global_id', 'business-1') as int;
    final branchId =
        await value('branches', 'id', 'global_id', 'branch-1') as int;
    final productId = await db.insert('products', {
      'global_id': 'product-1',
      'business_id': businessId,
      'code': 'P1',
      'name': 'Product',
      'presentation': 'Piece',
      'sale_price_cents': 100,
      'minimum_stock': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('inventory_lots', {
      'global_id': 'lot-1',
      'product_id': productId,
      'branch_id': branchId,
      'entry_date': now,
      'initial_quantity': quantity,
      'available_quantity': quantity,
      'unit_cost_cents': 40,
      'created_at': now,
    });
    return productId;
  }

  Future<void> seedCancelledSaleScenario() async {
    final productId = await seedProductAndLot(quantity: 10);
    final userId =
        await value('users', 'id', 'global_id', 'user-seller') as int;
    final deviceId =
        await value('devices', 'id', 'global_id', 'device-1') as int;
    final branchId =
        await value('branches', 'id', 'global_id', 'branch-1') as int;
    await db.update(
      'inventory_lots',
      {'available_quantity': 7},
      where: 'global_id=?',
      whereArgs: ['lot-1'],
    );
    final saleId = await db.insert('sales', {
      'global_id': 'sale-1',
      'idempotency_key': 'idem-1',
      'folio': 'V-1',
      'sale_datetime': now,
      'user_id': userId,
      'device_id': deviceId,
      'branch_id': branchId,
      'subtotal_cents': 300,
      'discount_cents': 0,
      'total_cents': 300,
      'fifo_cost_cents': 120,
      'gross_profit_cents': 180,
      'payment_method': 'Card',
      'change_cents': 0,
      'status': 'Confirmed',
      'created_at': now,
      'updated_at': now,
    });
    final detailId = await db.insert('sale_details', {
      'global_id': 'detail-1',
      'sale_id': saleId,
      'product_id': productId,
      'quantity': 3,
      'unit_price_cents': 100,
      'total_cents': 300,
      'fifo_cost_cents': 120,
    });
    final lotId =
        await value('inventory_lots', 'id', 'global_id', 'lot-1') as int;
    await db.insert('sale_detail_lots', {
      'global_id': 'detail-lot-1',
      'sale_detail_id': detailId,
      'inventory_lot_id': lotId,
      'quantity': 3,
      'unit_cost_cents': 40,
      'total_cost_cents': 120,
    });
  }

  Future<Object?> value(
    String table,
    String column,
    String keyColumn,
    Object key,
  ) async {
    db = await database.open();
    final rows = await db.query(
      table,
      columns: [column],
      where: '$keyColumn=?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.single[column];
  }

  Future<int> count(String table) async {
    db = await database.open();
    final rows = await db.rawQuery('SELECT COUNT(*) count FROM $table');
    return rows.single['count']! as int;
  }

  Future<void> dispose() => database.close();
}
