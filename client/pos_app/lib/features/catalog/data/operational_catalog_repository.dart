import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';

final class CatalogOption {
  const CatalogOption({
    required this.id,
    required this.globalId,
    required this.name,
    this.code,
  });
  final int id;
  final String globalId;
  final String name;
  final String? code;
}

final class ProductOption {
  const ProductOption({
    required this.id,
    required this.globalId,
    required this.code,
    required this.name,
    required this.priceCents,
    required this.stock,
    required this.active,
    this.barcode,
    this.categoryName,
  });
  final int id;
  final String globalId;
  final String code;
  final String name;
  final String? barcode;
  final String? categoryName;
  final int priceCents;
  final int stock;
  final bool active;

  bool matches(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query) ||
        code.toLowerCase().contains(query) ||
        (barcode?.toLowerCase().contains(query) ?? false);
  }
}

final class ProductOverview {
  const ProductOverview({
    required this.id,
    required this.code,
    required this.name,
    required this.salePriceCents,
    required this.minimumStock,
    required this.active,
    this.stock,
  });
  final int id;
  final String code;
  final String name;
  final int salePriceCents;
  final int minimumStock;
  final bool active;
  final int? stock;
}

final class OperationalCatalogRepository {
  OperationalCatalogRepository(this._db);
  final AppDatabase _db;

  Future<List<CatalogOption>> suppliers() async {
    final auth = await AuthorizationService(_db)
        .require(Capability.supplierRead);
    final database = await _db.open();
    final rows = await database.query(
      'suppliers',
      columns: ['id', 'global_id', 'name'],
      where: 'business_id = ? AND active = 1',
      whereArgs: [auth.context!.businessId],
      orderBy: 'name',
    );
    return rows
        .map(
          (row) => CatalogOption(
            id: row['id']! as int,
            globalId: row['global_id']! as String,
            name: row['name']! as String,
          ),
        )
        .toList();
  }

  Future<List<ProductOption>> products() async {
    final auth = await AuthorizationService(_db)
        .require(Capability.productRead);
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT p.id,p.global_id,p.code,p.name,p.barcode,p.sale_price_cents,p.active,
                c.name category_name,
                COALESCE(SUM(CASE WHEN l.active=1 THEN l.available_quantity ELSE 0 END),0) stock
         FROM products p
         LEFT JOIN categories c ON c.id=p.category_id
         LEFT JOIN inventory_lots l ON l.product_id=p.id AND l.branch_id=?
         WHERE p.business_id=?
         GROUP BY p.id,p.global_id,p.code,p.name,p.barcode,p.sale_price_cents,p.active,c.name
         ORDER BY p.active DESC,p.name,p.code''',
      [auth.context!.branchId, auth.context!.businessId],
    );
    return rows
        .map(
          (row) => ProductOption(
            id: row['id']! as int,
            globalId: row['global_id']! as String,
            code: row['code']! as String,
            name: row['name']! as String,
            barcode: row['barcode'] as String?,
            categoryName: row['category_name'] as String?,
            priceCents: row['sale_price_cents']! as int,
            stock: row['stock']! as int,
            active: row['active'] == 1,
          ),
        )
        .toList();
  }

  Future<List<ProductOverview>> productOverview() async {
    final auth = await AuthorizationService(_db)
        .require(Capability.productRead);
    final context = auth.context!;
    final database = await _db.open();
    final hasStockAccess = auth.can(Capability.inventoryAvailabilityRead);
    final rows = hasStockAccess
        ? await database.rawQuery(
            '''SELECT p.id,p.code,p.name,p.sale_price_cents,p.minimum_stock,p.active,
               COALESCE(SUM(CASE WHEN l.active=1 THEN l.available_quantity ELSE 0 END),0) stock
             FROM products p LEFT JOIN inventory_lots l ON l.product_id=p.id AND l.branch_id=?
             WHERE p.business_id=? GROUP BY p.id,p.code,p.name,p.sale_price_cents,p.minimum_stock,p.active ORDER BY p.name''',
            [context.branchId, context.businessId],
          )
        : await database.query(
            'products',
            columns: [
              'id',
              'code',
              'name',
              'sale_price_cents',
              'minimum_stock',
              'active',
            ],
            where: 'business_id = ?',
            whereArgs: [context.businessId],
            orderBy: 'name',
          );
    return rows
        .map(
          (row) => ProductOverview(
            id: row['id']! as int,
            code: row['code']! as String,
            name: row['name']! as String,
            salePriceCents: row['sale_price_cents']! as int,
            minimumStock: row['minimum_stock']! as int,
            active: row['active'] == 1,
            stock: row['stock'] as int?,
          ),
        )
        .toList();
  }
}
