import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/auth/data/auth_repository.dart';
import 'package:pos_app/features/auth/data/cloud_session_guard.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('LOCAL_LOGIN_DOES_NOT_WAIT_FOR_CLOUD', (tester) async {
    final cloud = Completer<void>();
    String? destination;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LoginScreen(
            localLogin: (_, _) async =>
                const LocalAuthSession('local-user', 'Seller'),
            startBackgroundCloudLogin: (_, _, _) {
              unawaited(cloud.future);
            },
            loadAuthorizedHome: () async => '/home',
            navigateTo: (_, route) => destination = route,
          ),
        ),
      ),
    );

    await _submit(tester);
    await tester.pump();

    expect(destination, '/home');
    expect(cloud.isCompleted, isFalse);
  });

  testWidgets('CLOUD_FAILURE_DOES_NOT_BREAK_LOCAL_LOGIN', (tester) async {
    String? destination;
    Object? handledCloudError;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LoginScreen(
            localLogin: (_, _) async =>
                const LocalAuthSession('local-user', 'Seller'),
            startBackgroundCloudLogin: (_, _, _) {
              unawaited(
                Future<void>.error(StateError('offline')).catchError((error) {
                  handledCloudError = error;
                }),
              );
            },
            loadAuthorizedHome: () async => '/home',
            navigateTo: (_, route) => destination = route,
          ),
        ),
      ),
    );

    await _submit(tester);
    await tester.pump();

    expect(destination, '/home');
    expect(handledCloudError, isA<StateError>());
    expect(find.text('Credenciales incorrectas.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CLOUD_SUCCESS_UPDATES_REMOTE_STATE_LATER', (tester) async {
    final cloud = Completer<String>();
    String? remoteToken;
    String? destination;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LoginScreen(
            localLogin: (_, _) async =>
                const LocalAuthSession('local-user', 'Administrator'),
            startBackgroundCloudLogin: (_, _, _) {
              unawaited(
                cloud.future.then((token) {
                  remoteToken = token;
                }),
              );
            },
            loadAuthorizedHome: () async => '/home',
            navigateTo: (_, route) => destination = route,
          ),
        ),
      ),
    );

    await _submit(tester);
    await tester.pump();
    expect(destination, '/home');
    expect(remoteToken, isNull);

    cloud.complete('remote-token');
    await tester.pump();

    expect(remoteToken, 'remote-token');
    expect(destination, '/home');
  });

  test('LATE_CLOUD_RESULT_AFTER_LOGOUT_IS_IGNORED', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final db = await database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('app_settings', {
      'key': 'local_session_authenticated',
      'value': '1',
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'active_user_global_id',
      'value': 'user-a',
      'updated_at': now,
    });

    final guard = CloudSessionGuard.instance;
    final generation = guard.beginSession();
    final response = Completer<String>();
    String? installedToken;
    final pending = response.future.then((token) async {
      if (await guard.matches(
        database,
        generation: generation,
        userGlobalId: 'user-a',
      )) {
        installedToken = token;
      }
    });

    await AuthRepository(database, clearTokens: () async {}).logout();
    response.complete('late-token-a');
    await pending;

    expect(installedToken, isNull);
  });
}

Future<void> _submit(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Usuario *'),
    'local-user',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Contraseña *'),
    'local-password',
  );
  await tester.tap(find.text('Iniciar sesión'));
}
