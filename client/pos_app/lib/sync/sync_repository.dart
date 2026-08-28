import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/core/utils/id_generator.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/sync_operation.dart';
import 'package:pos_app/sync/sync_pull.dart';

final class SyncRepository {
  SyncRepository({required this._database, IdGenerator? idGenerator})
    : _ids = idGenerator ?? const UuidV7Generator();

  final AppDatabase _database;
  final IdGenerator _ids;

  Future<List<SyncOperationRecord>> nextBatch({int limit = 50}) async {
    await AuthorizationService(_database).require(Capability.syncPush);
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.query(
      'sync_queue',
      where: "status = 'Pending' OR (status = 'Error' AND next_attempt_at IS NOT NULL AND next_attempt_at <= ?)",
      whereArgs: [now],
      orderBy: 'id ASC',
      limit: limit.clamp(1, 100),
    );
    return rows.map(SyncOperationRecord.fromRow).toList(growable: false);
  }

  Future<void> markSyncing(List<SyncOperationRecord> operations) async {
    if (operations.isEmpty) return;
    await AuthorizationService(_database).require(Capability.syncPush);
    final db = await _database.open();
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();
    for (final operation in operations) {
      batch.update(
        'sync_queue',
        {'status': 'Syncing', 'last_attempt_at': now, 'error_message': null},
        where: 'id = ? AND status IN (?, ?)',
        whereArgs: [operation.id, 'Pending', 'Error'],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> applyResults(List<SyncOperationResult> results) async {
    if (results.isEmpty) return;
    await AuthorizationService(_database).require(Capability.syncPush);
    final db = await _database.open();
    await db.transaction((tx) async {
      for (final result in results) {
        if (result.status == 'Applied' || result.status == 'AlreadyProcessed') {
          await tx.update(
            'sync_queue',
            {
              'status': 'Synced',
              'error_message': null,
              'next_attempt_at': null,
            },
            where: 'global_id = ?',
            whereArgs: [result.globalId],
          );
          continue;
        }

        if (result.status == 'Retry') {
          final nextRetry = DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 30))
              .toIso8601String();
          await tx.rawUpdate(
            "UPDATE sync_queue SET status = 'Error', retry_count = retry_count + 1, error_message = ?, next_attempt_at = ? WHERE global_id = ?",
            [_safeMessage(result.error), nextRetry, result.globalId],
          );
          continue;
        }

        if (result.status == 'Conflict' &&
            result.remoteVersion != null &&
            result.remotePayload != null) {
          await _recordPushConflict(tx, result);
          await tx.rawUpdate(
            "UPDATE sync_queue SET status = 'Error', retry_count = retry_count + 1, error_message = ?, next_attempt_at = NULL WHERE global_id = ?",
            [
              _safeMessage(result.error) ??
                  'Conflicto pendiente de resolución.',
              result.globalId,
            ],
          );
          continue;
        }

        await tx.rawUpdate(
          "UPDATE sync_queue SET status = 'Error', retry_count = retry_count + 1, error_message = ?, next_attempt_at = NULL WHERE global_id = ?",
          [_safeMessage(result.error), result.globalId],
        );
      }
    });
  }

  Future<void> markTransportFailure(
    List<SyncOperationRecord> operations,
    String message,
  ) async {
    if (operations.isEmpty) return;
    await AuthorizationService(_database).require(Capability.syncPush);
    final db = await _database.open();
    await db.transaction((tx) async {
      for (final operation in operations) {
        final nextRetry = DateTime.now()
            .toUtc()
            .add(_backoff(operation.retryCount + 1))
            .toIso8601String();
        await tx.rawUpdate(
          '''
          UPDATE sync_queue
          SET status = 'Error', retry_count = retry_count + 1,
              error_message = ?, next_attempt_at = ?
          WHERE id = ?
          ''',
          [_safeMessage(message), nextRetry, operation.id],
        );
      }
    });
  }

  Future<void> recoverInterrupted() async {
    await AuthorizationService(_database).require(Capability.syncPush);
    final db = await _database.open();
    await db.rawUpdate(
      "UPDATE sync_queue SET status = 'Pending', error_message = 'Reintento después de cierre inesperado.' WHERE status = 'Syncing'",
    );
  }

  Future<int> pendingCount() async {
    final db = await _database.open();
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM sync_queue WHERE status <> 'Synced'",
    );
    return result.first['count']! as int;
  }

