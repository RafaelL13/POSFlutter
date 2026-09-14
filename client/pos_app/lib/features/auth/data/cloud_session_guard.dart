import 'dart:async';

import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/core/storage/secure_token_store.dart';

final class CloudSessionGuard {
  CloudSessionGuard._();

  static final CloudSessionGuard instance = CloudSessionGuard._();

  int _generation = 0;
  Future<void> _tokenMutations = Future<void>.value();

  int beginSession() => ++_generation;

  void invalidate() => _generation++;

  bool isCurrentGeneration(int generation) => generation == _generation;

  Future<bool> saveTokensIfCurrent(
    AppDatabase database,
    SecureTokenStore tokens, {
    required int generation,
    required String userGlobalId,
    required String accessToken,
    required String refreshToken,
  }) {
    final result = Completer<bool>();
    _tokenMutations = _tokenMutations.then((_) async {
      if (!await matches(
        database,
        generation: generation,
        userGlobalId: userGlobalId,
      )) {
        result.complete(false);
        return;
      }
      await tokens.save(accessToken: accessToken, refreshToken: refreshToken);
      result.complete(true);
    });
    return result.future;
  }

  Future<void> clearTokens(SecureTokenStore tokens) {
    _tokenMutations = _tokenMutations.then((_) => tokens.clear());
    return _tokenMutations;
  }

  Future<bool> matches(
    AppDatabase database, {
    required int generation,
    required String userGlobalId,
  }) async {
    if (!isCurrentGeneration(generation)) {
      return false;
    }
    final db = await database.open();
    final rows = await db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?)',
      whereArgs: ['local_session_authenticated', 'active_user_global_id'],
    );
    final settings = <String, String?>{
      for (final row in rows) row['key'] as String: row['value'] as String?,
    };
    return isCurrentGeneration(generation) &&
        settings['local_session_authenticated'] == '1' &&
        settings['active_user_global_id'] == userGlobalId;
  }
}
