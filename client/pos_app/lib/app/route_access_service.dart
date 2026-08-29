import 'package:pos_app/app/route_authorization.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/database/app_database.dart';

final class RouteAccessService {
  RouteAccessService(this._database);

  final AppDatabase _database;

  Future<RouteAccessState> load() async {
    try {
      final db = await _database.open();
      final businessCount = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM businesses',
      );
      final configured = (businessCount.first['count'] as int) > 0;
      if (!configured) {
        return const RouteAccessState(
          configured: false,
          authenticated: false,
          capabilities: EffectiveCapabilities.denied(),
        );
      }

      final session = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['local_session_authenticated'],
        limit: 1,
      );
      final authenticated = session.isNotEmpty && session.first['value'] == '1';
      if (!authenticated) {
        return const RouteAccessState(
          configured: true,
          authenticated: false,
          capabilities: EffectiveCapabilities.denied(),
        );
      }

      return RouteAccessState(
        configured: true,
        authenticated: true,
        capabilities: await AuthorizationService(_database).load(),
      );
    } on Object {
      return const RouteAccessState(
        configured: true,
        authenticated: false,
        capabilities: EffectiveCapabilities.denied(),
      );
    }
  }
}