  Future<int> currentPullCursor() async {
    final db = await _database.open();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['sync_pull_cursor'],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value']! as String) ?? 0;
  }

  Future<void> applyPullBatch(SyncPullBatch batch) async {
    final authorization = await AuthorizationService(_database)
        .require(Capability.syncPull);
    final context = authorization.context!;
    final db = await _database.open();
    await db.transaction((tx) async {
      final current = await _cursorInTransaction(tx);
      if (batch.nextCursor < current) {
        throw StateError(
          'El servidor devolvió un cursor anterior al cursor local.',
        );
      }
      if (batch.nextCursor == current) {
        if (batch.changes.any((change) => change.cursor > current)) {
          throw StateError(
            'El lote remoto contiene cambios posteriores sin avanzar el cursor.',
          );
        }
        return;
      }
      if (batch.changes.isEmpty) {
        throw StateError('El servidor avanzó el cursor sin entregar cambios.');
      }

      var previousCursor = current;
      for (final change in batch.changes) {
        if (change.cursor <= current) continue;
        if (change.cursor <= previousCursor) {
          throw StateError(
            'Los cambios remotos no están ordenados por cursor ascendente.',
          );
        }
        if (change.cursor > batch.nextCursor) {
          throw StateError('Un cambio remoto excede el cursor final del lote.');
        }
        previousCursor = change.cursor;
      }
      final effective = batch.changes
          .where((change) => change.cursor > current)
          .toList(growable: false);
      if (effective.isEmpty || effective.last.cursor != batch.nextCursor) {
        throw StateError(
          'El cursor final no coincide con el último cambio del lote.',
        );
      }

      final ordered = [...effective]
        ..sort((a, b) {
          final rank = _entityRank(a.entityType)
              .compareTo(_entityRank(b.entityType));
          return rank != 0 ? rank : a.cursor.compareTo(b.cursor);
        });
      for (final change in ordered) {
        await _applyRemoteChange(tx, change, context);
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('app_settings', {
        'key': 'sync_pull_cursor',
        'value': batch.nextCursor.toString(),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.update(
        'devices',
        {'last_sync_at': batch.serverTime.toIso8601String()},
        where: 'id = ?',
        whereArgs: [context.deviceId],
      );
    });
  }

  Future<void> _applyRemoteChange(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    if (change.operation != 'Create' && change.operation != 'Update') {
      throw StateError(
        'Operación pull no soportada: ${change.entityType}/${change.operation}.',
      );
    }

    _validateRemoteBusiness(change, context.businessGlobalId);
    final localVersion = await _localServerVersion(
      tx,
      change.entityType,
      change.entityGlobalId,
    );
    if (change.version <= localVersion) return;

    final pending = await tx.query(
      'sync_queue',
      columns: ['global_id', 'payload_json'],
      where: "entity_type = ? AND entity_global_id = ? AND status <> 'Synced'",
      whereArgs: [change.entityType, change.entityGlobalId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (pending.isNotEmpty) {
      await _recordPullConflict(tx, change, pending.first);
      return;
    }

    switch (change.entityType) {
      case 'Business':
        await _applyBusiness(tx, change, context);
        break;
      case 'Branch':
        await _applyBranch(tx, change, context);
        break;
      case 'Device':
        await _applyDevice(tx, change, context);
        break;
      case 'User':
        await _applyUser(tx, change, context);
        break;
      case 'Category':
        await _applyCategory(tx, change, context);
        break;
      case 'Supplier':
        await _applySupplier(tx, change, context);
        break;
      case 'Product':
        await _applyProduct(tx, change, context);
        break;
      default:
        throw StateError('Entidad pull no soportada: ${change.entityType}.');
    }
  }

  Future<void> _applyBusiness(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    if (change.entityGlobalId != context.businessGlobalId) {
      throw StateError(
        'El servidor intentó aplicar otro negocio en esta base local.',
      );
    }
    final payload = change.payload;
    await tx.update(
      'businesses',
      {
        'name': _requiredString(payload, 'name'),
        'active': _boolInt(payload, 'active'),
        'updated_at': _requiredDate(payload, 'updatedAt'),
        'server_version': change.version,
      },
      where: 'id = ?',
      whereArgs: [context.businessId],
    );
  }

  Future<void> _applyBranch(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    final payload = change.payload;
    final rows = await tx.query(
      'branches',
      columns: ['id'],
      where: 'global_id = ?',
      whereArgs: [change.entityGlobalId],
      limit: 1,
    );
    final values = {
      'global_id': change.entityGlobalId,
      'business_id': context.businessId,
      'name': _requiredString(payload, 'name'),
      'active': _boolInt(payload, 'active'),
      'updated_at': _requiredDate(payload, 'updatedAt'),
      'server_version': change.version,
    };
    if (rows.isEmpty) {
      values['created_at'] = change.changedAt.toIso8601String();
      await tx.insert('branches', values);
    } else {
      values.remove('global_id');
      values.remove('business_id');
      await tx.update(
        'branches',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  Future<void> _applyDevice(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    final payload = change.payload;
    final branchGlobalId = _requiredString(payload, 'branchGlobalId');
    final branchRows = await tx.query(
      'branches',
      columns: ['id'],
      where: 'global_id = ? AND business_id = ?',
      whereArgs: [branchGlobalId, context.businessId],
      limit: 1,
    );
    if (branchRows.isEmpty) {
      throw StateError(
        'El dispositivo remoto referencia una sucursal aún no disponible localmente.',
      );
    }
    final rows = await tx.query(
      'devices',
      columns: ['id'],
      where: 'global_id = ?',
      whereArgs: [change.entityGlobalId],
      limit: 1,
    );
    final values = {
      'global_id': change.entityGlobalId,
      'branch_id': branchRows.first['id'],
      'name': _requiredString(payload, 'name'),
      'mode': _requiredString(payload, 'mode'),
      'active': _boolInt(payload, 'active'),
      'updated_at': change.changedAt.toIso8601String(),
      'last_sync_at': payload['lastSyncAt']?.toString(),
      'server_version': change.version,
    };
    if (rows.isEmpty) {
      values['created_at'] = change.changedAt.toIso8601String();
      await tx.insert('devices', values);
    } else {
      values.remove('global_id');
      await tx.update(
        'devices',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  Future<void> _applyUser(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    final payload = change.payload;
    final role = _requiredString(payload, 'role');
    if (!const {
      'Administrator',
      'Seller',
      'Supervisor',
      'Manager',
    }.contains(role)) {
      throw StateError('El servidor devolvió un rol de usuario no soportado.');
    }
    final rows = await tx.query(
      'users',
      columns: ['id'],
      where: 'global_id = ? AND business_id = ?',
      whereArgs: [change.entityGlobalId, context.businessId],
      limit: 1,
    );
    final values = {
      'global_id': change.entityGlobalId,
      'business_id': context.businessId,
      'name': _requiredString(payload, 'name'),
      'username': _requiredString(payload, 'username'),
      'password_hash': _requiredString(payload, 'passwordHash'),
      'password_salt': _requiredString(payload, 'passwordSalt'),
      'role': role,
      'active': _boolInt(payload, 'active'),
      'updated_at': _requiredDate(payload, 'updatedAt'),
      'server_version': change.version,
    };
    if (rows.isEmpty) {
      values['created_at'] = change.changedAt.toIso8601String();
      await tx.insert('users', values);
    } else {
      values.remove('global_id');
      values.remove('business_id');
      await tx.update(
        'users',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  Future<void> _applyCategory(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    final payload = change.payload;
    final rows = await tx.query(
      'categories',
      columns: ['id'],
      where: 'global_id = ? AND business_id = ?',
      whereArgs: [change.entityGlobalId, context.businessId],
      limit: 1,
    );
    final values = {
      'global_id': change.entityGlobalId,
      'business_id': context.businessId,
      'name': _requiredString(payload, 'name'),
      'description': _nullableString(payload['description']),
      'active': _boolInt(payload, 'active'),
      'updated_at': _requiredDate(payload, 'updatedAt'),
      'server_version': change.version,
    };
    if (rows.isEmpty) {
      values['created_at'] = change.changedAt.toIso8601String();
      await tx.insert('categories', values);
    } else {
      values.remove('global_id');
      values.remove('business_id');
      await tx.update(
        'categories',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  Future<void> _applySupplier(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    final payload = change.payload;
    final rows = await tx.query(
      'suppliers',
      columns: ['id'],
      where: 'global_id = ? AND business_id = ?',
      whereArgs: [change.entityGlobalId, context.businessId],
      limit: 1,
    );
    final values = {
      'global_id': change.entityGlobalId,
      'business_id': context.businessId,
      'name': _requiredString(payload, 'name'),
      'contact_name': _nullableString(payload['contactName']),
      'phone': _nullableString(payload['phone']),
      'email': _nullableString(payload['email']),
      'address': _nullableString(payload['address']),
      'notes': _nullableString(payload['notes']),
      'active': _boolInt(payload, 'active'),
      'updated_at': _requiredDate(payload, 'updatedAt'),
      'server_version': change.version,
    };
    if (rows.isEmpty) {
      values['created_at'] = change.changedAt.toIso8601String();
      await tx.insert('suppliers', values);
    } else {
      values.remove('global_id');
      values.remove('business_id');
      await tx.update(
        'suppliers',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  Future<void> _applyProduct(
    Transaction tx,
    SyncPullChange change,
    LocalAppContext context,
  ) async {
    final payload = change.payload;
    int? categoryId;
    final categoryGlobalId = _nullableString(payload['categoryGlobalId']);
    if (categoryGlobalId != null) {
      final categories = await tx.query(
        'categories',
        columns: ['id'],
        where: 'global_id = ? AND business_id = ?',
        whereArgs: [categoryGlobalId, context.businessId],
        limit: 1,
      );
      if (categories.isEmpty) {
        throw StateError(
          'El producto remoto referencia una categoría aún no disponible localmente.',
        );
      }
      categoryId = categories.first['id']! as int;
    }

    final price = _requiredInt(payload, 'salePriceCents', allowZero: true);
    final minimum = _requiredInt(payload, 'minimumStock', allowZero: true);
    final rows = await tx.query(
      'products',
      columns: ['id'],
      where: 'global_id = ? AND business_id = ?',
      whereArgs: [change.entityGlobalId, context.businessId],
      limit: 1,
    );
    final values = {
      'global_id': change.entityGlobalId,
      'business_id': context.businessId,
      'category_id': categoryId,
      'code': _requiredString(payload, 'code'),
      'barcode': _nullableString(payload['barcode']),
      'name': _requiredString(payload, 'name'),
      'presentation': _requiredString(payload, 'presentation'),
      'sale_price_cents': price,
      'minimum_stock': minimum,
      'active': _boolInt(payload, 'active'),
      'updated_at': _requiredDate(payload, 'updatedAt'),
      'server_version': change.version,
    };
    if (rows.isEmpty) {
      values['created_at'] = change.changedAt.toIso8601String();
      await tx.insert('products', values);
    } else {
      values.remove('global_id');
      values.remove('business_id');
      await tx.update(
        'products',
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  Future<int> _localServerVersion(
    Transaction tx,
    String entityType,
    String globalId,
  ) async {
    final table = switch (entityType) {
      'Business' => 'businesses',
      'Branch' => 'branches',
      'Device' => 'devices',
      'User' => 'users',
      'Category' => 'categories',
      'Supplier' => 'suppliers',
      'Product' => 'products',
      _ => throw StateError('Entidad pull no soportada: $entityType.'),
    };
    final rows = await tx.query(
      table,
      columns: ['server_version'],
      where: 'global_id = ?',
      whereArgs: [globalId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['server_version']! as int;
  }

  Future<void> _recordPullConflict(
    Transaction tx,
    SyncPullChange change,
    Map<String, Object?> pending,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await tx.insert('sync_conflicts', {
      'global_id': _ids.newId(),
      'entity_type': change.entityType,
      'entity_global_id': change.entityGlobalId,
      'source': 'Pull',
      'local_operation_global_id': pending['global_id'],
      'local_payload_json': pending['payload_json'],
      'remote_payload_json': jsonEncode(change.payload),
      'remote_version': change.version,
      'remote_cursor': change.cursor,
      'detected_at': now,
      'status': 'Pending',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _recordPushConflict(
    Transaction tx,
    SyncOperationResult result,
  ) async {
    final rows = await tx.query(
      'sync_queue',
      columns: ['global_id', 'entity_type', 'entity_global_id', 'payload_json'],
      where: 'global_id = ?',
      whereArgs: [result.globalId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    await tx.insert('sync_conflicts', {
      'global_id': _ids.newId(),
      'entity_type': row['entity_type'],
      'entity_global_id': row['entity_global_id'],
      'source': 'Push',
      'local_operation_global_id': row['global_id'],
      'local_payload_json': row['payload_json'],
      'remote_payload_json': jsonEncode(result.remotePayload),
      'remote_version': result.remoteVersion,
      'remote_cursor': null,
      'detected_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'Pending',
    });
  }

  Future<int> _cursorInTransaction(Transaction tx) async {
    final rows = await tx.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['sync_pull_cursor'],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value']! as String) ?? 0;
  }

  static void _validateRemoteBusiness(
    SyncPullChange change,
    String localBusinessGlobalId,
  ) {
    final payloadBusiness = switch (change.entityType) {
      'Business' => change.payload['globalId'],
      _ => change.payload['businessGlobalId'],
    };
    if (payloadBusiness?.toString() != localBusinessGlobalId) {
      throw StateError(
        'El servidor devolvió un cambio perteneciente a otro negocio.',
      );
    }
    if (change.payload['globalId']?.toString() != change.entityGlobalId) {
      throw StateError(
        'El payload remoto no coincide con el identificador del cambio.',
      );
    }
    final payloadVersion = change.payload['serverVersion'];
    if (payloadVersion is! num || payloadVersion.toInt() != change.version) {
      throw StateError(
        'La versión del payload remoto no coincide con el cambio.',
      );
    }
  }

  static int _entityRank(String type) => switch (type) {
    'Business' => 0,
    'Branch' => 1,
    'Device' => 2,
    'User' => 3,
    'Category' => 4,
    'Supplier' => 5,
    'Product' => 6,
    _ => 99,
  };

  static String _requiredString(Map<String, Object?> payload, String key) {
    final value = payload[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw StateError('El campo remoto $key es obligatorio.');
    }
    return value;
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _requiredInt(
    Map<String, Object?> payload,
    String key, {
    bool allowZero = false,
  }) {
    final value = payload[key];
    if (value is! num ||
        value % 1 != 0 ||
        (allowZero ? value < 0 : value <= 0)) {
      throw StateError('El campo remoto $key debe ser un entero válido.');
    }
    return value.toInt();
  }

  static int _boolInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! bool) {
      throw StateError('El campo remoto $key debe ser booleano.');
    }
    return value ? 1 : 0;
  }

  static String _requiredDate(Map<String, Object?> payload, String key) {
    final value = DateTime.tryParse(payload[key]?.toString() ?? '');
    if (value == null) {
      throw StateError('El campo remoto $key debe contener una fecha válida.');
    }
    return value.toUtc().toIso8601String();
  }

  static Duration _backoff(int retry) {
    final seconds = switch (retry) {
      <= 1 => 5,
      2 => 15,
      3 => 30,
      4 => 60,
      5 => 120,
      _ => 300,
    };
    return Duration(seconds: seconds);
  }

  static String? _safeMessage(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final text = value.trim();
    return text.length <= 500 ? text : text.substring(0, 500);
  }
}
