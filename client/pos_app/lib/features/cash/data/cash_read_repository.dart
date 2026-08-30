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

  Future<bool> hasOpenSession() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.cashRead);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.cashRead) ==
        PermissionLevel.ownOnly;
    final database = await _db.open();
    final rows = await database.rawQuery(
      '''SELECT EXISTS(
           SELECT 1 FROM cash_sessions
           WHERE branch_id = ? AND device_id = ? AND status = 'Open'
           ${ownOnly ? 'AND user_id = ?' : ''}
         ) AS is_open''',
      [context.branchId, context.deviceId, if (ownOnly) context.userId],
    );
    return rows.single['is_open'] == 1;
  }
}
