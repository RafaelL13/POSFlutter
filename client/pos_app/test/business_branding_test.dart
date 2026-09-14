import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/design/app_theme.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/branding/data/business_branding_repository.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'branding defaults to business name and is readable before login',
    () async {
      final database = await _fixture(
        role: 'Administrator',
        authenticated: false,
      );
      addTearDown(database.close);
      final branding = await BusinessBrandingRepository(database).read();
      expect(branding.displayName, 'Business');
      expect(branding.branchName, 'Principal');
      expect(branding.deviceName, 'Tablet');
    },
  );

  test(
    'administrator saves branding locally and queues complete update',
    () async {
      final database = await _fixture(role: 'Administrator');
      addTearDown(database.close);
      final logo = _png();
      await BusinessBrandingRepository(database).save(
        displayName: 'Mi Tienda',
        logoBytes: logo,
        primaryColor: businessBrandColors.first,
      );
      final branding = await BusinessBrandingRepository(database).read();
      expect(branding.displayName, 'Mi Tienda');
      expect(branding.logoBytes, logo);
      expect(branding.primaryColor, businessBrandColors.first);
      final db = await database.open();
      final queued = (await db.query('sync_queue')).single;
      final payload =
          jsonDecode(queued['payload_json'] as String) as Map<String, dynamic>;
      expect(payload['displayName'], 'Mi Tienda');
      expect(payload['logoBase64'], base64Encode(logo));
      expect(payload['brandingUpdatedAt'], isNotNull);
    },
  );

  for (final role in ['Seller', 'Supervisor']) {
    test('$role cannot write branding', () async {
      final database = await _fixture(role: role);
      addTearDown(database.close);
      expect(
        BusinessBrandingRepository(database)
            .save(displayName: 'Denied', logoBytes: null, primaryColor: null),
        throwsA(isA<AuthorizationDeniedException>()),
      );
    });
  }

  test('AdminReadOnly cannot write branding', () async {
    final database = await _fixture(
      role: 'Administrator',
      mode: 'AdminReadOnly',
    );
    addTearDown(database.close);
    expect(
      BusinessBrandingRepository(database)
          .save(displayName: 'Denied', logoBytes: null, primaryColor: null),
      throwsA(isA<AuthorizationDeniedException>()),
    );
  });

  test(
    'logo validation accepts signatures and rejects corrupt or oversized data',
    () {
      expect(BusinessBrandingRepository.validateLogo(_png()), 'image/png');
      expect(
        () => BusinessBrandingRepository.validateLogo(
          Uint8List.fromList([1, 2, 3]),
        ),
        throwsArgumentError,
      );
      expect(
        () => BusinessBrandingRepository.validateLogo(
          Uint8List(businessLogoMaxBytes + 1),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'business pull applies branding and older payload preserves it',
    () async {
      final database = await _fixture(role: 'Administrator');
      addTearDown(database.close);
      final repository = SyncRepository(database: database);
      Future<void> pull(int cursor, Map<String, dynamic> payload) =>
          repository.applyPullBatch(
            SyncPullBatch(
              nextCursor: cursor,
              hasMore: false,
              serverTime: DateTime.utc(2026, 9, 13),
              changes: [
                SyncPullChange(
                  cursor: cursor,
                  entityType: 'Business',
                  entityGlobalId: 'business-1',
                  operation: 'Update',
                  version: cursor,
                  changedAt: DateTime.utc(2026, 9, 13),
                  payload: payload,
                ),
              ],
            ),
          );
      Map<String, dynamic> common(int version) => {
        'globalId': 'business-1',
        'name': 'Business',
        'active': true,
        'updatedAt': '2026-09-13T00:00:00Z',
        'serverVersion': version,
      };
      await pull(2, {
        ...common(2),
        'displayName': 'Remota',
        'logoBase64': base64Encode(_png()),
        'logoMimeType': 'image/png',
        'primaryColor': businessBrandColors[1],
        'brandingUpdatedAt': '2026-09-13T00:00:00Z',
      });
      expect(
        (await BusinessBrandingRepository(database).read()).displayName,
        'Remota',
      );
      await pull(3, common(3));
      expect(
        (await BusinessBrandingRepository(database).read()).displayName,
        'Remota',
      );
    },
  );

  test('theme is derived from the controlled business color', () {
    final theme = AppTheme.lightFromSeed(
      Color(0xFF000000 | businessBrandColors.first),
    );
    expect(
      theme.colorScheme.primary,
      isNot(AppTheme.light.colorScheme.primary),
    );
  });
}

Uint8List _png() =>
    Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);

Future<AppDatabase> _fixture({
  required String role,
  String mode = 'PointOfSale',
  bool authenticated = true,
}) async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    fileName: 'branding-${DateTime.now().microsecondsSinceEpoch}.db',
  );
  final db = await database.open();
  final now = DateTime.utc(2026, 9, 13).toIso8601String();
  final business = await db.insert('businesses', {
    'global_id': 'business-1',
    'name': 'Business',
    'created_at': now,
    'updated_at': now,
  });
  final branch = await db.insert('branches', {
    'global_id': 'branch-1',
    'business_id': business,
    'name': 'Principal',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('devices', {
    'global_id': 'device-1',
    'branch_id': branch,
    'name': 'Tablet',
    'mode': mode,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('users', {
    'global_id': 'user-1',
    'business_id': business,
    'name': 'User',
    'username': 'user',
    'password_hash': 'h',
    'password_salt': 's',
    'role': role,
    'created_at': now,
    'updated_at': now,
  });
  for (final entry in {
    'local_device_global_id': 'device-1',
    'active_user_global_id': 'user-1',
    'local_session_authenticated': authenticated ? '1' : '0',
  }.entries) {
    await db.insert('app_settings', {
      'key': entry.key,
      'value': entry.value,
      'updated_at': now,
    });
  }
  return database;
}
