import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/sync/sync_pull.dart';

/// Applies a server-created purchase within the caller's pull transaction.
/// Never creates an outbound sync operation for a remote purchase.
final class PurchaseInventoryApplier {
  PurchaseInventoryApplier._();

  static String text(Map<String, Object?> payload, String name) {
    final value = payload[name];
    if (value is! String || value.trim().isEmpty) {
      throw StateError('Purchase: invalid $name.');
    }
    return value.trim();
  }

  static int number(Map<String, Object?> payload, String name, {bool zero = false}) {
    final value = payload[name];
    if (value is! int || (zero ? value < 0 : value <= 0)) {
      throw StateError('Purchase: invalid $name.');
    }
    return value;
  }

  static Future<int> linkedId(Transaction tx, String table, String gid,
      String businessIdColumn, int businessId) async {
    final rows = await tx.query(table,
      columns: ['id'],
      where: 'global_id = ? AND $businessIdColumn = ?',
      whereArgs: [gid, businessId], limit: 1);
    if (rows.length != 1) throw StateError('Purchase: missing $table identity.');
    return rows.single['id']! as int;
  }

  static Future<void> apply(Transaction tx, SyncPullChange change,
      LocalAppContext context) async {
    if (change.entityType != 'Purchase' || change.version != 1 ||
        change.operation != 'Create') {
      throw StateError('Unsupported remote Purchase contract.');
    }
    final payload = change.payload;
    if (text(payload, 'globalId') != change.entityGlobalId ||
        text(payload, 'businessGlobalId') != context.businessGlobalId) {
      throw StateError('Purchase: identity/tenant mismatch.');
    }
    if (text(payload, 'branchGlobalId') != context.branchGlobalId) {
      // A different branch's stock must never be imported into this branch.
      return;
    }
    final supplierGlobalId = text(payload, 'supplierGlobalId');
    final userGlobalId = text(payload, 'userGlobalId');
    final deviceGlobalId = text(payload, 'deviceGlobalId');
    final date = DateTime.tryParse(text(payload, 'date'))?.toUtc();
    if (date == null) throw StateError('Purchase: invalid date.');
    final total = number(payload, 'totalCents', zero: true);
    final rawLines = payload['lines'];
    if (rawLines is! List || rawLines.isEmpty) {
      throw StateError('Purchase: lines are required.');
    }
    final seenLots = <String>{};
    final seenDetails = <String>{};
    final lines = <({String detail, String lot, int product, int quantity,
      int cost, int subtotal})>[];
    var computed = 0;
    for (final raw in rawLines) {
      if (raw is! Map) throw StateError('Purchase: invalid line.');
      final line = Map<String, Object?>.from(raw);
      final detail = text(line, 'detailGlobalId');
      final lot = text(line, 'lotGlobalId');
      if (!seenLots.add(lot) || !seenDetails.add(detail)) {
        throw StateError('Purchase: repeated detail or lot.');
      }
      final quantity = number(line, 'quantity');
      final cost = number(line, 'unitCostCents', zero: true);
      final subtotal = number(line, 'subtotalCents', zero: true);
      if (quantity * cost != subtotal) throw StateError('Purchase: bad subtotal.');
      computed += subtotal;
      final product = await linkedId(tx, 'products',
          text(line, 'productGlobalId'), 'business_id', context.businessId);
      lines.add((detail: detail, lot: lot, product: product,
        quantity: quantity, cost: cost, subtotal: subtotal));
    }
    if (computed != total) throw StateError('Purchase: bad total.');

    final previous = await tx.query('purchases',
      columns: ['id', 'total_cents'], where: 'global_id = ?',
      whereArgs: [change.entityGlobalId], limit: 1);
    if (previous.isNotEmpty) {
      // Existing local/offline purchase or an already applied remote purchase.
      // Verify immutable identifiers and amounts rather than duplicating FIFO.
      final purchaseId = previous.single['id']! as int;
      if (previous.single['total_cents'] != total) {
        throw StateError('Purchase: existing total conflict.');
      }
      final details = await tx.query('purchase_details',
        columns: ['global_id','product_id','quantity','unit_cost_cents','subtotal_cents','id'],
        where: 'purchase_id = ?', whereArgs: [purchaseId]);
      if (details.length != lines.length) {
        throw StateError('Purchase: existing line count conflict.');
      }
      for (final line in lines) {
        final matched = details.where((d) => d['global_id'] == line.detail).toList();
        if (matched.length != 1 || matched.single['product_id'] != line.product ||
            matched.single['quantity'] != line.quantity ||
            matched.single['unit_cost_cents'] != line.cost ||
            matched.single['subtotal_cents'] != line.subtotal) {
          throw StateError('Purchase: existing line conflict.');
        }
        final lotRows = await tx.query('inventory_lots',
          columns: ['purchase_detail_id','product_id','initial_quantity','unit_cost_cents'],
          where: 'global_id = ?', whereArgs: [line.lot], limit: 1);
        if (lotRows.length != 1 ||
            lotRows.single['purchase_detail_id'] != matched.single['id'] ||
            lotRows.single['product_id'] != line.product ||
            lotRows.single['initial_quantity'] != line.quantity ||
            lotRows.single['unit_cost_cents'] != line.cost) {
          throw StateError('Purchase: existing lot conflict.');
        }
      }
      return;
    }

    final supplierId = await linkedId(tx, 'suppliers', supplierGlobalId,
      'business_id', context.businessId);
    final userId = await linkedId(tx, 'users', userGlobalId,
      'business_id', context.businessId);
    final deviceRows = await tx.rawQuery("""
      SELECT d.id FROM devices d JOIN branches b ON d.branch_id=b.id
      WHERE d.global_id=? AND b.business_id=? AND b.id=? LIMIT 1
      """, [deviceGlobalId, context.businessId, context.branchId]);
    if (deviceRows.length != 1) throw StateError('Purchase: missing device.');
    final deviceId = deviceRows.single['id']! as int;
    final createdAt = change.changedAt.toUtc().toIso8601String();
    final purchaseId = await tx.insert('purchases', {
      'global_id': change.entityGlobalId,
      'supplier_id': supplierId,
      'branch_id': context.branchId,
      'device_id': deviceId,
      'user_id': userId,
      'purchase_date': date.toIso8601String(),
      'reference': payload['reference']?.toString(),
      'notes': payload['notes']?.toString(),
      'total_cents': total,
      'status': 'Confirmed',
      'created_at': createdAt,
    });
    final stocks = <int, int>{};
    for (final line in lines) {
      final collision = await tx.query('inventory_lots',
        columns: ['id'], where: 'global_id = ?',
        whereArgs: [line.lot], limit: 1);
      if (collision.isNotEmpty) throw StateError('Purchase: lot GUID collision.');
      final before = stocks[line.product] ??
        (await tx.rawQuery("""
          SELECT COALESCE(SUM(available_quantity),0) n FROM inventory_lots
          WHERE product_id=? AND branch_id=? AND active=1
          """, [line.product, context.branchId])).single['n']! as int;
      final detailId = await tx.insert('purchase_details', {
        'global_id': line.detail,
        'purchase_id': purchaseId,
        'product_id': line.product,
        'quantity': line.quantity,
        'unit_cost_cents': line.cost,
        'subtotal_cents': line.subtotal,
      });
      await tx.insert('inventory_lots', {
        'global_id': line.lot,
        'product_id': line.product,
        'purchase_detail_id': detailId,
        'branch_id': context.branchId,
        'entry_date': date.toIso8601String(),
        'initial_quantity': line.quantity,
        'available_quantity': line.quantity,
        'unit_cost_cents': line.cost,
        'active': 1,
        'created_at': createdAt,
      });
      final after = before + line.quantity;
      stocks[line.product] = after;
      // Deterministic identity protects against duplicate movement creation.
      await tx.insert('inventory_movements', {
        'global_id': '${change.entityGlobalId}:${line.detail}',
        'product_id': line.product,
        'branch_id': context.branchId,
        'movement_date': date.toIso8601String(),
        'type': 'Purchase',
        'quantity_delta': line.quantity,
        'previous_stock': before,
        'new_stock': after,
        'reference_global_id': change.entityGlobalId,
        'user_id': userId,
        'device_id': deviceId,
        'notes': 'Web purchase sync',
      });
    }
  }
}
