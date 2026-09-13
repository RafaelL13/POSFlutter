import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/cash/data/cash_read_repository.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('manager manual deposit is atomic, audited and queued', () async {
    final fixture = await _CashFixture.create(role: 'Manager');
    addTearDown(fixture.dispose);
    final repository = CashRepository(fixture.database);

    await repository.open(1000);
    final movementId = await repository.addManualMovement(
      type: ManualCashMovementType.deposit,
      amountCents: 500,
      reason: 'Fondo adicional',
    );

    final db = await fixture.database.open();
    final movement = (await db.query(
      'cash_movements',
      where: 'global_id=?',
      whereArgs: [movementId],
    )).single;
    expect(movement['type'], 'ManualIn');
    expect(movement['amount_cents'], 500);
    expect(movement['notes'], 'Fondo adicional');

    final audit = (await db.query(
      'audit_logs',
      where: "entity_type='CashMovement' AND entity_global_id=?",
      whereArgs: [movementId],
    )).single;
    expect(audit['action'], 'ManualDeposit');

    final queued = (await db.query(
      'sync_queue',
      where: "entity_type='CashMovement' AND entity_global_id=?",
      whereArgs: [movementId],
    )).single;
    expect(queued['operation'], 'Create');
    expect(queued['payload_version'], 1);
    final payload = jsonDecode(queued['payload_json'] as String) as Map;
    expect(payload['type'], 'ManualIn');
    expect(payload['amountCents'], 500);
    expect(payload['cashSessionGlobalId'], isNotEmpty);
  });

  test(
    'manager withdrawal is negative and cannot exceed expected cash',
    () async {
      final fixture = await _CashFixture.create(role: 'Manager');
      addTearDown(fixture.dispose);
      final repository = CashRepository(fixture.database);
      await repository.open(1000);

      final movementId = await repository.addManualMovement(
        type: ManualCashMovementType.withdrawal,
        amountCents: 400,
        reason: 'Retiro parcial',
      );
      final db = await fixture.database.open();
      final movement = (await db.query(
        'cash_movements',
        where: 'global_id=?',
        whereArgs: [movementId],
      )).single;
      expect(movement['type'], 'ManualOut');
      expect(movement['amount_cents'], -400);

      final before = await _count(db, 'cash_movements');
      await expectLater(
        repository.addManualMovement(
          type: ManualCashMovementType.withdrawal,
          amountCents: 601,
          reason: 'Excede caja',
        ),
        throwsStateError,
      );
      expect(await _count(db, 'cash_movements'), before);
    },
  );

  test(
    'supervisor withdrawal requires additional authorization before mutation',
    () async {
      final fixture = await _CashFixture.create(role: 'Supervisor');
      addTearDown(fixture.dispose);
      final repository = CashRepository(fixture.database);
      await repository.open(1000);
      final db = await fixture.database.open();
      final queueBefore = await _count(db, 'sync_queue');

      await expectLater(
        repository.addManualMovement(
          type: ManualCashMovementType.withdrawal,
          amountCents: 100,
          reason: 'Retiro sensible',
        ),
        throwsA(isA<AdditionalAuthorizationRequiredException>()),
      );

      expect(await _count(db, 'cash_movements'), 0);
      expect(await _count(db, 'sync_queue'), queueBefore);
    },
  );

  test('seller cannot create manual cash movements', () async {
    final fixture = await _CashFixture.create(role: 'Seller');
    addTearDown(fixture.dispose);
    final repository = CashRepository(fixture.database);
    await repository.open(1000);

    for (final type in ManualCashMovementType.values) {
      await expectLater(
        repository.addManualMovement(
          type: type,
          amountCents: 100,
          reason: 'No permitido',
        ),
        throwsA(isA<AuthorizationDeniedException>()),
      );
    }

    final db = await fixture.database.open();
    expect(await _count(db, 'cash_movements'), 0);
  });

  test('seller own-only close cannot close another seller session', () async {
    final fixture = await _CashFixture.create(
      role: 'Seller',
      includeOtherSeller: true,
    );
    addTearDown(fixture.dispose);
    final db = await fixture.database.open();
    final now = DateTime.utc(2026, 9, 13, 8).toIso8601String();

    await db.insert('cash_sessions', {
      'global_id': 'other-session',
      'branch_id': fixture.branchId,
      'device_id': fixture.deviceId,
      'user_id': fixture.otherUserId,
      'opened_at': now,
      'opening_balance_cents': 0,
      'status': 'Open',
      'updated_at': now,
    });

    await expectLater(
      CashRepository(fixture.database).close(0),
      throwsStateError,
    );

    final session = (await db.query(
      'cash_sessions',
      where: 'global_id=?',
      whereArgs: ['other-session'],
    )).single;
    expect(session['status'], 'Open');
  });

  test('current summary reconciles drawer and payment methods', () async {
    final fixture = await _CashFixture.create(role: 'Manager');
    addTearDown(fixture.dispose);
    final repository = CashRepository(fixture.database);
    await repository.open(10000);
    final db = await fixture.database.open();

    final session = (await db.query(
      'cash_sessions',
      where: "status='Open'",
    )).single;
    final saleTime = DateTime.now().toUtc().add(const Duration(seconds: 1));
    final saleId = await db.insert('sales', {
      'global_id': 'summary-sale',
      'idempotency_key': 'summary-idem',
      'folio': 'V-SUM',
      'sale_datetime': saleTime.toIso8601String(),
      'user_id': fixture.userId,
      'device_id': fixture.deviceId,
      'branch_id': fixture.branchId,
      'subtotal_cents': 6000,
      'discount_cents': 0,
      'total_cents': 6000,
      'fifo_cost_cents': 0,
      'gross_profit_cents': 6000,
      'payment_method': 'Mixed',
      'change_cents': 0,
      'status': 'PendingPayment',
      'created_at': saleTime.toIso8601String(),
      'updated_at': saleTime.toIso8601String(),
    });
    for (final entry in const [
      ('Cash', 3000, 'summary-pay-cash'),
      ('Card', 2000, 'summary-pay-card'),
      ('Transfer', 1000, 'summary-pay-transfer'),
    ]) {
      await db.insert('sale_payments', {
        'global_id': entry.$3,
        'sale_id': saleId,
        'method': entry.$1,
        'amount_cents': entry.$2,
        'created_at': saleTime.toIso8601String(),
      });
    }
    await db.update(
      'sales',
      {'status': 'Confirmed'},
      where: 'id=?',
      whereArgs: [saleId],
    );

    await db.insert('cash_movements', {
      'global_id': 'summary-sale-cash',
      'cash_session_id': session['id'],
      'movement_date': saleTime.toIso8601String(),
      'type': 'Sale',
      'amount_cents': 3000,
      'reference_global_id': 'summary-sale',
      'user_id': fixture.userId,
    });
    await db.insert('cash_movements', {
      'global_id': 'summary-expense',
      'cash_session_id': session['id'],
      'movement_date': saleTime.toIso8601String(),
      'type': 'Expense',
      'amount_cents': -500,
      'reference_global_id': 'expense-summary',
      'user_id': fixture.userId,
    });
    await db.insert('cash_movements', {
      'global_id': 'summary-cancel',
      'cash_session_id': session['id'],
      'movement_date': saleTime.toIso8601String(),
      'type': 'Cancellation',
      'amount_cents': -300,
      'reference_global_id': 'cancel-summary',
      'user_id': fixture.userId,
    });

    await repository.addManualMovement(
      type: ManualCashMovementType.deposit,
      amountCents: 1000,
      reason: 'Fondo',
    );
    await repository.addManualMovement(
      type: ManualCashMovementType.withdrawal,
      amountCents: 700,
      reason: 'Retiro',
    );

    final summary = await CashReadRepository(fixture.database).currentSummary();

    expect(summary, isNotNull);
    expect(summary!.openingBalanceCents, 10000);
    expect(summary.cashSalesCents, 3000);
    expect(summary.cashExpensesCents, 500);
    expect(summary.cashCancellationsCents, 300);
    expect(summary.manualInCents, 1000);
    expect(summary.manualOutCents, 700);
    expect(summary.expectedCashCents, 12500);
    expect(summary.paymentSummary.cashCents, 3000);
    expect(summary.paymentSummary.cardCents, 2000);
    expect(summary.paymentSummary.transferCents, 1000);
    expect(summary.paymentSummary.totalCents, 6000);
    expect(summary.saleCount, 1);
  });

  test('exact close persists reconciliation and audit', () async {
    final fixture = await _CashFixture.create(role: 'Manager');
    addTearDown(fixture.dispose);
    final repository = CashRepository(fixture.database);
    await repository.open(1000);
    await repository.addManualMovement(
      type: ManualCashMovementType.deposit,
      amountCents: 500,
      reason: 'Fondo',
    );

    await repository.close(1500);

    final db = await fixture.database.open();
    final session = (await db.query('cash_sessions')).single;
    expect(session['status'], 'Closed');
    expect(session['expected_cash_cents'], 1500);
    expect(session['counted_cash_cents'], 1500);
    expect(session['difference_cents'], 0);

    final audits = await db.query(
      'audit_logs',
      where: "entity_type='CashSession' AND action='Close'",
    );
    expect(audits, hasLength(1));
  });
}

