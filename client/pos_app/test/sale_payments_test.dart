import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/features/payments/domain/sale_payment.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/features/sales/data/sales_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'payment domain rejects empty, zero, negative, duplicate and wrong sums',
    () {
      expect(
        () => SalePaymentRules.validate(const [], totalCents: 100),
        throwsStateError,
      );
      for (final amount in [0, -1]) {
        expect(
          () => SalePaymentRules.validate([
            SalePaymentInput(method: PaymentMethod.cash, amountCents: amount),
          ], totalCents: 100),
          throwsStateError,
        );
      }
      expect(
        () => SalePaymentRules.validate(const [
          SalePaymentInput(method: PaymentMethod.cash, amountCents: 40),
          SalePaymentInput(method: PaymentMethod.cash, amountCents: 60),
        ], totalCents: 100),
        throwsStateError,
      );
      for (final amount in [99, 101]) {
        expect(
          () => SalePaymentRules.validate([
            SalePaymentInput(method: PaymentMethod.card, amountCents: amount),
          ], totalCents: 100),
          throwsStateError,
        );
      }
      expect(() => PaymentMethod.fromStorage('Other'), throwsArgumentError);
    },
  );

  for (final scenario in <({String name, List<SalePaymentInput> payments})>[
    (
      name: 'Cash',
      payments: const [
        SalePaymentInput(method: PaymentMethod.cash, amountCents: 100),
      ],
    ),
    (
      name: 'Card',
      payments: const [
        SalePaymentInput(method: PaymentMethod.card, amountCents: 100),
      ],
    ),
    (
      name: 'Transfer',
      payments: const [
        SalePaymentInput(method: PaymentMethod.transfer, amountCents: 100),
      ],
    ),
    (
      name: 'CashCard',
      payments: const [
        SalePaymentInput(method: PaymentMethod.cash, amountCents: 30),
        SalePaymentInput(method: PaymentMethod.card, amountCents: 70),
      ],
    ),
    (
      name: 'CashTransfer',
      payments: const [
        SalePaymentInput(method: PaymentMethod.cash, amountCents: 30),
        SalePaymentInput(method: PaymentMethod.transfer, amountCents: 70),
      ],
    ),
    (
      name: 'All',
      payments: const [
        SalePaymentInput(method: PaymentMethod.cash, amountCents: 20),
        SalePaymentInput(method: PaymentMethod.card, amountCents: 30),
        SalePaymentInput(method: PaymentMethod.transfer, amountCents: 50),
      ],
    ),
  ]) {
    test(
      '${scenario.name} persists exact payments and only Cash enters drawer',
      () async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        final cashCents = SalePaymentRules.cashCents(scenario.payments);
        final sale = await PosRepository(fixture.database).completeSale(
          [fixture.line],
          payments: scenario.payments,
          receivedCents: cashCents == 0 ? null : cashCents + 20,
        );
        final db = await fixture.database.open();
        final saleRow = (await db.query(
          'sales',
          where: 'global_id=?',
          whereArgs: [sale.globalId],
        )).single;
        final payments = await db.query(
          'sale_payments',
          where: 'sale_id=?',
          whereArgs: [saleRow['id']],
        );
        expect(payments, hasLength(scenario.payments.length));
        expect(
          payments.fold<int>(
            0,
            (sum, row) => sum + (row['amount_cents'] as int),
          ),
          100,
        );
        final movements = await db.query(
          'cash_movements',
          where: "type='Sale' AND reference_global_id=?",
          whereArgs: [sale.globalId],
        );
        expect(movements, hasLength(cashCents == 0 ? 0 : 1));
        if (cashCents > 0) {
          expect(movements.single['amount_cents'], cashCents);
        }
        expect(
          (await db.query('inventory_lots')).single['available_quantity'],
          4,
        );
        final queue = (await db.query(
          'sync_queue',
          where: "entity_type='Sale' AND entity_global_id=?",
          whereArgs: [sale.globalId],
        )).single;
        final payload = jsonDecode(queue['payload_json'] as String) as Map;
        expect(payload['payments'], hasLength(scenario.payments.length));
        expect(queue['payload_version'], 2);
      },
    );
  }

  test(
    'payment insertion failure rolls back sale, FIFO, cash and sync',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final repository = PosRepository(
        fixture.database,
        ids: _SequenceIds([
          'sale',
          'idem',
          'duplicate-payment',
          'duplicate-payment',
        ]),
      );
      await expectLater(
        repository.completeSale(
          [fixture.line],
          payments: const [
            SalePaymentInput(method: PaymentMethod.cash, amountCents: 40),
            SalePaymentInput(method: PaymentMethod.card, amountCents: 60),
          ],
          receivedCents: 40,
        ),
        throwsA(anything),
      );
      final db = await fixture.database.open();
      expect(await _count(db, 'sales'), 0);
      expect(await _count(db, 'sale_payments'), 0);
      expect(await _count(db, 'cash_movements'), 0);
      expect(await _count(db, 'sync_queue'), 1);
      expect(
        (await db.query('inventory_lots')).single['available_quantity'],
        5,
      );
    },
  );

  test('cancellation preserves payments and reverses only Cash', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final sale = await PosRepository(fixture.database).completeSale(
      [fixture.line],
      payments: const [
        SalePaymentInput(method: PaymentMethod.cash, amountCents: 30),
        SalePaymentInput(method: PaymentMethod.card, amountCents: 70),
      ],
      receivedCents: 50,
    );
    await SalesRepository(fixture.database).cancel(sale.globalId, 'Error');
    final db = await fixture.database.open();
    expect(await _count(db, 'sale_payments'), 2);
    final movements = await db.query(
      'cash_movements',
      where: 'reference_global_id=?',
      whereArgs: [sale.globalId],
      orderBy: 'id',
    );
    expect(movements.map((row) => row['amount_cents']), [30, -30]);
    expect((await db.query('inventory_lots')).single['available_quantity'], 5);
  });
}

