import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/catalog_import/data/catalog_import_csv.dart';

enum ExistingCatalogPolicy { skip, updateCatalogData }

final class InitialInventoryRepository {
  InitialInventoryRepository(this._database, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _database;
  final IdGenerator _ids;
  Future<String> import({
    required CatalogImportPreview preview,
    required ExistingCatalogPolicy policy,
    String? sourceName,
  }) async {
    if (!preview.isValid) {
      throw StateError('Corrige todos los errores antes de importar.');
    }
    final effective = await AuthorizationService(_database).load();
    effective.require(Capability.productWrite);
    effective.require(Capability.categoryWrite);
    effective.require(Capability.supplierWrite);
    effective.require(Capability.initialInventoryImport);
    final ctx = effective.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final importGid = _ids.newId();
    return _database.criticalTransaction((tx) async {
      final existingImport = await tx.query(
        'initial_inventory_imports',
        columns: ['global_id'],
        where: 'business_id=? AND branch_id=? AND source_fingerprint=?',
        whereArgs: [ctx.businessId, ctx.branchId, preview.fingerprint],
        limit: 1,
      );
      if (existingImport.isNotEmpty) {
        return existingImport.single['global_id']! as String;
      }
      final prepared = <Map<String, Object?>>[];
      for (final row in preview.rows) {
        final products = await tx.query(
          'products',
          where: 'business_id=? AND code=? COLLATE NOCASE',
          whereArgs: [ctx.businessId, row.sku],
          limit: 1,
        );
        if (products.isNotEmpty) {
          final product = products.single;
          final productId = product['id']! as int;
          if (row.quantity > 0) {
            final historic = await tx.rawQuery(
              '''
              SELECT 1
              FROM (
                SELECT 1
                FROM inventory_lots
                WHERE product_id=? AND branch_id=?

                UNION ALL

                SELECT 1
                FROM inventory_movements
                WHERE product_id=? AND branch_id=?
              )
              LIMIT 1
              ''',
              [productId, ctx.branchId, productId, ctx.branchId],
            );

            if (historic.isNotEmpty) {
              throw StateError(
                'El producto ${row.sku} ya tiene inventario histórico en esta sucursal; usa un ajuste o compra.',
              );
            }
          }
          if (policy == ExistingCatalogPolicy.updateCatalogData) {
            await tx.update(
              'products',
              {
                'name': row.name,
                'sale_price_cents': row.priceCents,
                'updated_at': now,
              },
              where: 'id=?',
              whereArgs: [productId],
            );
          }
          prepared.add({
            'productId': productId,
            'productGlobalId': product['global_id'],
            'row': row,
            'new': false,
          });
          continue;
        }
        final category = await _category(
          tx,
          ctx.businessId,
          ctx.businessGlobalId,
          row.category,
          now,
        );
        if (row.supplier.isNotEmpty) {
          await _supplier(
            tx,
            ctx.businessId,
            ctx.businessGlobalId,
            row.supplier,
            now,
          );
        }
        final productGid = _ids.newId();
        final productId = await tx.insert('products', {
          'global_id': productGid,
          'business_id': ctx.businessId,
          'code': row.sku,
          'name': row.name,
          'category_id': category['id'],
          'presentation': 'Piece',
          'sale_price_cents': row.priceCents,
          'minimum_stock': 0,
          'active': 1,
          'created_at': now,
          'updated_at': now,
        });
        await _queue(tx, 'Product', productGid, {
          'globalId': productGid,
          'businessGlobalId': ctx.businessGlobalId,
          'categoryGlobalId': category['global_id'],
          'code': row.sku,
          'name': row.name,
          'presentation': 'Piece',
          'salePriceCents': row.priceCents,
          'minimumStock': 0,
          'active': true,
          'serverVersion': 0,
          'updatedAt': now,
        }, now);
        prepared.add({
          'productId': productId,
          'productGlobalId': productGid,
          'row': row,
          'new': true,
        });
      }
      final stocked = prepared
          .where((x) => (x['row'] as CatalogImportRow).quantity > 0)
          .toList();
      if (stocked.isEmpty) return importGid;
      final importId = await tx.insert('initial_inventory_imports', {
        'global_id': importGid,
        'business_id': ctx.businessId,
        'branch_id': ctx.branchId,
        'device_id': ctx.deviceId,
        'user_id': ctx.userId,
        'source_fingerprint': preview.fingerprint,
        'source_name': sourceName,
        'valid_rows': stocked.length,
        'total_units': stocked.fold<int>(
          0,
          (s, x) => s + (x['row'] as CatalogImportRow).quantity,
        ),
        'created_at': now,
      });
      final lines = <Map<String, Object?>>[];
      for (final item in stocked) {
        final row = item['row'] as CatalogImportRow;
        final lotGid = _ids.newId();
        final lineGid = _ids.newId();
        final lotId = await tx.insert('inventory_lots', {
          'global_id': lotGid,
          'product_id': item['productId'],
          'branch_id': ctx.branchId,
          'entry_date': now,
          'initial_quantity': row.quantity,
          'available_quantity': row.quantity,
          'unit_cost_cents': row.costCents,
          'active': 1,
          'created_at': now,
        });
        await tx.insert('initial_inventory_lines', {
          'global_id': lineGid,
          'import_id': importId,
          'product_id': item['productId'],
          'inventory_lot_id': lotId,
          'quantity': row.quantity,
          'unit_cost_cents': row.costCents,
        });
        await tx.insert('inventory_movements', {
          'global_id': _ids.newId(),
          'product_id': item['productId'],
          'branch_id': ctx.branchId,
          'movement_date': now,
          'type': 'InitialInventory',
          'quantity_delta': row.quantity,
          'previous_stock': 0,
          'new_stock': row.quantity,
          'reference_global_id': importGid,
          'user_id': ctx.userId,
          'device_id': ctx.deviceId,
        });
        lines.add({
          'globalId': lineGid,
          'productGlobalId': item['productGlobalId'],
          'lotGlobalId': lotGid,
          'quantity': row.quantity,
          'unitCostCents': row.costCents,
        });
      }
      await tx.insert('audit_logs', {
        'global_id': _ids.newId(),
        'entity_type': 'InitialInventory',
        'entity_global_id': importGid,
        'action': 'Create',
        'user_id': ctx.userId,
        'device_id': ctx.deviceId,
        'created_at': now,
        'details_json': jsonEncode({
          'fingerprint': preview.fingerprint,
          'rows': stocked.length,
        }),
      });
      await _queue(tx, 'InitialInventory', importGid, {
        'globalId': importGid,
        'businessGlobalId': ctx.businessGlobalId,
        'branchGlobalId': ctx.branchGlobalId,
        'deviceGlobalId': ctx.deviceGlobalId,
        'userGlobalId': ctx.userGlobalId,
        'sourceFingerprint': preview.fingerprint,
        'sourceName': sourceName,
        'createdAt': now,
        'lines': lines,
      }, now);
      return importGid;
    });
  }

  Future<Map<String, Object?>> _category(
    dynamic tx,
    int businessId,
    String businessGlobalId,
    String name,
    String now,
  ) async {
    final found = await tx.query(
      'categories',
      where: 'business_id=? AND name=?',
      whereArgs: [businessId, name],
      limit: 1,
    );
    if (found.isNotEmpty) return found.single;
    final gid = _ids.newId();
    final id = await tx.insert('categories', {
      'global_id': gid,
      'business_id': businessId,
      'name': name,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await _queue(tx, 'Category', gid, {
      'globalId': gid,
      'businessGlobalId': businessGlobalId,
      'name': name,
      'description': null,
      'active': true,
      'updatedAt': now,
      'serverVersion': 0,
    }, now);
    return {'id': id, 'global_id': gid};
  }

  Future<void> _supplier(
    dynamic tx,
    int businessId,
    String businessGlobalId,
    String name,
    String now,
  ) async {
    final found = await tx.query(
      'suppliers',
      where: 'business_id=? AND name=?',
      whereArgs: [businessId, name],
      limit: 1,
    );
    if (found.isNotEmpty) return;
    final gid = _ids.newId();
    await tx.insert('suppliers', {
      'global_id': gid,
      'business_id': businessId,
      'name': name,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await _queue(tx, 'Supplier', gid, {
      'globalId': gid,
      'businessGlobalId': businessGlobalId,
      'name': name,
      'contactName': null,
      'phone': null,
      'email': null,
      'address': null,
      'notes': null,
      'active': true,
      'updatedAt': now,
      'serverVersion': 0,
    }, now);
  }

  Future<void> _queue(
    dynamic tx,
    String type,
    String entity,
    Map<String, Object?> payload,
    String now,
  ) async {
    await tx.insert('sync_queue', {
      'global_id': _ids.newId(),
      'entity_type': type,
      'entity_global_id': entity,
      'operation': 'Create',
      'payload_version': 1,
      'payload_json': jsonEncode(payload),
      'created_at': now,
    });
  }
}