final class _CashFixture {
  _CashFixture(
    this.database, {
    required this.branchId,
    required this.deviceId,
    required this.userId,
    this.otherUserId,
  });

  final AppDatabase database;
  final int branchId;
  final int deviceId;
  final int userId;
  final int? otherUserId;

  static Future<_CashFixture> create({
    required String role,
    bool includeOtherSeller = false,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.open();
    final now = DateTime.utc(2026, 9, 13).toIso8601String();
    final businessId = await db.insert('businesses', {
      'global_id': 'cash-business',
      'name': 'Negocio',
      'created_at': now,
      'updated_at': now,
    });
    final branchId = await db.insert('branches', {
      'global_id': 'cash-branch',
      'business_id': businessId,
      'name': 'Principal',
      'created_at': now,
      'updated_at': now,
    });
    final deviceId = await db.insert('devices', {
      'global_id': 'cash-device',
      'branch_id': branchId,
      'name': 'Caja',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });
    final userId = await db.insert('users', {
      'global_id': 'cash-user',
      'business_id': businessId,
      'name': 'Usuario',
      'username': 'cash-user',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': role,
      'created_at': now,
      'updated_at': now,
    });

    int? otherUserId;
    if (includeOtherSeller) {
      otherUserId = await db.insert('users', {
        'global_id': 'cash-other-user',
        'business_id': businessId,
        'name': 'Otro cajero',
        'username': 'cash-other-user',
        'password_hash': 'hash',
        'password_salt': 'salt',
        'role': 'Seller',
        'created_at': now,
        'updated_at': now,
      });
    }

    for (final entry in {
      'local_device_global_id': 'cash-device',
      'active_user_global_id': 'cash-user',
    }.entries) {
      await db.insert('app_settings', {
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }

    return _CashFixture(
      database,
      branchId: branchId,
      deviceId: deviceId,
      userId: userId,
      otherUserId: otherUserId,
    );
  }

  Future<void> dispose() => database.close();
}

Future<int> _count(Database db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS count FROM $table')).single['count']
        as int;
