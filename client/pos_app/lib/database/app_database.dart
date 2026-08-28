import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema_v1.dart';
import 'schema_v2.dart';
import 'schema_v3.dart';

final class AppDatabase {
  AppDatabase({
    this.fileName = 'pos_flutter.db',
    DatabaseFactory? factory,
    this.databasePath,
  }) : _factory = factory ?? databaseFactory;
  static const schemaVersion = 3;
  final String fileName;
  final DatabaseFactory _factory;
  final String? databasePath;
  Database? _db;
  Completer<void>? _maintenance;

  Future<Database> open() async {
    final maintenance = _maintenance;
    if (maintenance != null) await maintenance.future;
    if (_db case final db? when db.isOpen) return db;
    final path =
        databasePath ?? p.join(await _factory.getDatabasesPath(), fileName);
    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, _) async {
          await _executeAll(db, schemaV1Statements);
          await _executeAll(db, schemaV2Statements);
          await _executeAll(db, schemaV3Statements);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2 && newVersion >= 2) {
            await _executeAll(db, schemaV2Statements);
          }
          if (oldVersion < 3 && newVersion >= 3) {
            await _executeAll(db, schemaV3Statements);
          }
        },
      ),
    );
    return _db!;
  }

  Future<T> criticalTransaction<T>(
    Future<T> Function(Transaction tx) action,
  ) async {
    final db = await open();
    return db.transaction(action, exclusive: true);
  }

  Future<T> maintenance<T>(
    Future<T> Function(String databasePath) action,
  ) async {
    if (_maintenance != null) {
      throw StateError('Ya existe una operación de mantenimiento.');
    }
    // Open before installing the barrier; otherwise open() would wait on this same gate.
    final db = await open();
    final path = db.path;
    final gate = Completer<void>();
    _maintenance = gate;
    try {
      await db.close();
      _db = null;
      return await action(path);
    } finally {
      _maintenance = null;
      gate.complete();
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _executeAll(DatabaseExecutor db, List<String> sql) async {
    for (final statement in sql) {
      await db.execute(statement);
    }
  }
}
