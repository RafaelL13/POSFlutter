import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class ExpenseRepository {
  ExpenseRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _db;
  final IdGenerator _ids;
  Future<String> create({
    required String concept,
    required int amountCents,
    String paymentMethod = 'Cash',
    String? category,
  }) async {
    if (amountCents <= 0) throw ArgumentError('Monto inválido.');
    final authorization = await AuthorizationService(_db)
        .require(Capability.expenseCreate);
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = _ids.newId();
    await _db.criticalTransaction((tx) async {
      await tx.insert('expenses', {
        'global_id': gid,
        'expense_date': now,
        'concept': concept.trim(),
        'category': category,
        'amount_cents': amountCents,
        'payment_method': paymentMethod,
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'branch_id': ctx.branchId,
        'created_at': now,
      });
      String? cashSessionGlobalId;
      if (paymentMethod == 'Cash') {
        final cash = await tx.query(
          'cash_sessions',
          where: "device_id=? AND status='Open'",
          whereArgs: [ctx.deviceId],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (cash.isEmpty) {
          throw StateError('Debe existir caja abierta para gasto en efectivo.');
        }
        cashSessionGlobalId = cash.first['global_id']?.toString();
        if (cashSessionGlobalId == null || cashSessionGlobalId.isEmpty) {
          throw StateError('La caja abierta no tiene identificador de sincronización.');
        }
        await tx.insert('cash_movements', {
          'global_id': _ids.newId(),
          'cash_session_id': cash.first['id'],
          'movement_date': now,
          'type': 'Expense',
          'amount_cents': -amountCents,
          'reference_global_id': gid,
          'user_id': ctx.userId,
        });
      }
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Expense',
        'entity_global_id': gid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': gid,
          'businessGlobalId': ctx.businessGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'date': now,
          'concept': concept.trim(),
          'category': category,
          'amountCents': amountCents,
          'paymentMethod': paymentMethod,
          'cashSessionGlobalId': cashSessionGlobalId,
        }),
        'created_at': now,
      });
    });
    return gid;
  }
}
