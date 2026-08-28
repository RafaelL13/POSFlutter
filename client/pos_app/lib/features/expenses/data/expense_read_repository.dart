import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';

final class ExpenseReadRepository {
  ExpenseReadRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, Object?>>> list() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.expenseRead);
    final context = authorization.context!;
    final columns = <String>['id', 'expense_date', 'concept', 'payment_method'];
    if (authorization.can(Capability.viewExpenses)) columns.add('amount_cents');
    final database = await _db.open();
    return database.query(
      'expenses',
      columns: columns,
      where: 'branch_id = ?',
      whereArgs: [context.branchId],
      orderBy: 'id DESC',
    );
  }
}
