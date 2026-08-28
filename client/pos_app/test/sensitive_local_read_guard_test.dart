import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/cash/data/cash_read_repository.dart';
import 'package:pos_app/features/expenses/data/expense_read_repository.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/features/purchases/data/purchase_read_repository.dart';
import 'package:pos_app/features/reports/data/report_repository.dart';
import 'package:pos_app/features/sales/data/sales_read_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'Seller reads only own sales and cash without sensitive values',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      await fixture.activate('seller');

      final sales = await SalesReadRepository(fixture.database).list();
      expect(sales, hasLength(1));
      expect(sales.single['folio'], 'SELLER-1');
      expect(sales.single, isNot(contains('fifo_cost_cents')));
      expect(sales.single, isNot(contains('gross_profit_cents')));

      final metrics = await ReportRepository(
        fixture.database,
        clock: () => DateTime.utc(2026, 8, 27),
      ).today();
      expect(metrics.salesCents, 1000000);
      expect(metrics.operations, 1);
      expect(metrics.fifoCostCents, isNull);
      expect(metrics.grossProfitCents, isNull);
      expect(metrics.expensesCents, isNull);
      expect(metrics.marginBasisPoints, isNull);
      expect(metrics.resultCents, isNull);

      final cash = await CashReadRepository(fixture.database).sessions();
      expect(cash, hasLength(1));
      expect(cash.single['opening_balance_cents'], 100);
      expect(cash.single, isNot(contains('difference_cents')));
    },
  );

  test('Seller is denied costs, expenses, lots and inventory value', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    await fixture.activate('seller');

    await _denied(PurchaseReadRepository(fixture.database).list());
    await _denied(
      PurchaseReadRepository(fixture.database).lines(fixture.purchaseId),
    );
    await _denied(ExpenseReadRepository(fixture.database).list());
    await _denied(InventoryReadRepository(fixture.database).lots());
    await _denied(
      InventoryReadRepository(fixture.database).inventoryValueCents(),
    );

    final availability = await InventoryReadRepository(fixture.database)
        .availability();
    expect(availability.single['stock'], 3);
    expect(availability.single, isNot(contains('unit_cost_cents')));
  });

  test(
    'Supervisor reads operations but cannot infer protected costs',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      await fixture.activate('supervisor');

      final purchases = await PurchaseReadRepository(fixture.database).list();
      expect(purchases.single, isNot(contains('total_cents')));
      final lines = await PurchaseReadRepository(fixture.database)
          .lines(fixture.purchaseId);
      expect(lines.single, isNot(contains('unit_cost_cents')));
      expect(lines.single, isNot(contains('subtotal_cents')));

      final lots = await InventoryReadRepository(fixture.database).lots();
      expect(lots.single, isNot(contains('unit_cost_cents')));
      await _denied(
        InventoryReadRepository(fixture.database).inventoryValueCents(),
      );

      final metrics = await ReportRepository(
        fixture.database,
        clock: () => DateTime.utc(2026, 8, 27),
      ).today();
      expect(metrics.fifoCostCents, isNull);
      expect(metrics.grossProfitCents, isNull);
      expect(metrics.marginBasisPoints, isNull);
      expect(metrics.expensesCents, 333333);
    },
  );

  test(
    'Manager receives explicitly authorized sensitive projections',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.database.close);
      await fixture.activate('manager');

      final purchases = await PurchaseReadRepository(fixture.database).list();
      expect(purchases.single['total_cents'], 444444);
      final lines = await PurchaseReadRepository(fixture.database)
          .lines(fixture.purchaseId);
      expect(lines.single['unit_cost_cents'], 444444);
      expect(lines.single['subtotal_cents'], 444444);
      expect(
        await InventoryReadRepository(fixture.database).inventoryValueCents(),
        777777,
      );
      expect(
        (await InventoryReadRepository(
          fixture.database,
        ).lots()).single['unit_cost_cents'],
        259259,
      );
      expect(
        (await CashReadRepository(
          fixture.database,
        ).sessions()).first['difference_cents'],
        222222,
      );

      final metrics = await ReportRepository(
        fixture.database,
        clock: () => DateTime.utc(2026, 8, 27),
      ).today();
      expect(metrics.salesCents, 1005000);
      expect(metrics.fifoCostCents, 123466);
      expect(metrics.grossProfitCents, 654341);
      expect(metrics.expensesCents, 333333);
      expect(metrics.marginBasisPoints, 6510);
      expect(metrics.resultCents, 321008);
    },
  );

  test('Administrator receives authorized financial reads', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    await fixture.activate('administrator');

    final metrics = await ReportRepository(
      fixture.database,
      clock: () => DateTime.utc(2026, 8, 27),
    ).today();
    expect(metrics.fifoCostCents, 123466);
    expect(metrics.grossProfitCents, 654341);
    expect(metrics.marginBasisPoints, 6510);
    expect(metrics.expensesCents, 333333);
    expect(
      await InventoryReadRepository(fixture.database).inventoryValueCents(),
      777777,
    );
    expect(
      (await PurchaseReadRepository(fixture.database).lines(fixture.purchaseId))
          .single['unit_cost_cents'],
      444444,
    );
  });

  test('AdminReadOnly does not elevate Seller reads and invalid context fails closed', () async {
    final fixture = await _fixture(mode: 'AdminReadOnly');
    addTearDown(fixture.database.close);
    await fixture.activate('seller');

    expect(await SalesReadRepository(fixture.database).list(), hasLength(1));
    await _denied(PurchaseReadRepository(fixture.database).list());
    await _denied(
      InventoryReadRepository(fixture.database).inventoryValueCents(),
    );

    final db = await fixture.database.open();
    await db.delete('app_settings', where: "key = 'active_user_global_id'");
    await _denied(SalesReadRepository(fixture.database).list());
  });

  test('Unknown persisted role fails closed before sensitive reads', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);
    await fixture.activate('seller');
    final db = await fixture.database.open();
    await db.execute('PRAGMA ignore_check_constraints = ON');
    await db.update(
      'users',
      {'role': 'Unknown'},
      where: 'global_id = ?',
      whereArgs: ['seller'],
    );

    await _denied(SalesReadRepository(fixture.database).list());
    await _denied(
      InventoryReadRepository(fixture.database).inventoryValueCents(),
    );
  });
}

