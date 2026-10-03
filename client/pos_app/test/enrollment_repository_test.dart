import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/first_run/data/enrollment_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'PointOfSale redeem persists local identity, credential, and tokens',
    () async {
      final database = _database();
      addTearDown(database.close);
      final tokens = <String, String>{};

      final result =
          await EnrollmentRepository(
            database,
            _EnrollmentApi(_response()),
            ids: _Ids(['device-pos']),
            hashPassword: (_) async => const PasswordHash('hash', 'salt'),
            saveTokens: ({required accessToken, required refreshToken}) async {
              tokens['access'] = accessToken;
              tokens['refresh'] = refreshToken;
            },
          ).redeem(
            code: 'invitation',
            username: 'administrator',
            password: 'not-a-production-password',
            deviceName: 'POS',
          );

      final db = await database.open();
      expect(result.mode, DeviceMode.pointOfSale);
      expect(result.deviceGlobalId, 'device-pos');
      expect(result.cloudCredentialsPersisted, isTrue);
      expect(tokens, {'access': 'access-token', 'refresh': 'refresh-token'});
      expect(await _setting(db, 'local_device_global_id'), 'device-pos');
      expect(await _setting(db, 'active_user_global_id'), 'user-1');
      expect(await _setting(db, 'local_session_authenticated'), '1');
      expect(await _setting(db, 'pending_enrollment_device_global_id'), isNull);

      final device = (await db.query('devices')).single;
      expect(device['global_id'], 'device-pos');
      expect(device['mode'], 'PointOfSale');
      final user = (await db.query('users')).single;
      expect(user['password_hash'], 'hash');
      expect(user['password_salt'], 'salt');
    },
  );

  test(
    'post-redeem local failure preserves retry identity and writes no tokens',
    () async {
      final database = _database();
      addTearDown(database.close);
      var tokenWrites = 0;
      final malformed = _response(deviceGlobalId: 'device-retry')
        ..['business'] = <String, Object?>{
          'globalId': 'business-1',
          'name': null,
        };
      final repository = EnrollmentRepository(
        database,
        _EnrollmentApi(malformed),
        ids: _Ids(['device-retry']),
        hashPassword: (_) async => const PasswordHash('hash', 'salt'),
        saveTokens: ({required accessToken, required refreshToken}) async {
          tokenWrites++;
        },
      );

      await expectLater(
        repository.redeem(
          code: 'consumed-on-server',
          username: 'administrator',
          password: 'not-a-production-password',
          deviceName: 'POS',
        ),
        throwsA(isA<EnrollmentPostRedeemException>()),
      );

      final db = await database.open();
      expect(tokenWrites, 0);
      expect(await _count(db, 'businesses'), 0);
      expect(await _count(db, 'branches'), 0);
      expect(await _count(db, 'devices'), 0);
      expect(await _count(db, 'users'), 0);
      expect(
        await _setting(db, 'pending_enrollment_device_global_id'),
        'device-retry',
      );

      final recovered =
          await EnrollmentRepository(
            database,
            _EnrollmentApi(_response(deviceGlobalId: 'device-retry')),
            ids: _Ids([]),
            hashPassword: (_) async => const PasswordHash('hash', 'salt'),
            saveTokens: ({
              required accessToken,
              required refreshToken,
            }) async {},
          ).redeem(
            code: 'same-consumed-server-invitation',
            username: 'administrator',
            password: 'not-a-production-password',
            deviceName: 'POS',
          );

      expect(recovered.deviceGlobalId, 'device-retry');
      expect(await _count(db, 'devices'), 1);
    },
  );

  test(
    'recovery uses the supplied existing device identity without creating one',
    () async {
      final database = _database();
      addTearDown(database.close);

      final result =
          await EnrollmentRepository(
            database,
            _EnrollmentApi(_response(deviceGlobalId: 'device-existing')),
            ids: _Ids([]),
            hashPassword: (_) async => const PasswordHash('hash', 'salt'),
            saveTokens: ({
              required accessToken,
              required refreshToken,
            }) async {},
          ).redeem(
            code: 'recovery-invitation',
            username: 'administrator',
            password: 'not-a-production-password',
            deviceName: 'POS',
            recoveryDeviceGlobalId: 'device-existing',
          );

      expect(result.deviceGlobalId, 'device-existing');
      expect(
        await _setting(await database.open(), 'local_device_global_id'),
        'device-existing',
      );
    },
  );

  test(
    'token persistence failure does not block offline PointOfSale enrollment',
    () async {
      final database = _database();
      addTearDown(database.close);
      var clearCalled = false;

      final result =
          await EnrollmentRepository(
            database,
            _EnrollmentApi(_response(deviceGlobalId: 'device-offline')),
            ids: _Ids(['device-offline']),
            hashPassword: (_) async => const PasswordHash('hash', 'salt'),
            saveTokens: ({required accessToken, required refreshToken}) async {
              throw StateError('secure storage unavailable');
            },
            clearTokens: () async => clearCalled = true,
          ).redeem(
            code: 'invitation',
            username: 'administrator',
            password: 'not-a-production-password',
            deviceName: 'POS',
          );

      final db = await database.open();
      expect(result.cloudCredentialsPersisted, isFalse);
      expect(clearCalled, isTrue);
      expect(await _count(db, 'businesses'), 1);
      expect(await _setting(db, 'local_session_authenticated'), '1');
      expect(await _setting(db, 'pending_enrollment_device_global_id'), isNull);
    },
  );

  test('AdminReadOnly enrollment keeps cloud-only local credentials', () async {
    final database = _database();
    addTearDown(database.close);

    final result =
        await EnrollmentRepository(
          database,
          _EnrollmentApi(
            _response(deviceGlobalId: 'device-admin', mode: 'AdminReadOnly'),
          ),
          ids: _Ids(['device-admin']),
          saveTokens: ({required accessToken, required refreshToken}) async {},
        ).redeem(
          code: 'invitation',
          username: 'administrator',
          password: 'not-a-production-password',
          deviceName: 'Admin',
        );

    final user = (await (await database.open()).query('users')).single;
    expect(result.mode, DeviceMode.adminReadOnly);
    expect(user['password_hash'], 'REMOTE_ONLY');
    expect(user['password_salt'], 'REMOTE_ONLY');
  });

  test('invitation sends selected device mode', () {
    final source = File(
      'lib/features/cloud_admin/data/cloud_admin_repository.dart',
    ).readAsStringSync();

    expect(source, contains('required DeviceMode mode'));
    expect(source, contains("'mode': mode.wireValue"));
  });

  test('First Run redirects according to enrolled mode', () {
    final source = File(
      'lib/features/first_run/presentation/first_run_screen.dart',
    ).readAsStringSync();

    expect(source, contains('DeviceMode.adminReadOnly'));
    expect(source, contains("'/cloud-admin'"));
    expect(source, contains("'/dashboard'"));
  });
}

