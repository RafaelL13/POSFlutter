import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/authorization/special_authorization.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/backup/domain/backup_provider.dart';

final class LocalBackupProvider implements BackupProvider {
  LocalBackupProvider(this._db);
  final AppDatabase _db;
  @override
  Future<String> createBackup() async {
    await AuthorizationService(_db).require(Capability.backupCreate);
    final dir = await getApplicationDocumentsDirectory();
    final out = p.join(
      dir.path,
      'backup_${DateTime.now().toUtc().millisecondsSinceEpoch}.db',
    );
    final db = await _db.open();
    final escaped = out.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$escaped'");
    final check = await openDatabase(out, readOnly: true);
    final integrity = await check.rawQuery('PRAGMA integrity_check');
    await check.close();
    if (integrity.first.values.first != 'ok') {
      await File(out).delete();
      throw StateError('El respaldo no pasó integrity_check.');
    }
    return out;
  }

  @override
  Future<void> restoreBackup(
    String path, {
    SpecialAuthorizationGrant? reauthenticationGrant,
    bool confirmedDestructiveRestore = false,
  }) async {
    final authorization = await AuthorizationService(_db).load();
    final specialAuthorization = SpecialAuthorizationService(_db);
    final prepared = await specialAuthorization.prepare(
      effective: authorization,
      capability: Capability.backupRestore,
      grant: reauthenticationGrant,
    );
    if (!confirmedDestructiveRestore) {
      throw StateError('Debes confirmar explícitamente la restauración.');
    }
    final source = File(path);
    if (!await source.exists()) throw StateError('Respaldo inexistente.');
    final check = await openDatabase(path, readOnly: true);
    final integrity = await check.rawQuery('PRAGMA integrity_check');
    final version = await check.getVersion();
    await check.close();
    if (integrity.first.values.first != 'ok' ||
        version > AppDatabase.schemaVersion) {
      throw StateError('Respaldo inválido o de versión no soportada.');
    }
    final entityGlobalId = p.basename(path);
    final authorizationMetadata = await _db.criticalTransaction(
      (tx) => specialAuthorization.consumeInTransaction(
        tx,
        prepared: prepared,
        effective: authorization,
        capability: Capability.backupRestore,
        operation: 'Restore',
        entityType: 'Backup',
        entityGlobalId: entityGlobalId,
      ),
    );
    await _db.maintenance((target) async {
      final preventive = File('$target.pre_restore');
      if (await File(target).exists()) await File(target).copy(preventive.path);
      try {
        await source.copy(target);
        final verify = await openDatabase(target, readOnly: true);
        final result = await verify.rawQuery('PRAGMA integrity_check');
        await verify.close();
        if (result.first.values.first != 'ok') {
          throw StateError('La base restaurada no es íntegra.');
        }
      } catch (_) {
        if (await preventive.exists()) await preventive.copy(target);
        rethrow;
      } finally {
        if (await preventive.exists()) await preventive.delete();
      }
    });
    final grant = reauthenticationGrant;
    if (grant != null && authorizationMetadata != null) {
      await specialAuthorization.recordAfterDatabaseRestore(
        grant: grant,
        effective: authorization,
        metadata: authorizationMetadata,
        operation: 'Restore',
        entityType: 'Backup',
        entityGlobalId: entityGlobalId,
      );
    }
  }
}