final class _SequenceIds implements IdGenerator {
  _SequenceIds(this._values);
  final List<String> _values;
  var _index = 0;
  @override
  String newId() =>
      _index < _values.length ? _values[_index++] : 'generated-${_index++}';
}

final class _Fixture {
  _Fixture(this.database, this.line);
  final AppDatabase database;
  final CartLine line;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.open();
    final now = DateTime.utc(2026, 9, 13).toIso8601String();
    final businessId = await db.insert('businesses', {
      'global_id': 'business',
      'name': 'Business',
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
    await db.insert('devices', {
      'global_id': 'device',
      'branch_id': branchId,
      'name': 'POS',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'global_id': 'user',
      'business_id': businessId,
      'name': 'Admin',
      'username': 'admin',
      'password_hash': 'h',
      'password_salt': 's',
      'role': 'Administrator',
      'created_at': now,
      'updated_at': now,
    });
    final productId = await db.insert('products', {
      'global_id': 'product',
      'business_id': businessId,
      'code': 'P',
      'name': 'Product',
      'presentation': 'Piece',
      'sale_price_cents': 100,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('inventory_lots', {
      'global_id': 'lot',
      'product_id': productId,
      'branch_id': branchId,
      'entry_date': now,
      'initial_quantity': 5,
      'available_quantity': 5,
      'unit_cost_cents': 40,
      'created_at': now,
    });
    for (final entry in {
      'local_device_global_id': 'device',
      'active_user_global_id': 'user',
    }.entries) {
      await db.insert('app_settings', {
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }
    await CashRepository(database).open(0);
    return _Fixture(
      database,
      CartLine(
        productId: productId,
        productGlobalId: 'product',
        name: 'Product',
        quantity: 1,
        unitPriceCents: 100,
      ),
    );
  }

  Future<void> dispose() => database.close();
}

Future<int> _count(Database db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS count FROM $table')).single['count']
        as int;
