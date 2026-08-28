import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

final class CatalogRepository {
  CatalogRepository(this._db, {IdGenerator? ids})
    : _ids = ids ?? const UuidV7Generator();
  final AppDatabase _db;
  final IdGenerator _ids;
  Future<String> addCategory(String name) async => _create(
    Capability.categoryWrite,
    'Category',
    'categories',
    {'name': name.trim(), 'description': null, 'active': 1},
  );
  Future<String> addSupplier(String name) async => _create(
    Capability.supplierWrite,
    'Supplier',
    'suppliers',
    {'name': name.trim(), 'active': 1},
  );
  Future<String> addProduct({
    required String code,
    required String name,
    required int salePriceCents,
    int minimumStock = 0,
  }) async => _create(Capability.productWrite, 'Product', 'products', {
    'code': code.trim(),
    'name': name.trim(),
    'presentation': 'Piece',
    'sale_price_cents': salePriceCents,
    'minimum_stock': minimumStock,
    'active': 1,
  });
  Future<String> _create(
    Capability capability,
    String type,
    String table,
    Map<String, Object?> values,
  ) async {
    final authorization = await AuthorizationService(_db).require(capability);
    final ctx = authorization.context!;
    final now = DateTime.now().toUtc().toIso8601String();
    final gid = _ids.newId();
    await _db.criticalTransaction((tx) async {
      final row = {
        'global_id': gid,
        'business_id': ctx.businessId,
        ...values,
        'created_at': now,
        'updated_at': now,
      };
      await tx.insert(table, row);
      final payload = <String, Object?>{
        'globalId': gid,
        'businessGlobalId': ctx.businessGlobalId,
        'serverVersion': 0,
        'updatedAt': now,
      };
      for (final e in values.entries) {
        final key = switch (e.key) {
          'sale_price_cents' => 'salePriceCents',
          'minimum_stock' => 'minimumStock',
          _ => e.key,
        };
        payload[key] = e.value is int && ['active'].contains(e.key)
            ? e.value == 1
            : e.value;
      }
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': type,
        'entity_global_id': gid,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode(payload),
        'created_at': now,
      });
    });
    return gid;
  }
}
