import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/sync/web_sale_inventory_v1.dart';

/// Applied inside the same transaction as the pull cursor.
/// Strict fail-closed reconciliation: no negative stock, no lost local sales.
final class WebSaleInventoryApplier {
  WebSaleInventoryApplier._();

  static Future<void> apply(
    Transaction tx, {
    required Map<String, Object?> payload,
    required String eventGlobalId,
    required String businessGlobalId,
    required String branchGlobalId,
    required int branchId,
    required int userId,
    required int deviceId,
    required String changedAt,
  }) async {
    final data = WebSaleInventoryV1.validate(
      payload,
      businessGlobalId: businessGlobalId,
      branchGlobalId: branchGlobalId,
    );
    if ((data['globalId'] as String).toLowerCase() !=
        eventGlobalId.toLowerCase()) {
      throw StateError('Web sale event identity mismatch.');
    }

    final lines = data['lines'] as List;
    var allocations = 0;
    for (final raw in lines) {
      allocations += (Map<String, Object?>.from(raw as Map)['lots'] as List).length;
    }

    // Same sale can be replayed, but an incomplete record must never
    // be acknowledged as successfully applied.
    final existing = await tx.query(
      'inventory_movements',
      columns: ['id'],
      where: 'type=? AND reference_global_id=? AND branch_id=?',
      whereArgs: ['WebSaleInventory', eventGlobalId, branchId],
    );
    if (existing.isNotEmpty) {
      if (existing.length != allocations) {
        throw StateError('Incomplete previous web sale reconciliation.');
      }
      return;
    }

    // Conservative offline-first gate. Local unsynced inventory-changing
    // operations must go to the server before applying an inventory snapshot.
    final pending = await tx.query(
      'sync_queue',
      columns: ['id'],
      where: "status <> 'Synced' AND entity_type IN ('Sale','Purchase','InventoryAdjustment','StockAdjustment','CentralTransferIn')",
      limit: 1,
    );
    if (pending.isNotEmpty) {
      throw StateError('Pending local inventory operations; push before pull.');
    }

    final updates = <({int productId, int lotId, int taken})>[];
    for (final raw in lines) {
      final line = Map<String, Object?>.from(raw as Map);
      final productGlobalId = line['productGlobalId'] as String;
      final products = await tx.query(
        'products',
        columns: ['id'],
        where: 'global_id=? AND business_id=? AND active=1',
        whereArgs: [productGlobalId, await _businessId(tx, businessGlobalId)],
        limit: 1,
      );
      if (products.length != 1) {
        throw StateError('Unknown product in web sale.');
      }
      final productId = products.single['id'] as int;
      for (final rawLot in line['lots'] as List) {
        final lot = Map<String, Object?>.from(rawLot as Map);
        final lots = await tx.query(
          'inventory_lots',
          columns: ['id', 'available_quantity'],
          where: 'global_id=? AND product_id=? AND branch_id=? AND active=1',
          whereArgs: [lot['lotGlobalId'], productId, branchId],
          limit: 1,
        );
        if (lots.length != 1 ||
            (lots.single['available_quantity'] as int) < (lot['quantity'] as int)) {
          throw StateError('Missing or insufficient local FIFO lot; reconciliation blocked.');
        }
        updates.add((
          productId: productId,
          lotId: lots.single['id'] as int,
          taken: lot['quantity'] as int,
        ));
      }
    }

    for (final update in updates) {
      final before = (await tx.rawQuery(
        'SELECT COALESCE(SUM(available_quantity),0) s FROM inventory_lots WHERE product_id=? AND branch_id=? AND active=1',
        [update.productId, branchId],
      )).single['s'] as int;
      final count = await tx.rawUpdate(
        'UPDATE inventory_lots SET available_quantity=available_quantity-? WHERE id=? AND available_quantity>=?',
        [update.taken, update.lotId, update.taken],
      );
      if (count != 1) throw StateError('FIFO concurrent stock conflict.');
      await tx.insert('inventory_movements', {
        'global_id': _freshMovementId(),
        'product_id': update.productId,
        'branch_id': branchId,
        'movement_date': changedAt,
        'type': 'WebSaleInventory',
        'quantity_delta': -update.taken,
        'previous_stock': before,
        'new_stock': before - update.taken,
        'reference_global_id': eventGlobalId,
        'user_id': userId,
        'device_id': deviceId,
        'notes': 'Venta web sincronizada',
      });
    }
  }

  static Future<int> _businessId(Transaction tx, String globalId) async {
    final rows = await tx.query(
      'businesses',
      columns: ['id'],
      where: 'global_id=?',
      whereArgs: [globalId],
      limit: 1,
    );
    if (rows.length != 1) throw StateError('Business identity missing.');
    return rows.single['id'] as int;
  }

  static String _freshMovementId() => const UuidV7Generator().newId();
}
