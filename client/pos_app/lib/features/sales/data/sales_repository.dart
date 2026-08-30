import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class SalesRepository {
  SalesRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _db;
  final IdGenerator _ids;
  Future<void> cancel(
    String saleGlobalId,
    String reason, {
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    final authorization = await AuthorizationService(_db).load();
    final specialAuthorization = SpecialAuthorizationService(_db);
    final prepared = await specialAuthorization.prepare(
      effective: authorization,
      capability: Capability.saleCancel,
      grant: authorizationGrant,
    );
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.criticalTransaction((tx) async {
      final sales = await tx.query(
        'sales',
        where: 'global_id=?',
        whereArgs: [saleGlobalId],
        limit: 1,
      );
      if (sales.isEmpty) throw StateError('Venta inexistente.');
      final sale = sales.first;
      if (sale['status'] == 'Cancelled') return;
      final authorizationMetadata = await specialAuthorization
          .consumeInTransaction(
            tx,
            prepared: prepared,
            effective: authorization,
            capability: Capability.saleCancel,
            operation: 'Cancel',
            entityType: 'Sale',
            entityGlobalId: saleGlobalId,
          );
      final details = await tx.query(
        'sale_details',
        where: 'sale_id=?',
        whereArgs: [sale['id']],
      );
      for (final d in details) {
        final allocations = await tx.rawQuery(
          'SELECT sdl.quantity,sdl.inventory_lot_id,p.id product_id FROM sale_detail_lots sdl JOIN sale_details sd ON sd.id=sdl.sale_detail_id JOIN products p ON p.id=sd.product_id WHERE sdl.sale_detail_id=?',
          [d['id']],
        );
        for (final a in allocations) {
          final beforeRows = await tx.rawQuery(
            'SELECT COALESCE(SUM(available_quantity),0) s FROM inventory_lots WHERE product_id=? AND branch_id=?',
            [a['product_id'], ctx.branchId],
          );
          final before = beforeRows.first['s'] as int;
          await tx.rawUpdate(
            'UPDATE inventory_lots SET available_quantity=available_quantity+? WHERE id=?',
            [a['quantity'], a['inventory_lot_id']],
          );
          await tx.insert('inventory_movements', {
            'global_id': _ids.newId(),
            'product_id': a['product_id'],
            'branch_id': ctx.branchId,
            'movement_date': now,
            'type': 'Cancellation',
            'quantity_delta': a['quantity'],
            'previous_stock': before,
            'new_stock': before + (a['quantity'] as int),
            'reference_global_id': saleGlobalId,
            'user_id': ctx.userId,
            'device_id': ctx.deviceId,
            'notes': reason,
          });
        }
      }
      if (sale['payment_method'] == 'Cash') {
        final cash = await tx.query(
          'cash_sessions',
          where: "device_id=? AND status='Open'",
          whereArgs: [ctx.deviceId],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (cash.isEmpty) {
          throw StateError(
            'Debe existir caja abierta para cancelar una venta en efectivo.',
          );
        }
        await tx.insert('cash_movements', {
          'global_id': _ids.newId(),
          'cash_session_id': cash.first['id'],
          'movement_date': now,
          'type': 'Cancellation',
          'amount_cents': -(sale['total_cents'] as int),
          'reference_global_id': saleGlobalId,
          'user_id': ctx.userId,
          'notes': reason,
        });
      }
      await tx.update(
        'sales',
        {
          'status': 'Cancelled',
          'cancelled_at': now,
          'cancellation_reason': reason,
          'cancelled_by_user_id': ctx.userId,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [sale['id']],
      );
      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': 'Sale',
        'entity_global_id': saleGlobalId,
        'action': 'Cancel',
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
        'details_json': jsonEncode({
          'reason': reason,
          'authorization': ?authorizationMetadata,
        }),
      });
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Sale',
        'entity_global_id': saleGlobalId,
        'operation': 'Cancel',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': saleGlobalId,
          'reason': reason,
          'cancelledAt': now,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'authorization': ?authorizationMetadata,
        }),
        'created_at': now,
      });
    });
  }
}
