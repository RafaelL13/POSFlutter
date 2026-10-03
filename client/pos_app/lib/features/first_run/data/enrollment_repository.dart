import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/authorization/device_mode.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/core/security/password_hasher.dart';
import 'package:pos_app/core/storage/secure_token_store.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';

typedef EnrollmentPasswordHasher = Future<PasswordHash> Function(
  String password,
);

typedef EnrollmentTokenWriter = Future<void> Function({
  required String accessToken,
  required String refreshToken,
});

typedef EnrollmentTokenClearer = Future<void> Function();

final class EnrollmentPostRedeemException implements Exception {
  const EnrollmentPostRedeemException([this.stage = 'unknown']);

  final String stage;

  @override
  String toString() => 'EnrollmentPostRedeemException(stage=$stage)';
}

final class EnrollmentResult {
  const EnrollmentResult({
    required this.mode,
    required this.deviceGlobalId,
    required this.cloudCredentialsPersisted,
  });

  final DeviceMode mode;
  final String deviceGlobalId;
  final bool cloudCredentialsPersisted;
}

final class EnrollmentRepository {
  EnrollmentRepository(
    this._db,
    this._api, {
    IdGenerator? ids,
    SecureTokenStore? tokens,
    EnrollmentPasswordHasher? hashPassword,
    EnrollmentTokenWriter? saveTokens,
    EnrollmentTokenClearer? clearTokens,
  }) : _ids = ids ?? const UuidV7Generator(),
       _tokens = tokens ?? const SecureTokenStore(),
       _hashPassword = hashPassword ?? PasswordHasher().hash,
       _tokenWriterOverride = saveTokens,
       _tokenClearerOverride = clearTokens;
  final AppDatabase _db;
  final JsonApiClient _api;
  final IdGenerator _ids;
  final SecureTokenStore _tokens;
  final EnrollmentPasswordHasher _hashPassword;
  final EnrollmentTokenWriter? _tokenWriterOverride;
  final EnrollmentTokenClearer? _tokenClearerOverride;
  Future<String> stableDeviceGlobalId() async {
    final db = await _db.open();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: ['pending_enrollment_device_global_id'],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['value'] as String;
    final id = _ids.newId();
    await db.insert('app_settings', {
      'key': 'pending_enrollment_device_global_id',
      'value': id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<EnrollmentResult> redeem({
    required String code,
    required String username,
    required String password,
    required String deviceName,
    String? recoveryDeviceGlobalId,
  }) async {
    final deviceGid = recoveryDeviceGlobalId?.trim().isNotEmpty == true
        ? recoveryDeviceGlobalId!.trim()
        : await stableDeviceGlobalId();
    final j = await _api.post('/api/device-enrollment/redeem', {
      'token': code.trim(),
      'username': username.trim(),
      'password': password,
      'deviceName': deviceName.trim(),
      'deviceGlobalId': deviceGid,
    }, authenticated: false);
    var postRedeemStage = 'response_parse';

    try {
      final auth = _map(j, 'auth');
      final device = _map(j, 'device');
      final mode = DeviceMode.tryParse(device['mode']?.toString());

      if (mode == null) {
        throw const EnrollmentPostRedeemException();
      }

      if (device['globalId']?.toString() != deviceGid) {
        throw const EnrollmentPostRedeemException();
      }

      final accessToken = auth['accessToken']?.toString();
      final refreshToken = auth['refreshToken']?.toString();
      if (accessToken == null || refreshToken == null) {
        throw const EnrollmentPostRedeemException();
      }

      postRedeemStage = 'password_hash';
      final localPassword = mode == DeviceMode.pointOfSale
          ? await _hashPassword(password)
          : null;

      postRedeemStage = 'database_open';
      final db = await _db.open();
      await db.transaction((tx) async {
        final now = DateTime.now().toUtc().toIso8601String();
        final business = _map(j, 'business');
        final branch = _map(j, 'branch');
        final user = _map(j, 'user');
        postRedeemStage = 'sqlite_business';
        final bid = await tx.insert('businesses', {
          'global_id': business['globalId'],
          'name': business['name'],
          'server_version': business['serverVersion'] ?? 1,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        postRedeemStage = 'sqlite_branch';
        final brid = await tx.insert('branches', {
          'global_id': branch['globalId'],
          'business_id': bid,
          'name': branch['name'],
          'server_version': branch['serverVersion'] ?? 1,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        postRedeemStage = 'sqlite_device';
        await tx.insert('devices', {
          'global_id': device['globalId'],
          'branch_id': brid,
          'name': device['name'],
          'mode': mode.wireValue,
          'server_version': device['serverVersion'] ?? 1,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        postRedeemStage = 'sqlite_user';
        await tx.insert('users', {
          'global_id': user['globalId'],
          'business_id': bid,
          'name': user['name'],
          'username': user['username'],
          'password_hash': localPassword?.hash ?? 'REMOTE_ONLY',
          'password_salt': localPassword?.salt ?? 'REMOTE_ONLY',
          'role': user['role'],
          'server_version': user['serverVersion'] ?? 1,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        postRedeemStage = 'sqlite_settings';
        for (final e in {
          'local_device_global_id': deviceGid,
          'active_user_global_id': user['globalId'].toString(),
          'configured': '1',
          'local_session_authenticated': '1',
        }.entries) {
          await tx.insert('app_settings', {
            'key': e.key,
            'value': e.value,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        postRedeemStage = 'sqlite_pending_cleanup';
        await tx.delete(
          'app_settings',
          where: 'key=?',
          whereArgs: ['pending_enrollment_device_global_id'],
        );
      });

      var cloudCredentialsPersisted = true;
      try {
        if (_tokenWriterOverride case final save?) {
          await save(accessToken: accessToken, refreshToken: refreshToken);
        } else {
          await _tokens.save(
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
        }
      } on Object {
        cloudCredentialsPersisted = false;
        try {
          if (_tokenClearerOverride case final clear?) {
            await clear();
          } else {
            await _tokens.clear();
          }
        } on Object {
          // A failed cleanup must not block local, offline-first enrollment.
        }
      }

      return EnrollmentResult(
        mode: mode,
        deviceGlobalId: deviceGid,
        cloudCredentialsPersisted: cloudCredentialsPersisted,
      );
    } on EnrollmentPostRedeemException {
      rethrow;
    } on Object {
      throw EnrollmentPostRedeemException(postRedeemStage);
    }
  }

  static Map<String, Object?> _map(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! Map) {
      throw const EnrollmentPostRedeemException();
    }
    return Map<String, Object?>.from(value);
  }
}
