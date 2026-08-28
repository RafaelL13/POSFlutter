import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';

final class PurchaseReadRepository {
  PurchaseReadRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, Object?>>> list() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.purchaseRead);
    final context = authorization.context!;
    final columns = <String>['id', 'global_id', 'purchase_date', 'status'];
    if (authorization.can(Capability.viewPurchaseCost)) {
      columns.add('total_cents');
    }
    final database = await _db.open();
    return database.query(
      'purchases',
      columns: columns,
      where: 'branch_id = ?',
      whereArgs: [context.branchId],
      orderBy: 'id DESC',
    );
  }

  Future<List<Map<String, Object?>>> lines(int purchaseId) async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.purchaseRead);
    final context = authorization.context!;
    final columns = <String>['d.id', 'd.product_id', 'd.quantity'];
    if (authorization.can(Capability.viewSupplierPrice)) {
      columns.add('d.unit_cost_cents');
    }
    if (authorization.can(Capability.viewPurchaseCost)) {
      columns.add('d.subtotal_cents');
    }
    final database = await _db.open();
    return database.rawQuery(
      '''SELECT ${columns.join(', ')} FROM purchase_details d
         INNER JOIN purchases p ON p.id = d.purchase_id
         WHERE d.purchase_id = ? AND p.branch_id = ? ORDER BY d.id''',
      [purchaseId, context.branchId],
    );
  }
}
