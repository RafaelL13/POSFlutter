import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class PurchaseLineInput {
  const PurchaseLineInput(
    this.productId,
    this.productGlobalId,
    this.quantity,
    this.unitCostCents,
  );
  final int productId;
  final String productGlobalId;
  final int quantity;
  final int unitCostCents;
}

final class PurchaseRepository {
  PurchaseRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _db;
  final IdGenerator _ids;
  Future<String> create({
    required int supplierId,
    required String supplierGlobalId,
    required List<PurchaseLineInput> lines,
    String? reference,
  }) async {
    if (lines.isEmpty) throw StateError('La compra no puede estar vacía.');
    if (lines.any((e) => e.quantity <= 0 || e.unitCostCents < 0)) {
      throw StateError('Cantidad/costo inválido.');
    }
    final authorization = await AuthorizationService(_db)
        .require(Capability.purchaseCreate);
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = _ids.newId();
    return _db.criticalTransaction((tx) async {
      final total = lines.fold<int>(
        0,
        (s, l) => s + l.quantity * l.unitCostCents,
      );
      final id = await tx.insert('purchases', {
        'global_id': gid,
        'supplier_id': supplierId,
        'branch_id': ctx.branchId,
        'device_id': ctx.deviceId,
        'user_id': ctx.userId,
        'purchase_date': now,
        'reference': reference,
        'total_cents': total,
        'status': 'Confirmed',
        'created_at': now,
      });
      final payloadLines = <Map<String, Object?>>[];
      for (final l in lines) {
        final detailGid = _ids.newId();
        final detailId = await tx.insert('purchase_details', {
          'global_id': detailGid,
          'purchase_id': id,
          'product_id': l.productId,
          'quantity': l.quantity,
          'unit_cost_cents': l.unitCostCents,
          'subtotal_cents': l.quantity * l.unitCostCents,
        });
        final lotGid = _ids.newId();
        await tx.insert('inventory_lots', {
          'global_id': lotGid,
          'product_id': l.productId,
          'purchase_detail_id': detailId,
          'branch_id': ctx.branchId,
          'entry_date': now,
          'initial_quantity': l.quantity,
          'available_quantity': l.quantity,
          'unit_cost_cents': l.unitCostCents,
          'created_at': now,
        });
        final stock = await tx.rawQuery(
          'SELECT COALESCE(SUM(available_quantity),0) s FROM inventory_lots WHERE product_id=? AND branch_id=?',
          [l.productId, ctx.branchId],
        );
        final after = stock.first['s'] as int;
        await tx.insert('inventory_movements', {
          'global_id': _ids.newId(),
          'product_id': l.productId,
          'branch_id': ctx.branchId,
          'movement_date': now,
          'type': 'Purchase',
          'quantity_delta': l.quantity,
          'previous_stock': after - l.quantity,
          'new_stock': after,
          'reference_global_id': gid,
          'user_id': ctx.userId,
          'device_id': ctx.deviceId,
        });
        payloadLines.add({
          'detailGlobalId': detailGid,
          'productGlobalId': l.productGlobalId,
          'quantity': l.quantity,
          'unitCostCents': l.unitCostCents,
          'subtotalCents': l.quantity * l.unitCostCents,
          'lotGlobalId': lotGid,
        });
      }
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Purchase',
        'entity_global_id': gid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': gid,
          'businessGlobalId': ctx.businessGlobalId,
          'supplierGlobalId': supplierGlobalId,
          'branchGlobalId': ctx.branchGlobalId,
          'deviceGlobalId': ctx.deviceGlobalId,
          'userGlobalId': ctx.userGlobalId,
          'date': now,
          'reference': reference,
          'totalCents': total,
          'lines': payloadLines,
        }),
        'created_at': now,
      });
      return gid;
    });
  }
}
