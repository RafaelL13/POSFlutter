import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/database/app_database.dart';

final class PosProduct {
  const PosProduct({
    required this.id,
    required this.globalId,
    required this.code,
    required this.name,
    required this.priceCents,
    required this.stock,
    this.categoryId,
  });
  final int id;
  final String globalId;
  final String code;
  final String name;
  final int priceCents;
  final int stock;
  final int? categoryId;
}

final class PosCategory {
  const PosCategory(this.id, this.name);
  final int id;
  final String name;
}

final class PosBootstrap {
  const PosBootstrap({
    required this.products,
    required this.categories,
    required this.capabilities,
    required this.branchName,
    required this.userName,
    required this.cashOpen,
  });
  final List<PosProduct> products;
  final List<PosCategory> categories;
  final EffectiveCapabilities capabilities;
  final String branchName;
  final String userName;
  final bool cashOpen;
}

final class PosCatalogRepository {
  PosCatalogRepository(this._database);
  final AppDatabase _database;

  Future<PosBootstrap> load() async {
    final capabilities = await AuthorizationService(_database).load();
    final context = capabilities.context;
    if (context == null) throw StateError('No hay una sesión local válida.');
    final db = await _database.open();
    final identity = await db.rawQuery(
      '''
      SELECT b.name branch_name, u.name user_name
      FROM branches b JOIN users u ON u.business_id=b.business_id
      WHERE b.id=? AND u.id=? LIMIT 1
    ''',
      [context.branchId, context.userId],
    );
    final rows = await db.rawQuery(
      '''
      SELECT p.id,p.global_id,p.code,p.name,p.sale_price_cents,p.category_id,
             COALESCE(SUM(CASE WHEN l.active=1 THEN l.available_quantity ELSE 0 END),0) stock
      FROM products p
      LEFT JOIN inventory_lots l ON l.product_id=p.id AND l.branch_id=?
      WHERE p.active=1 AND p.business_id=?
      GROUP BY p.id,p.global_id,p.code,p.name,p.sale_price_cents,p.category_id
      ORDER BY p.name LIMIT 500
    ''',
      [context.branchId, context.businessId],
    );
    final categories = await db.rawQuery(
      'SELECT id,name FROM categories WHERE business_id=? AND active=1 ORDER BY name',
      [context.businessId],
    );
    final cash = await db.query(
      'cash_sessions',
      columns: ['id'],
      where: "device_id=? AND status='Open'",
      whereArgs: [context.deviceId],
      limit: 1,
    );
    return PosBootstrap(
      products: [
        for (final row in rows)
          PosProduct(
            id: row['id'] as int,
            globalId: row['global_id'] as String,
            code: row['code'] as String,
            name: row['name'] as String,
            priceCents: row['sale_price_cents'] as int,
            stock: row['stock'] as int,
            categoryId: row['category_id'] as int?,
          ),
      ],
      categories: [
        for (final row in categories)
          PosCategory(row['id'] as int, row['name'] as String),
      ],
      capabilities: capabilities,
      branchName: identity.first['branch_name'] as String,
      userName: identity.first['user_name'] as String,
      cashOpen: cash.isNotEmpty,
    );
  }
}
