import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/inventory/data/inventory_repository.dart';
import 'package:pos_app/features/inventory/domain/fifo.dart';
import 'package:pos_app/features/pos/domain/cart.dart';

final class CompletedSale {
  const CompletedSale(this.globalId, this.totalCents, this.fifoCostCents);
  final String globalId;
  final int totalCents;
  final int fifoCostCents;
}

final class PosRepository {
  PosRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator(),
      _inventory = InventoryRepository(_db);
  final AppDatabase _db;
  final IdGenerator _ids;
  final InventoryRepository _inventory;
  Future<CompletedSale> completeSale(
    List<CartLine> lines, {
    required String paymentMethod,
    int discountCents = 0,
    int? receivedCents,
  }) async {
    if (lines.isEmpty) throw StateError('La venta no puede estar vacía.');
    for (final l in lines) {
      if (l.quantity <= 0) {
        throw StateError('Las cantidades deben ser enteras positivas.');
      }
    }
    final authorization = await AuthorizationService(_db)
        .require(Capability.saleCreate);
    if (discountCents > 0) authorization.require(Capability.saleDiscount);
    final ctx = authorization.context!;
    final totals = calculateSaleTotals(lines, discountCents: discountCents);
    if (paymentMethod == 'Cash' && (receivedCents ?? 0) < totals.totalCents) {
      throw StateError('Efectivo recibido insuficiente.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final saleGid = _ids.newId();
    final idem = _ids.newId();
    var fifoCost = 0;
    return _db.criticalTransaction((tx) async {
      final cash = await tx.query(
        'cash_sessions',
        where: "device_id=? AND status='Open'",
        whereArgs: [ctx.deviceId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (paymentMethod == 'Cash' && cash.isEmpty) {
        throw StateError('Debe abrir caja antes de vender en efectivo.');
      }
      final saleId = await tx.insert('sales', {
        'global_id': saleGid,
        'idempotency_key': idem,
        'folio': 'V-${DateTime.now().millisecondsSinceEpoch}',
        'sale_datetime': now,
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'branch_id': ctx.branchId,
        'subtotal_cents': totals.subtotalCents,
        'discount_cents': discountCents,
        'total_cents': totals.totalCents,
        'fifo_cost_cents': 0,
        'gross_profit_cents': 0,
        'payment_method': paymentMethod,
        'received_cents': receivedCents,
        'change_cents': paymentMethod == 'Cash'
            ? (receivedCents! - totals.totalCents)
            : 0,
        'status': 'Confirmed',
        'created_at': now,
        'updated_at': now,
      });
      final linePayloads = <Map<String, Object?>>[];
      for (final line in lines) {
        final before = await _inventory.stockInTx(
          tx,
          line.productId,
          ctx.branchId,
        );
        final allocations = allocateFifo(
          await _inventory.fifoLots(tx, line.productId, ctx.branchId),
          line.quantity,
        );
        final detailGid = _ids.newId();
        final lineCost = allocations.fold<int>(
          0,
          (s, a) => s + a.totalCostCents,
        );
        fifoCost += lineCost;
        final detailId = await tx.insert('sale_details', {
          'global_id': detailGid,
          'sale_id': saleId,
          'product_id': line.productId,
          'quantity': line.quantity,
          'unit_price_cents': line.unitPriceCents,
          'total_cents': line.totalCents,
          'fifo_cost_cents': lineCost,
        });
        final lotsPayload = <Map<String, Object?>>[];
        for (final a in allocations) {
          await tx.rawUpdate(
            'UPDATE inventory_lots SET available_quantity=available_quantity-? WHERE id=?',
            [a.quantity, a.lot.id],
          );
          await tx.insert('sale_detail_lots', {
            'global_id': _ids.newId(),
            'sale_detail_id': detailId,
            'inventory_lot_id': a.lot.id,
            'quantity': a.quantity,
            'unit_cost_cents': a.lot.unitCostCents,
            'total_cost_cents': a.totalCostCents,
          });
          lotsPayload.add({
            'inventoryLotGlobalId': a.lot.globalId,
            'quantity': a.quantity,
            'unitCostCents': a.lot.unitCostCents,
            'totalCostCents': a.totalCostCents,
          });
        }
        await tx.insert('inventory_movements', {
          'global_id': _ids.newId(),
          'product_id': line.productId,
          'branch_id': ctx.branchId,
          'movement_date': now,
          'type': 'Sale',
          'quantity_delta': -line.quantity,
          'previous_stock': before,
          'new_stock': before - line.quantity,
          'reference_global_id': saleGid,
          'user_id': ctx.userId,
          'device_id': ctx.deviceId,
        });
        linePayloads.add({
          'detailGlobalId': detailGid,
          'productGlobalId': line.productGlobalId,
          'quantity': line.quantity,
          'unitPriceCents': line.unitPriceCents,
          'discountCents': 0,
          'totalCents': line.totalCents,
          'fifoCostCents': lineCost,
          'lots': lotsPayload,
        });
      }
      await tx.update(
        'sales',
        {
          'fifo_cost_cents': fifoCost,
          'gross_profit_cents': totals.totalCents - fifoCost,
        },
        where: 'id=?',
        whereArgs: [saleId],
      );
      if (paymentMethod == 'Cash') {
        await tx.insert('cash_movements', {
          'global_id': _ids.newId(),
          'cash_session_id': cash.first['id'],
          'movement_date': now,
          'type': 'Sale',
          'amount_cents': totals.totalCents,
          'reference_global_id': saleGid,
          'user_id': ctx.userId,
        });
      }
      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': 'Sale',
        'entity_global_id': saleGid,
        'action': 'Create',
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
      });
      final payload = {
        'globalId': saleGid,
        'idempotencyKey': idem,
        'businessGlobalId': ctx.businessGlobalId,
        'branchGlobalId': ctx.branchGlobalId,
        'deviceGlobalId': ctx.deviceGlobalId,
        'userGlobalId': ctx.userGlobalId,
        'folio': 'V-${DateTime.now().millisecondsSinceEpoch}',
        'saleDateTime': now,
        'subtotalCents': totals.subtotalCents,
        'discountCents': discountCents,
        'totalCents': totals.totalCents,
        'fifoCostCents': fifoCost,
        'grossProfitCents': totals.totalCents - fifoCost,
        'paymentMethod': paymentMethod,
        'receivedCents': receivedCents,
        'changeCents': paymentMethod == 'Cash'
            ? (receivedCents! - totals.totalCents)
            : 0,
        'lines': linePayloads,
      };
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Sale',
        'entity_global_id': saleGid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode(payload),
        'created_at': now,
      });
      return CompletedSale(saleGid, totals.totalCents, fifoCost);
    });
  }
}
