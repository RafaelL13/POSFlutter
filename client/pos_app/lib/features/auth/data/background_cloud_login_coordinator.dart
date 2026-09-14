import 'dart:async';

import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/auth/data/cloud_auth_service.dart';
import 'package:pos_app/features/auth/data/cloud_bootstrap_service.dart';
import 'package:pos_app/features/auth/data/cloud_session_guard.dart';

final class BackgroundCloudLoginCoordinator {
  BackgroundCloudLoginCoordinator(
    this._database,
    this._api, {
    CloudSessionGuard? guard,
  }) : _guard = guard ?? CloudSessionGuard.instance;

  final AppDatabase _database;
  final CloudApiClient _api;
  final CloudSessionGuard _guard;

  void start({
    required String username,
    required String password,
    required String userGlobalId,
  }) {
    final generation = _guard.beginSession();
    unawaited(
      _run(username, password, userGlobalId, generation).catchError((_) {}),
    );
  }

  Future<void> _run(
    String username,
    String password,
    String userGlobalId,
    int generation,
  ) async {
    if (!await _guard.matches(
      _database,
      generation: generation,
      userGlobalId: userGlobalId,
    )) {
      return;
    }
    await CloudBootstrapService(_database, _api).tryBootstrap(
      expectedUserGlobalId: userGlobalId,
      sessionGeneration: generation,
    );
    if (!await _guard.matches(
      _database,
      generation: generation,
      userGlobalId: userGlobalId,
    )) {
      return;
    }
    await CloudAuthService(_database, _api).tryLogin(
      username,
      password,
      expectedUserGlobalId: userGlobalId,
      sessionGeneration: generation,
    );
  }
}