Future<void> _denied(Future<Object?> operation) async {
  await expectLater(operation, throwsA(isA<AuthorizationDeniedException>()));
}

final class _Fixture {
  const _Fixture(this.database, this.purchaseId);
  final AppDatabase database;
  final int purchaseId;

  Future<void> activate(String userGlobalId) async {
    final db = await database.open();
    await db.update('app_settings', {
      'value': userGlobalId,
      'updated_at': '2026-08-27T12:00:00.000Z',
    }, where: "key = 'active_user_global_id'");
  }
}

Future<_Fixture> _fixture({String mode = 'PointOfSale'}) async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final db = await database.open();
  const now = '2026-08-27T12:00:00.000Z';
  final businessId = await db.insert('businesses', {
    'global_id': 'business',
    'name': 'Test',
    'created_at': now,
    'updated_at': now,
  });
  final branchId = await db.insert('branches', {
    'global_id': 'branch',
    'business_id': businessId,
    'name': 'Main',
    'created_at': now,
    'updated_at': now,
  });
  final deviceId = await db.insert('devices', {
    'global_id': 'device',
    'branch_id': branchId,
    'name': 'Tablet',
    'mode': mode,
    'created_at': now,
    'updated_at': now,
  });
  final users = <String, int>{};
  for (final entry in {
    'administrator': 'Administrator',
    'seller': 'Seller',
    'seller-2': 'Seller',
    'supervisor': 'Supervisor',
    'manager': 'Manager',
  }.entries) {
    users[entry.key] = await db.insert('users', {
      'global_id': entry.key,
      'business_id': businessId,
      'name': entry.key,
      'username': entry.key,
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': entry.value,
      'created_at': now,
      'updated_at': now,
    });
  }
  final supplierId = await db.insert('suppliers', {
    'global_id': 'supplier',
    'business_id': businessId,
    'name': 'Supplier',
    'created_at': now,
    'updated_at': now,
  });
  final productId = await db.insert('products', {
    'global_id': 'product',
    'business_id': businessId,
    'code': 'P1',
    'name': 'Product',
    'sale_price_cents': 1000000,
    'created_at': now,
    'updated_at': now,
  });
  final purchaseId = await db.insert('purchases', {
    'global_id': 'purchase',
    'supplier_id': supplierId,
    'branch_id': branchId,
    'device_id': deviceId,
    'user_id': users['manager'],
    'purchase_date': now,
    'total_cents': 444444,
    'created_at': now,
  });
  final detailId = await db.insert('purchase_details', {
    'global_id': 'detail',
    'purchase_id': purchaseId,
    'product_id': productId,
    'quantity': 1,
    'unit_cost_cents': 444444,
    'subtotal_cents': 444444,
  });
  await db.insert('inventory_lots', {
    'global_id': 'lot',
    'product_id': productId,
    'purchase_detail_id': detailId,
    'branch_id': branchId,
    'entry_date': now,
    'initial_quantity': 3,
    'available_quantity': 3,
    'unit_cost_cents': 259259,
    'created_at': now,
  });
  await _sale(
    db,
    'seller-sale',
    'SELLER-1',
    users['seller']!,
    deviceId,
    branchId,
    1000000,
    123456,
    654321,
  );
  await _sale(
    db,
    'other-sale',
    'OTHER-1',
    users['seller-2']!,
    deviceId,
    branchId,
    5000,
    10,
    20,
  );
  await db.insert('expenses', {
    'global_id': 'expense',
    'expense_date': now,
    'concept': 'Rent',
    'amount_cents': 333333,
    'payment_method': 'Cash',
    'user_id': users['manager'],
    'device_id': deviceId,
    'branch_id': branchId,
    'created_at': now,
  });
  await _cash(
    db,
    'seller-cash',
    users['seller']!,
    deviceId,
    branchId,
    100,
    111111,
  );
  await _cash(
    db,
    'manager-cash',
    users['manager']!,
    deviceId,
    branchId,
    200,
    222222,
  );
  await db.insert('app_settings', {
    'key': 'local_device_global_id',
    'value': 'device',
    'updated_at': now,
  });
  await db.insert('app_settings', {
    'key': 'active_user_global_id',
    'value': 'seller',
    'updated_at': now,
  });
  return _Fixture(database, purchaseId);
}

