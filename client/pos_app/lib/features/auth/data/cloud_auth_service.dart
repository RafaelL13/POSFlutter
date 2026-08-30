import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/core/storage/secure_token_store.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pos_app/sync/sync_repository.dart';

final class CloudAuthService {
  CloudAuthService(this._db, this._api, {SecureTokenStore? tokens})
    : _tokens = tokens ?? const SecureTokenStore();
  final AppDatabase _db;
  final CloudApiClient _api;
  final SecureTokenStore _tokens;
  Future<bool> login(String username, String password) async {
    try {
      final ctx = await LocalAppContext.load(_db);
      final j = await _api.post('/api/auth/login', {
        'businessGlobalId': ctx.businessGlobalId,
        'deviceGlobalId': ctx.deviceGlobalId,
        'username': username,
        'password': password,
      }, authenticated: false);
      final access = j['accessToken']?.toString(),
          refresh = j['refreshToken']?.toString();
      if (access == null || refresh == null) return false;
      await _tokens.save(accessToken: access, refreshToken: refresh);
      final db = await _db.open();
      await db.insert('app_settings', {
        'key': 'local_session_authenticated',
        'value': '1',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncRepository(database: _db).releaseAuthenticationRequired();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> tryLogin(String username, String password) async {
    await login(username, password);
  }
}
