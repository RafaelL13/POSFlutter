import 'dart:convert';

import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
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
    required int categoryId,
    required int salePriceCents,
    int minimumStock = 0,
    String? barcode,
  }) async {
    if (code.trim().isEmpty) {
      throw ArgumentError('El código es obligatorio.');
    }

    if (name.trim().isEmpty) {
      throw ArgumentError('El nombre es obligatorio.');
    }

    if (salePriceCents < 0) {
      throw ArgumentError('Precio inválido.');
    }

    if (minimumStock < 0) {
      throw ArgumentError('Stock mínimo inválido.');
    }

    final authorization = await AuthorizationService(_db)
        .require(Capability.productWrite);

    final ctx = authorization.context!;
    final db = await _db.open();

    final categories = await db.query(
      'categories',
      columns: ['id', 'global_id'],
      where: 'id = ? AND business_id = ? AND active = 1',
      whereArgs: [categoryId, ctx.businessId],
      limit: 1,
    );

    if (categories.isEmpty) {
      throw StateError('La categoría seleccionada no existe o está inactiva.');
    }

    final categoryGlobalId = categories.first['global_id']! as String;
    final now = DateTime.now().toUtc().toIso8601String();
    final productGlobalId = _ids.newId();

    await _db.criticalTransaction((tx) async {
      await tx.insert('products', {
        'global_id': productGlobalId,
        'business_id': ctx.businessId,
        'code': code.trim(),
        'barcode': barcode?.trim().isEmpty ?? true ? null : barcode!.trim(),
        'name': name.trim(),
        'category_id': categoryId,
        'presentation': 'Piece',
        'sale_price_cents': salePriceCents,
        'minimum_stock': minimumStock,
        'active': 1,
        'created_at': now,
        'updated_at': now,
      });

      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Product',
        'entity_global_id': productGlobalId,
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': productGlobalId,
          'businessGlobalId': ctx.businessGlobalId,
          'categoryGlobalId': categoryGlobalId,
          'code': code.trim(),
          'barcode': barcode?.trim().isEmpty ?? true ? null : barcode!.trim(),
          'name': name.trim(),
          'presentation': 'Piece',
          'salePriceCents': salePriceCents,
          'minimumStock': minimumStock,
          'active': true,
          'serverVersion': 0,
          'updatedAt': now,
        }),
        'created_at': now,
      });
    });

    return productGlobalId;
  }

  Future<void> updateProduct({
    required int productId,
    required String code,
    required String name,
    required int categoryId,
    required int salePriceCents,
    required int minimumStock,
    required bool active,
    String? barcode,
    SpecialAuthorizationGrant? priceAuthorizationGrant,
  }) async {
    final normalizedCode = code.trim();
    final normalizedName = name.trim();
    final normalizedBarcode = barcode?.trim();

    if (normalizedCode.isEmpty) {
      throw ArgumentError('El código es obligatorio.');
    }

    if (normalizedName.isEmpty) {
      throw ArgumentError('El nombre es obligatorio.');
    }

    if (salePriceCents < 0) {
      throw ArgumentError('Precio inválido.');
    }

    if (minimumStock < 0) {
      throw ArgumentError('Stock mínimo inválido.');
    }

    final authorization = await AuthorizationService(_db)
        .require(Capability.productWrite);

    final ctx = authorization.context!;
    final db = await _db.open();

    final products = await db.query(
      'products',
      columns: ['global_id', 'sale_price_cents', 'presentation'],
      where: 'id = ? AND business_id = ?',
      whereArgs: [productId, ctx.businessId],
      limit: 1,
    );

    if (products.isEmpty) {
      throw StateError('Producto inexistente.');
    }

    final categories = await db.query(
      'categories',
      columns: ['global_id'],
      where: 'id = ? AND business_id = ? AND active = 1',
      whereArgs: [categoryId, ctx.businessId],
      limit: 1,
    );

    if (categories.isEmpty) {
      throw StateError('La categoría seleccionada no existe o está inactiva.');
    }

    final product = products.first;
    final productGlobalId = product['global_id']! as String;
    final categoryGlobalId = categories.first['global_id']! as String;
    final presentation = (product['presentation'] as String?) ?? 'Piece';

    final oldPrice = product['sale_price_cents']! as int;
    final priceChanged = oldPrice != salePriceCents;

    final specialAuthorization = SpecialAuthorizationService(_db);

    PreparedSpecialAuthorization? preparedPriceAuthorization;

    if (priceChanged) {
      preparedPriceAuthorization = await specialAuthorization.prepare(
        effective: authorization,
        capability: Capability.productPriceChange,
        grant: priceAuthorizationGrant,
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await _db.criticalTransaction((tx) async {
      Map<String, Object?>? authorizationMetadata;

      if (preparedPriceAuthorization != null) {
        authorizationMetadata = await specialAuthorization.consumeInTransaction(
          tx,
          prepared: preparedPriceAuthorization,
          effective: authorization,
          capability: Capability.productPriceChange,
          operation: 'UpdateProductPrice',
          entityType: 'Product',
          entityGlobalId: productGlobalId,
        );
      }

      final updated = await tx.update(
        'products',
        {
          'code': normalizedCode,
          'name': normalizedName,
          'barcode': normalizedBarcode == null || normalizedBarcode.isEmpty
              ? null
              : normalizedBarcode,
          'category_id': categoryId,
          'sale_price_cents': salePriceCents,
          'minimum_stock': minimumStock,
          'active': active ? 1 : 0,
          'updated_at': now,
        },
        where: 'id = ? AND business_id = ?',
        whereArgs: [productId, ctx.businessId],
      );

      if (updated != 1) {
        throw StateError('Producto inexistente.');
      }

      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Product',
        'entity_global_id': productGlobalId,
        'operation': 'Update',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': productGlobalId,
          'businessGlobalId': ctx.businessGlobalId,
          'categoryGlobalId': categoryGlobalId,
          'code': normalizedCode,
          'barcode': normalizedBarcode == null || normalizedBarcode.isEmpty
              ? null
              : normalizedBarcode,
          'name': normalizedName,
          'presentation': presentation,
          'salePriceCents': salePriceCents,
          'minimumStock': minimumStock,
          'active': active,
          'updatedAt': now,
          'authorization': ?authorizationMetadata,
        }),
        'created_at': now,
      });
    });
  }

  Future<void> changeProductPrice({
    required int productId,
    required int salePriceCents,
    SpecialAuthorizationGrant? authorizationGrant,
  }) async {
    if (salePriceCents < 0) throw ArgumentError('Precio inválido.');
    final authorization = await AuthorizationService(_db).load();
    final specialAuthorization = SpecialAuthorizationService(_db);
    final prepared = await specialAuthorization.prepare(
      effective: authorization,
      capability: Capability.productPriceChange,
      grant: authorizationGrant,
    );
    final ctx = authorization.context!;
    final db = await _db.open();
    final products = await db.query(
      'products',
      columns: ['global_id'],
      where: 'id=? AND business_id=?',
      whereArgs: [productId, ctx.businessId],
      limit: 1,
    );
    if (products.isEmpty) throw StateError('Producto inexistente.');
    final productGlobalId = products.first['global_id'] as String;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.criticalTransaction((tx) async {
      final authorizationMetadata = await specialAuthorization
          .consumeInTransaction(
            tx,
            prepared: prepared,
            effective: authorization,
            capability: Capability.productPriceChange,
            operation: 'ChangePrice',
            entityType: 'Product',
            entityGlobalId: productGlobalId,
          );
      final updated = await tx.update(
        'products',
        {'sale_price_cents': salePriceCents, 'updated_at': now},
        where: 'id=? AND business_id=?',
        whereArgs: [productId, ctx.businessId],
      );
      if (updated != 1) throw StateError('Producto inexistente.');
      await tx.insert('sync_queue', {
        'global_id': _ids.newId(),
        'entity_type': 'Product',
        'entity_global_id': productGlobalId,
        'operation': 'Update',
        'payload_version': 1,
        'payload_json': jsonEncode({
          'globalId': productGlobalId,
          'businessGlobalId': ctx.businessGlobalId,
          'salePriceCents': salePriceCents,
          'updatedAt': now,
          'authorization': ?authorizationMetadata,
        }),
        'created_at': now,
      });
    });
  }

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
