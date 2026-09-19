import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/database/app_database.dart';

final class CashMovementSummary {
  const CashMovementSummary({
    required this.globalId,
    required this.movementDate,
    required this.type,
    required this.amountCents,
    required this.notes,
  });

  final String globalId;
  final DateTime movementDate;
  final String type;
  final int amountCents;
  final String? notes;
}

final class CashPaymentSummary {
  const CashPaymentSummary({
    required this.cashCents,
    required this.cardCents,
    required this.transferCents,
  });

  final int cashCents;
  final int cardCents;
  final int transferCents;

  int get totalCents => cashCents + cardCents + transferCents;
}

final class CashSessionSummary {
  const CashSessionSummary({
    required this.globalId,
    required this.userName,
    required this.openedAt,
    required this.openingBalanceCents,
    required this.expectedCashCents,
    required this.cashSalesCents,
    required this.cashExpensesCents,
    required this.cashCancellationsCents,
    required this.manualInCents,
    required this.manualOutCents,
    required this.otherMovementCents,
    required this.paymentSummary,
    required this.saleCount,
    required this.movements,
  });

  final String globalId;
  final String userName;
  final DateTime openedAt;
  final int openingBalanceCents;
  final int expectedCashCents;
  final int cashSalesCents;
  final int cashExpensesCents;
  final int cashCancellationsCents;
  final int manualInCents;
  final int manualOutCents;
  final int otherMovementCents;
  final CashPaymentSummary paymentSummary;
  final int saleCount;
  final List<CashMovementSummary> movements;

  int get netCashSalesCents => cashSalesCents - cashCancellationsCents;
}

final class CashReadRepository {
  CashReadRepository(this._db);

  final AppDatabase _db;

  Future<List<Map<String, Object?>>> sessions() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashRead);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.cashRead) ==
        PermissionLevel.ownOnly;
    final columns = <String>[
      'id',
      'opened_at',
      'opening_balance_cents',
      'status',
    ];
    if (authorization.can(Capability.reportsFinancial)) {
      columns.add('difference_cents');
    }
    final database = await _db.open();
    return database.query(
      'cash_sessions',
      columns: columns,
      where: 'branch_id = ?${ownOnly ? ' AND user_id = ?' : ''}',
      whereArgs: [context.branchId, if (ownOnly) context.userId],
      orderBy: 'id DESC',
    );
  }

  Future<bool> hasOpenSession() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashRead);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.cashRead) ==
        PermissionLevel.ownOnly;
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT EXISTS(
           SELECT 1 FROM cash_sessions
           WHERE branch_id = ? AND device_id = ? AND status = 'Open'
           ${ownOnly ? 'AND user_id = ?' : ''}
         ) AS is_open''',
      [context.branchId, context.deviceId, if (ownOnly) context.userId],
    );
    return rows.single['is_open'] == 1;
  }

  Future<CashSessionSummary?> currentSummary({int movementLimit = 20}) async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashRead);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.cashRead) ==
        PermissionLevel.ownOnly;
    final database = await _db.open();

    final sessions = await database.rawQuery(
      '''
      SELECT cs.id, cs.global_id, cs.branch_id, cs.device_id, cs.user_id,
             cs.opened_at, cs.opening_balance_cents, u.name AS user_name
      FROM cash_sessions cs
      JOIN users u ON u.id = cs.user_id
      WHERE cs.branch_id = ? AND cs.device_id = ? AND cs.status = 'Open'
        ${ownOnly ? 'AND cs.user_id = ?' : ''}
      ORDER BY cs.id DESC
      LIMIT 1
      ''',
      [context.branchId, context.deviceId, if (ownOnly) context.userId],
    );
    if (sessions.isEmpty) return null;

    final session = sessions.single;
    final sessionId = session['id'] as int;
    final movementRows = await database.query(
      'cash_movements',
      columns: ['global_id', 'movement_date', 'type', 'amount_cents', 'notes'],
      where: 'cash_session_id=?',
      whereArgs: [sessionId],
      orderBy: 'id DESC',
      limit: movementLimit.clamp(1, 100),
    );
    final allMovementRows = await database.query(
      'cash_movements',
      columns: ['type', 'amount_cents'],
      where: 'cash_session_id=?',
      whereArgs: [sessionId],
    );

    var movementNet = 0;
    var cashSales = 0;
    var cashExpenses = 0;
    var cashCancellations = 0;
    var manualIn = 0;
    var manualOut = 0;
    var knownNet = 0;

    for (final row in allMovementRows) {
      final amount = row['amount_cents'] as int;
      movementNet += amount;
      switch (row['type']) {
        case 'Sale':
          cashSales += amount;
          knownNet += amount;
          break;
        case 'Expense':
          cashExpenses += -amount;
          knownNet += amount;
          break;
        case 'Cancellation':
          cashCancellations += -amount;
          knownNet += amount;
          break;
        case 'ManualIn':
          manualIn += amount;
          knownNet += amount;
          break;
        case 'ManualOut':
          manualOut += -amount;
          knownNet += amount;
          break;
      }
    }

    final openedAt = session['opened_at'] as String;
    final paymentRows = await database.rawQuery(
      '''
      SELECT sp.method, COALESCE(SUM(sp.amount_cents), 0) AS amount_cents
      FROM sale_payments sp
      JOIN sales s ON s.id = sp.sale_id
      WHERE s.branch_id = ? AND s.device_id = ?
        AND s.sale_datetime >= ? AND s.status = 'Confirmed'
      GROUP BY sp.method
      ''',
      [session['branch_id'], session['device_id'], openedAt],
    );
    var paymentCash = 0;
    var paymentCard = 0;
    var paymentTransfer = 0;
    for (final row in paymentRows) {
      final amount = row['amount_cents'] as int;
      switch (row['method']) {
        case 'Cash':
          paymentCash = amount;
          break;
        case 'Card':
          paymentCard = amount;
          break;
        case 'Transfer':
          paymentTransfer = amount;
          break;
      }
    }

    final saleCountRows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM sales
      WHERE branch_id = ? AND device_id = ?
        AND sale_datetime >= ? AND status = 'Confirmed'
      ''',
      [session['branch_id'], session['device_id'], openedAt],
    );

    return CashSessionSummary(
      globalId: session['global_id'] as String,
      userName: session['user_name'] as String,
      openedAt: DateTime.parse(openedAt).toUtc(),
      openingBalanceCents: session['opening_balance_cents'] as int,
      expectedCashCents:
          (session['opening_balance_cents'] as int) + movementNet,
      cashSalesCents: cashSales,
      cashExpensesCents: cashExpenses,
      cashCancellationsCents: cashCancellations,
      manualInCents: manualIn,
      manualOutCents: manualOut,
      otherMovementCents: movementNet - knownNet,
      paymentSummary: CashPaymentSummary(
        cashCents: paymentCash,
        cardCents: paymentCard,
        transferCents: paymentTransfer,
      ),
      saleCount: saleCountRows.single['count'] as int,
      movements: movementRows
          .map(
            (row) => CashMovementSummary(
              globalId: row['global_id'] as String,
              movementDate: DateTime.parse(row['movement_date'] as String)
                  .toUtc(),
              type: row['type'] as String,
              amountCents: row['amount_cents'] as int,
              notes: row['notes'] as String?,
            ),
          )
          .toList(growable: false),
    );
  }
}
