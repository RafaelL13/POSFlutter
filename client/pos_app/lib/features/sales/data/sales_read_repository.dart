import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/role_policy.dart';
import 'package:pos_app/database/app_database.dart';

final class SalesReadRepository {
  SalesReadRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, Object?>>> list() async {
    final authorization = await AuthorizationService(_db)
        .require(Capability.saleHistory);
    final context = authorization.context!;
    final ownOnly =
        authorization.permissionFor(Capability.saleHistory) ==
        PermissionLevel.ownOnly;
    final database = await _db.open();
    return database.rawQuery(
      '''SELECT id, folio, sale_datetime, total_cents, status, global_id
         FROM sales
         WHERE branch_id = ?${ownOnly ? ' AND user_id = ?' : ''}
         ORDER BY id DESC''',
      [context.branchId, if (ownOnly) context.userId],
    );
  }
}
