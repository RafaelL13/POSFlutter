import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('repair coalesces untouched Business and User updates', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);

    await fixture.repository.repairFirstSyncQueue();

    final db = await fixture.database.open();
    final queue = await db.query('sync_queue', orderBy: 'id ASC');

    expect(queue, hasLength(2));

    expect(queue[0]['global_id'], 'business-create-operation');
    expect(queue[0]['operation'], 'Create');

    final business = Map<String, Object?>.from(
      jsonDecode(queue[0]['payload_json'] as String) as Map,
    );

    expect(business['displayName'], 'Marca Final');
    expect(business['primaryColor'], 222);
    expect(business['serverVersion'], 0);
    expect(business.containsKey('baseServerVersion'), isFalse);

    expect(queue[1]['global_id'], 'user-create-operation');
    expect(queue[1]['operation'], 'Create');

    final user = Map<String, Object?>.from(
      jsonDecode(queue[1]['payload_json'] as String) as Map,
    );

    expect(user['name'], 'Usuario Final');
    expect(user['username'], 'usuario.final');
    expect(user['passwordHash'], 'hash-final');
    expect(user['passwordSalt'], 'salt-final');
    expect(user.containsKey('baseServerVersion'), isFalse);
  });

  test('repair is idempotent', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);

    await fixture.repository.repairFirstSyncQueue();

    final db = await fixture.database.open();
    final once = await db.query('sync_queue', orderBy: 'id ASC');

    await fixture.repository.repairFirstSyncQueue();

    final twice = await db.query('sync_queue', orderBy: 'id ASC');
    expect(twice, once);
  });

  test('repair does not touch an attempted update', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);

    final db = await fixture.database.open();

    await db.update(
      'sync_queue',
      {'retry_count': 1, 'last_attempt_at': '2026-09-20T12:00:00.000Z'},
      where: 'global_id = ?',
      whereArgs: ['business-update-operation-2'],
    );

    final before = await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: ['Business'],
      orderBy: 'id ASC',
    );

    await fixture.repository.repairFirstSyncQueue();

    final after = await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: ['Business'],
      orderBy: 'id ASC',
    );

    expect(after, before);
  });

  test('repair does not coalesce server_version greater than zero', () async {
    final fixture = await _fixture();
    addTearDown(fixture.database.close);

    final db = await fixture.database.open();

    await db.update(
      'users',
      {'server_version': 1},
      where: 'global_id = ?',
      whereArgs: ['user-1'],
    );

    final before = await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: ['User'],
      orderBy: 'id ASC',
    );

    await fixture.repository.repairFirstSyncQueue();

    final after = await db.query(
      'sync_queue',
      where: 'entity_type = ?',
      whereArgs: ['User'],
      orderBy: 'id ASC',
    );

    expect(after, before);
  });
}

Future<_Fixture> _fixture() async {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );

  final db = await database.open();
  final now = DateTime.utc(2026, 9, 20).toIso8601String();

  final businessId = await db.insert('businesses', {
    'global_id': 'business-1',
    'name': 'Business',
    'server_version': 0,
    'created_at': now,
    'updated_at': now,
  });

  final branchId = await db.insert('branches', {
    'global_id': 'branch-1',
    'business_id': businessId,
    'name': 'Principal',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('devices', {
    'global_id': 'device-1',
    'branch_id': branchId,
    'name': 'Tablet',
    'mode': 'PointOfSale',
    'created_at': now,
    'updated_at': now,
  });

  await db.insert('users', {
    'global_id': 'user-1',
    'business_id': businessId,
    'name': 'Current',
    'username': 'current',
    'password_hash': 'hash',
    'password_salt': 'salt',
    'role': 'Administrator',
    'server_version': 0,
    'created_at': now,
    'updated_at': now,
  });

  for (final entry in {
    'local_device_global_id': 'device-1',
    'active_user_global_id': 'user-1',
    'local_session_authenticated': '1',
  }.entries) {
    await db.insert('app_settings', {
      'key': entry.key,
      'value': entry.value,
      'updated_at': now,
    });
  }

  Future<void> enqueue(
    String operationId,
    String type,
    String entityId,
    String operation,
    Map<String, Object?> payload,
  ) async {
    await db.insert('sync_queue', {
      'global_id': operationId,
      'entity_type': type,
      'entity_global_id': entityId,
      'operation': operation,
      'payload_version': 1,
      'payload_json': jsonEncode(payload),
      'created_at': now,
    });
  }

  await enqueue(
    'business-create-operation',
    'Business',
    'business-1',
    'Create',
    {
      'globalId': 'business-1',
      'name': 'Business',
      'active': true,
      'updatedAt': now,
      'serverVersion': 0,
      'displayName': 'Original',
      'primaryColor': null,
    },
  );

  await enqueue(
    'business-update-operation-1',
    'Business',
    'business-1',
    'Update',
    {
      'globalId': 'business-1',
      'name': 'Business',
      'active': true,
      'updatedAt': now,
      'baseServerVersion': 0,
      'displayName': 'Marca Intermedia',
      'primaryColor': 111,
    },
  );

  await enqueue(
    'business-update-operation-2',
    'Business',
    'business-1',
    'Update',
    {
      'globalId': 'business-1',
      'name': 'Business',
      'active': true,
      'updatedAt': now,
      'baseServerVersion': 0,
      'displayName': 'Marca Final',
      'primaryColor': 222,
    },
  );

  await enqueue('user-create-operation', 'User', 'user-1', 'Create', {
    'globalId': 'user-1',
    'businessGlobalId': 'business-1',
    'name': 'Usuario Inicial',
    'username': 'usuario.inicial',
    'passwordHash': 'hash-inicial',
    'passwordSalt': 'salt-inicial',
    'role': 'Seller',
    'active': true,
    'updatedAt': now,
  });

  await enqueue('user-update-operation', 'User', 'user-1', 'Update', {
    'globalId': 'user-1',
    'businessGlobalId': 'business-1',
    'name': 'Usuario Final',
    'username': 'usuario.final',
    'passwordHash': 'hash-final',
    'passwordSalt': 'salt-final',
    'role': 'Seller',
    'active': true,
    'updatedAt': now,
    'baseServerVersion': 0,
  });

  return _Fixture(database, SyncRepository(database: database));
}

final class _Fixture {
  const _Fixture(this.database, this.repository);

  final AppDatabase database;
  final SyncRepository repository;
}
