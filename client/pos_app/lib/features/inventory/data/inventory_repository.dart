import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/inventory/domain/fifo.dart';

final class InventoryRepository {
  InventoryRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _db;
  final IdGenerator _ids;
  Future<int> stock(int productId, int branchId) async {
    await AuthorizationService(_db)
        .require(Capability.inventoryAvailabilityRead);
    final db = await _db.open();
    return stockInTx(db, productId, branchId);
  }

  Future<int> stockInTx(dynamic tx, int productId, int branchId) async {
    final r = await tx.rawQuery(
      'SELECT COALESCE(SUM(available_quantity),0) s FROM inventory_lots WHERE product_id=? AND branch_id=? AND active=1',
      [productId, branchId],
    );
    return r.first['s'] as int;
  }

  Future<List<FifoLot>> fifoLots(
    dynamic tx,
    int productId,
    int branchId,
  ) async {
    final rows = await tx.query(
      'inventory_lots',
      where:
          'product_id=? AND branch_id=? AND available_quantity>0 AND active=1',
      whereArgs: [productId, branchId],
      orderBy: 'entry_date ASC,id ASC',
    );
    return rows
        .map<FifoLot>(
          (r) => FifoLot(
            id: r['id'] as int,
            globalId: r['global_id'] as String,
            available: r['available_quantity'] as int,
            unitCostCents: r['unit_cost_cents'] as int,
          ),
        )
        .toList();
  }

  Future<String> productGlobal(dynamic tx, int productId) async {
    final r = await tx.query(
      'products',
      columns: ['global_id'],
      where: 'id=?',
      whereArgs: [productId],
      limit: 1,
    );
    if (r.isEmpty) throw StateError('Producto inexistente.');
    return r.first['global_id'] as String;
  }

  Future<void> adjust({
    required int productId,
    required int delta,
    required String reason,
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    if (delta == 0) throw ArgumentError('El ajuste no puede ser cero.');
    if (reason.trim().isEmpty) throw ArgumentError('El motivo es obligatorio.');
    final authorization = await AuthorizationService(_db).load();
    final specialAuthorization = SpecialAuthorizationService(_db);
    final prepared = await specialAuthorization.prepare(
      effective: authorization,
      capability: Capability.inventoryAdjust,
      grant: authorizationGrant,
    );
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = _ids.newId();
    await _db.criticalTransaction((tx) async {
      final authorizationMetadata = await specialAuthorization
          .consumeInTransaction(
            tx,
            prepared: prepared,
            effective: authorization,
            capability: Capability.inventoryAdjust,
            operation: 'Create',
            entityType: 'InventoryAdjustment',
            entityGlobalId: gid,
          );
      final before = await stockInTx(tx, productId, ctx.branchId);
      if (before + delta < 0) {
        throw StateError('Stock insuficiente para el ajuste.');
      }
      final productGid = await productGlobal(tx, productId);
      String? newLotGid;
      int? unitCost;
      final allocations = <Map<String, Object?>>[];
      if (delta > 0) {
        newLotGid = _ids.newId();
        unitCost = 0;
        await tx.insert('inventory_lots', {
          'global_id': newLotGid,
          'product_id': productId,
          'branch_id': ctx.branchId,
          'entry_date': now,
          'initial_quantity': delta,
          'available_quantity': delta,
          'unit_cost_cents': unitCost,
          'created_at': now,
        });
      } else {
        final fifo = allocateFifo(
          await fifoLots(tx, productId, ctx.branchId),
          -delta,
        );
        for (final a in fifo) {
          await tx.rawUpdate(
            'UPDATE inventory_lots SET available_quantity=available_quantity-? WHERE id=?',
            [a.quantity, a.lot.id],
          );
          allocations.add({
            'lotGlobalId': a.lot.globalId,
            'quantity': a.quantity,
            'unitCostCents': a.lot.unitCostCents,
          });
        }
      }
      await tx.insert('inventory_adjustments', {
        'global_id': gid,
        'product_id': productId,
        'branch_id': ctx.branchId,
        'quantity_delta': delta,
        'reason': reason,
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
      });
      await tx.insert('inventory_movements', {
        'global_id': _ids.newId(),
        'product_id': productId,
        'branch_id': ctx.branchId,
        'movement_date': now,
        'type': 'Correction',
        'quantity_delta': delta,
        'previous_stock': before,
        'new_stock': before + delta,
        'reference_global_id': gid,
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'notes': reason,
      });
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'InventoryAdjustment',
        'entity_global_id': gid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': gid,
          'businessGlobalId': ctx.businessGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'productGlobalId': productGid,
          'date': now,
          'type': 'Correction',
          'quantityDelta': delta,
          'reason': reason,
          'newLotGlobalId': newLotGid,
          'unitCostCents': unitCost,
          'allocations': allocations,
          'authorization': ?authorizationMetadata,
        }),
        'created_at': now,
      });
    });
  }
}
