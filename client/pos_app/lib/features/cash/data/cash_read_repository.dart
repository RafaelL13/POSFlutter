import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/database/app_database.dart';

final class CashReadRepository {
  CashReadRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, Object?>>> sessions() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashRead);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.cashRead) ==
        PermissionLevel.ownOnly;
    final columns = <String>[
      'id',
      'opened_at',
      'opening_balance_cents',
      'status',
    ];
    if (authorization.can(Capability.reportsFinancial)) {
      columns.add('difference_cents');
    }
    final database = await _db.open();
    return database.query(
      'cash_sessions',
      columns: columns,
      where: 'branch_id = ?${ownOnly ? ' AND user_id = ?' : ''}',
      whereArgs: [context.branchId, if (ownOnly) context.userId],
      orderBy: 'id DESC',
    );
  }
}
