import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:pos_app/database/schema_v4.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('fresh V5 contains persistent sync classification columns', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final db = await database.open();
    final columns = await db.rawQuery('PRAGMA table_info(sync_queue)');
    final names = columns.map((row) => row['name']).toSet();

    expect(await db.getVersion(), 5);
    expect(
      names,
      containsAll(['error_category', 'error_code', 'requires_action']),
    );
  });

  test('upgrade V4 to V5 preserves pending operation and defaults', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pos_v5_migration_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}v4.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          for (final statement in [
            ...schemaV1Statements,
            ...schemaV2Statements,
            ...schemaV3Statements,
            ...schemaV4Statements,
          ]) {
            await db.execute(statement);
          }
        },
      ),
    );
    await legacy.insert('sync_queue', {
      'global_id': 'pending-v4',
      'entity_type': 'Sale',
      'entity_global_id': 'sale-v4',
      'operation': 'Create',
      'payload_version': 1,
      'payload_json': '{}',
      'created_at': '2026-08-29T12:00:00Z',
      'status': 'Error',
      'retry_count': 2,
      'error_message': 'Legacy error',
    });
    await legacy.close();

    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(database.close);
    final upgraded = await database.open();
    final row = (await upgraded.query(
      'sync_queue',
      where: 'global_id=?',
      whereArgs: ['pending-v4'],
    )).single;

    expect(await upgraded.getVersion(), 5);
    expect(row['status'], 'Error');
    expect(row['retry_count'], 2);
    expect(row['error_message'], 'Legacy error');
    expect(row['error_category'], 'UNSUPPORTED_OPERATION');
    expect(row['error_code'], 'LegacyUnclassified');
    expect(row['requires_action'], 1);
    expect(
      (await upgraded.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
  });
}
