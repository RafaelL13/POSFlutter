import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/database/schema_v1.dart';
import 'package:pos_app/database/schema_v2.dart';
import 'package:pos_app/database/schema_v3.dart';
import 'package:pos_app/database/schema_v4.dart';
import 'package:pos_app/database/schema_v5.dart';
import 'package:pos_app/database/schema_v6.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('schema 6 upgrades through 7 to 8 preserving legacy data and creating initial inventory tables', () async {
    final path = p.join(
      await databaseFactoryFfi.getDatabasesPath(),
      'branding-migration-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() => databaseFactoryFfi.deleteDatabase(path));
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          for (final statement in [
            ...schemaV1Statements,
            ...schemaV2Statements,
            ...schemaV3Statements,
            ...schemaV4Statements,
            ...schemaV5Statements,
            ...schemaV6Statements,
          ]) {
            await db.execute(statement);
          }
        },
      ),
    );
    final now = DateTime.utc(2026, 9, 13).toIso8601String();
    await legacy.insert('businesses', {
      'global_id': 'business-1',
      'name': 'Legacy',
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(database.close);
    final db = await database.open();
    expect(await db.getVersion(), AppDatabase.schemaVersion);
    final business = (await db.query('businesses')).single;
    expect(business['name'], 'Legacy');
    expect(business['display_name'], isNull);

    final initialInventoryTable = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name = 'initial_inventory_imports'",
    );
    expect(initialInventoryTable, hasLength(1));

    final initialInventoryLinesTable = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name = 'initial_inventory_lines'",
    );
    expect(initialInventoryLinesTable, hasLength(1));
    expect(
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
      'ok',
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
