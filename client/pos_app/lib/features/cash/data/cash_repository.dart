import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class CashRepository {
  CashRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _db;
  final IdGenerator _ids;
  Future<String> open(int openingCents) async {
    if (openingCents < 0) throw ArgumentError('Saldo inválido.');
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashOpen);
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = _ids.newId();
    await _db.criticalTransaction((tx) async {
      final open = await tx.query(
        'cash_sessions',
        where: "device_id=? AND status='Open'",
        whereArgs: [ctx.deviceId],
      );
      if (open.isNotEmpty) throw StateError('Ya existe caja abierta.');
      await tx.insert('cash_sessions', {
        'global_id': gid,
        'branch_id': ctx.branchId,
        'device_id': ctx.deviceId,
        'user_id': ctx.userId,
        'opened_at': now,
        'opening_balance_cents': openingCents,
        'status': 'Open',
        'updated_at': now,
      });
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'CashSession',
        'entity_global_id': gid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': gid,
          'businessGlobalId': ctx.businessGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'openedAt': now,
          'openingBalanceCents': openingCents,
          'status': 'Open',
        }),
        'created_at': now,
      });
    });
    return gid;
  }

  Future<void> close(
    int countedCents, {
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    if (countedCents < 0) throw ArgumentError('Contado inválido.');
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashClose);
    final ctx = authorization.context!;
    final db = await _db.open();
    final currentRows = await db.query(
      'cash_sessions',
      where: "device_id=? AND status='Open'",
      whereArgs: [ctx.deviceId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (currentRows.isEmpty) throw StateError('No hay caja abierta.');
    final current = currentRows.first;
    final currentMovements = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_cents),0) s FROM cash_movements WHERE cash_session_id=?',
      [current['id']],
    );
    final currentExpected =
        (current['opening_balance_cents'] as int) +
        (currentMovements.first['s'] as int);
    final hasDifference = countedCents != currentExpected;
    final specialAuthorization = SpecialAuthorizationService(_db);
    final prepared = hasDifference
        ? await specialAuthorization.prepare(
            effective: authorization,
            capability: Capability.cashCloseWithDifference,
            grant: authorizationGrant,
          )
        : const PreparedSpecialAuthorization.direct();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.criticalTransaction((tx) async {
      final rows = await tx.query(
        'cash_sessions',
        where: "device_id=? AND status='Open'",
        whereArgs: [ctx.deviceId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('No hay caja abierta.');
      final r = rows.first;
      final movements = await tx.rawQuery(
        'SELECT COALESCE(SUM(amount_cents),0) s FROM cash_movements WHERE cash_session_id=?',
        [r['id']],
      );
      final expected =
          (r['opening_balance_cents'] as int) + (movements.first['s'] as int);
      if ((countedCents != expected) != hasDifference ||
          r['global_id'] != current['global_id']) {
        throw StateError('La caja cambió; vuelve a intentar el cierre.');
      }
      final authorizationMetadata = hasDifference
          ? await specialAuthorization.consumeInTransaction(
              tx,
              prepared: prepared,
              effective: authorization,
              capability: Capability.cashCloseWithDifference,
              operation: 'CloseWithDifference',
              entityType: 'CashSession',
              entityGlobalId: r['global_id'] as String,
            )
          : null;
      await tx.update(
        'cash_sessions',
        {
          'status': 'Closed',
          'closed_at': now,
          'counted_cash_cents': countedCents,
          'expected_cash_cents': expected,
          'difference_cents': countedCents - expected,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [r['id']],
      );
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'CashSession',
        'entity_global_id': r['global_id'],
        'operation': 'Update',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': r['global_id'],
          'businessGlobalId': ctx.businessGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'openedAt': r['opened_at'],
          'openingBalanceCents': r['opening_balance_cents'],
          'status': 'Closed',
          'closedAt': now,
          'countedCashCents': countedCents,
          'expectedCashCents': expected,
          'differenceCents': countedCents - expected,
          'authorization': ?authorizationMetadata,
        }),
        'created_at': now,
      });
    });
  }
}
