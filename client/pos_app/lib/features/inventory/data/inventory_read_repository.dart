import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';

final class InventoryReadRepository {
  InventoryReadRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, Object?>>> availability() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryAvailabilityRead);
    final context = authorization.context!;
    final database = await _db.open();
    return database.rawQuery(
      '''SELECT p.id, p.name, COALESCE(SUM(l.available_quantity), 0) AS stock
         FROM products p LEFT JOIN inventory_lots l
           ON l.product_id = p.id AND l.branch_id = ? AND l.active = 1
         WHERE p.business_id = ? GROUP BY p.id, p.name ORDER BY p.name''',
      [context.branchId, context.businessId],
    );
  }

  Future<List<Map<String, Object?>>> lots({int? productId}) async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryLotsRead);
    final context = authorization.context!;
    final columns = <String>[
      'id',
      'global_id',
      'product_id',
      'entry_date',
      'initial_quantity',
      'available_quantity',
      'active',
    ];
    if (authorization.can(Capability.viewFifoHistoricalCost)) {
      columns.add('unit_cost_cents');
    }
    final database = await _db.open();
    return database.query(
      'inventory_lots',
      columns: columns,
      where: 'branch_id = ?${productId == null ? '' : ' AND product_id = ?'}',
      whereArgs: [context.branchId, ?productId],
      orderBy: 'entry_date, id',
    );
  }

  Future<int> inventoryValueCents() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.viewInventoryValue);
    final context = authorization.context!;
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT COALESCE(SUM(available_quantity * unit_cost_cents), 0) AS value
         FROM inventory_lots WHERE branch_id = ? AND active = 1''',
      [context.branchId],
    );
    return rows.single['value']! as int;
  }

  Future<int> totalAvailableUnits() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.inventoryAvailabilityRead);
    final context = authorization.context!;
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT COALESCE(SUM(available_quantity), 0) AS units
         FROM inventory_lots WHERE branch_id = ? AND active = 1''',
      [context.branchId],
    );
    return rows.single['units']! as int;
  }
}
