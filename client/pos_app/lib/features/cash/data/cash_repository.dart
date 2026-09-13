import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

enum ManualCashMovementType {
  deposit('ManualIn', 1),
  withdrawal('ManualOut', -1);

  const ManualCashMovementType(this.storageValue, this.sign);

  final String storageValue;
  final int sign;
}

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

      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': 'CashSession',
        'entity_global_id': gid,
        'action': 'Open',
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
        'details_json': jsonEncode({'openingBalanceCents': openingCents}),
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

  Future<String> addManualMovement({
    required ManualCashMovementType type,
    required int amountCents,
    required String reason,
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError('El monto debe ser mayor que cero.');
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError('El motivo es obligatorio.');
    }
    if (normalizedReason.length > 240) {
      throw ArgumentError('El motivo no puede exceder 240 caracteres.');
    }

    final capability = switch (type) {
      ManualCashMovementType.deposit => Capability.cashDeposit,
      ManualCashMovementType.withdrawal => Capability.cashWithdrawal,
    };
    final authorization = await AuthorizationService(_db).load();
    final specialAuthorization = SpecialAuthorizationService(_db);
    final prepared = await specialAuthorization.prepare(
      effective: authorization,
      capability: capability,
      grant: authorizationGrant,
    );
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = _ids.newId();
    final signedAmount = amountCents * type.sign;

    await _db.criticalTransaction((tx) async {
      final sessions = await tx.query(
        'cash_sessions',
        where: "branch_id=? AND device_id=? AND status='Open'",
        whereArgs: [ctx.branchId, ctx.deviceId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (sessions.isEmpty) {
        throw StateError('Debe existir caja abierta.');
      }

      final session = sessions.first;
      if (type == ManualCashMovementType.withdrawal) {
        final movements = await tx.rawQuery(
          'SELECT COALESCE(SUM(amount_cents),0) s '
          'FROM cash_movements WHERE cash_session_id=?',
          [session['id']],
        );
        final expected =
            (session['opening_balance_cents'] as int) +
            (movements.first['s'] as int);
        if (amountCents > expected) {
          throw StateError(
            'El retiro excede el efectivo esperado disponible en caja.',
          );
        }
      }

      final authorizationMetadata = await specialAuthorization
          .consumeInTransaction(
            tx,
            prepared: prepared,
            effective: authorization,
            capability: capability,
            operation: type == ManualCashMovementType.deposit
                ? 'ManualDeposit'
                : 'ManualWithdrawal',
            entityType: 'CashMovement',
            entityGlobalId: gid,
          );

      await tx.insert('cash_movements', {
        'global_id': gid,
        'cash_session_id': session['id'],
        'movement_date': now,
        'type': type.storageValue,
        'amount_cents': signedAmount,
        'reference_global_id': null,
        'user_id': ctx.userId,
        'notes': normalizedReason,
      });

      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': 'CashMovement',
        'entity_global_id': gid,
        'action': type == ManualCashMovementType.deposit
            ? 'ManualDeposit'
            : 'ManualWithdrawal',
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
        'details_json': jsonEncode({
          'cashSessionGlobalId': session['global_id'],
          'type': type.storageValue,
          'amountCents': signedAmount,
          'reason': normalizedReason,
          'authorization': ?authorizationMetadata,
        }),
      });

      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'CashMovement',
        'entity_global_id': gid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': gid,
          'businessGlobalId': ctx.businessGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'cashSessionGlobalId': session['global_id'],
          'date': now,
          'type': type.storageValue,
          'amountCents': signedAmount,
          'notes': normalizedReason,
          'authorization': ?authorizationMetadata,
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
    final ownOnly =
        authorization.permissionFor(Capability.cashClose) ==
        PermissionLevel.ownOnly;
    final db = await _db.open();

    final currentRows = await db.query(
      'cash_sessions',
      where:
          "branch_id=? AND device_id=? AND status='Open'"
          "${ownOnly ? ' AND user_id=?' : ''}",
      whereArgs: [ctx.branchId, ctx.deviceId, if (ownOnly) ctx.userId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (currentRows.isEmpty) throw StateError('No hay caja abierta.');

    final current = currentRows.first;
    final currentMovements = await db.rawQuery(
      'SELECT COALESCE(SUM(amount_cents),0) s '
      'FROM cash_movements WHERE cash_session_id=?',
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
        where:
            "branch_id=? AND device_id=? AND status='Open'"
            "${ownOnly ? ' AND user_id=?' : ''}",
        whereArgs: [ctx.branchId, ctx.deviceId, if (ownOnly) ctx.userId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('No hay caja abierta.');

      final session = rows.first;
      final movements = await tx.rawQuery(
        'SELECT COALESCE(SUM(amount_cents),0) s '
        'FROM cash_movements WHERE cash_session_id=?',
        [session['id']],
      );
      final expected =
          (session['opening_balance_cents'] as int) +
          (movements.first['s'] as int);
      if ((countedCents != expected) != hasDifference ||
          session['global_id'] != current['global_id']) {
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
              entityGlobalId: session['global_id'] as String,
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
        whereArgs: [session['id']],
      );

      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': 'CashSession',
        'entity_global_id': session['global_id'],
        'action': 'Close',
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
        'details_json': jsonEncode({
          'expectedCashCents': expected,
          'countedCashCents': countedCents,
          'differenceCents': countedCents - expected,
          'authorization': ?authorizationMetadata,
        }),
      });

      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'CashSession',
        'entity_global_id': session['global_id'],
        'operation': 'Update',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': session['global_id'],
          'businessGlobalId': ctx.businessGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'openedAt': session['opened_at'],
          'openingBalanceCents': session['opening_balance_cents'],
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