Future<void> _sale(
  Database db,
  String globalId,
  String folio,
  int userId,
  int deviceId,
  int branchId,
  int total,
  int cost,
  int profit,
) async {
  await db.insert('sales', {
    'global_id': globalId,
    'idempotency_key': '$globalId-key',
    'folio': folio,
    'sale_datetime': '2026-08-27T10:00:00.000Z',
    'user_id': userId,
    'device_id': deviceId,
    'branch_id': branchId,
    'subtotal_cents': total,
    'total_cents': total,
    'fifo_cost_cents': cost,
    'gross_profit_cents': profit,
    'payment_method': 'Cash',
    'created_at': '2026-08-27T10:00:00.000Z',
    'updated_at': '2026-08-27T10:00:00.000Z',
  });
}

Future<void> _cash(
  Database db,
  String globalId,
  int userId,
  int deviceId,
  int branchId,
  int opening,
  int difference,
) async {
  await db.insert('cash_sessions', {
    'global_id': globalId,
    'branch_id': branchId,
    'device_id': deviceId,
    'user_id': userId,
    'opened_at': '2026-08-27T08:00:00.000Z',
    'opening_balance_cents': opening,
    'status': 'Closed',
    'difference_cents': difference,
    'updated_at': '2026-08-27T12:00:00.000Z',
  });
}
