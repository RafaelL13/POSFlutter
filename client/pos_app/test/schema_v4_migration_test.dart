import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('fresh V4 creates constrained special authorization grants', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final db = await database.open();

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(
      await db.query(
        'sqlite_master',
        where: "type='table' AND name='special_authorization_grants'",
      ),
      hasLength(1),
    );
    final row = {
      'global_id': 'grant-1',
      'capability': 'saleCancel',
      'requirement': 'SecondUserAuthorization',
      'performed_by_user_global_id': 'seller-1',
      'authorized_by_user_global_id': 'manager-1',
      'business_global_id': 'business-1',
      'device_global_id': 'device-1',
      'reason': 'Approved',
      'authorized_at': '2026-08-29T12:00:00Z',
    };
    await db.insert('special_authorization_grants', row);
    await expectLater(
      db.insert('special_authorization_grants', {...row, 'reason': 'Again'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('special_authorization_grants', {
        ...row,
        'global_id': 'grant-empty-reason',
        'reason': '   ',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('special_authorization_grants', {
        ...row,
        'global_id': 'grant-invalid-requirement',
        'requirement': 'Unknown',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('upgrade V3 to V4 preserves existing data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pos_v4_migration_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}v3.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          for (final statement in [
            ...schemaV1Statements,
            ...schemaV2Statements,
            ...schemaV3Statements,
          ]) {
            await db.execute(statement);
          }
        },
      ),
    );
    final now = DateTime.utc(2026, 8, 29).toIso8601String();
    await legacy.insert('businesses', {
      'global_id': 'preserved-business',
      'name': 'Preserved',
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(database.close);
    final upgraded = await database.open();

    expect(await upgraded.getVersion(), 4);
    expect(
      await upgraded.query(
        'businesses',
        columns: ['name'],
        where: 'global_id=?',
        whereArgs: ['preserved-business'],
      ),
      [containsPair('name', 'Preserved')],
    );
    expect(
      await upgraded.query(
        'sqlite_master',
        where: "type='table' AND name='special_authorization_grants'",
      ),
      hasLength(1),
    );
    expect(
      (await upgraded.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
  });
}