AppDatabase _database() => AppDatabase(
  factory: databaseFactoryFfi,
  databasePath: inMemoryDatabasePath,
);

Map<String, Object?> _response({
  String deviceGlobalId = 'device-pos',
  String mode = 'PointOfSale',
}) => <String, Object?>{
  'auth': <String, Object?>{
    'accessToken': 'access-token',
    'refreshToken': 'refresh-token',
  },
  'business': <String, Object?>{
    'globalId': 'business-1',
    'name': 'Business',
    'serverVersion': 1,
  },
  'branch': <String, Object?>{
    'globalId': 'branch-1',
    'name': 'Branch',
    'serverVersion': 1,
  },
  'device': <String, Object?>{
    'globalId': deviceGlobalId,
    'name': 'POS',
    'mode': mode,
    'serverVersion': 1,
  },
  'user': <String, Object?>{
    'globalId': 'user-1',
    'name': 'Administrator',
    'username': 'administrator',
    'role': 'Administrator',
    'serverVersion': 1,
  },
};

final class _EnrollmentApi implements JsonApiClient {
  _EnrollmentApi(this.response);

  final Map<String, Object?> response;

  @override
  Future<Map<String, Object?>> get(String path, {Map<String, String>? query}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) async => response;
}

final class _Ids implements IdGenerator {
  _Ids(this._values);

  final List<String> _values;

  @override
  String newId() => _values.removeAt(0);
}

Future<String?> _setting(Database db, String key) async {
  final rows = await db.query(
    'app_settings',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['value'] as String;
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count'] as int;
}
