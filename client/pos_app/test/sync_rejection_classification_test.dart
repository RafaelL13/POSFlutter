import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/cash/data/cash_repository.dart';
import 'package:pos_app/features/pos/data/pos_repository.dart';
import 'package:pos_app/features/pos/domain/cart.dart';
import 'package:pos_app/sync/sync_error.dart';
import 'package:pos_app/sync/sync_operation.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('structured result parser preserves errorCode', () {
    final result = SyncOperationResult.fromJson({
      'globalId': 'op-1',
      'status': 'Rejected',
      'errorCode': 'RoleDenied',
      'error': 'Denied',
    });

    expect(result.errorCode, 'RoleDenied');
    expect(
      SyncFailure.fromOperationResult(result).category,
      SyncErrorCategory.authorizationRejected,
    );
  });

  test('Applied and AlreadyProcessed become Synced', () async {
    final fixture = await _SyncFixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertOperation('applied');
    await fixture.insertOperation('duplicate');
    final operations = await fixture.repository.nextBatch();
    await fixture.repository.markSyncing(operations);

    await fixture.repository.applyResults(const [
      SyncOperationResult('applied', 'Applied'),
      SyncOperationResult('duplicate', 'AlreadyProcessed'),
    ]);

    expect(await fixture.column('applied', 'status'), 'Synced');
    expect(await fixture.column('duplicate', 'status'), 'Synced');
    expect(await fixture.column('applied', 'error_category'), isNull);
  });

  test('Retry and network failures remain transient with backoff', () async {
    final fixture = await _SyncFixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertOperation('server-retry');
    await fixture.insertOperation('network-retry');
    final operations = await fixture.repository.nextBatch();
    await fixture.repository.markSyncing(operations);

    await fixture.repository.applyResults(const [
      SyncOperationResult('server-retry', 'Retry', errorCode: 'ServerError'),
    ]);
    await fixture.repository.markBatchFailure(
      [operations.singleWhere((item) => item.globalId == 'network-retry')],
      const SyncFailure(
        category: SyncErrorCategory.networkError,
        code: 'NetworkError',
        disposition: SyncFailureDisposition.transient,
        message: 'Offline',
      ),
    );

    expect(
      await fixture.column('server-retry', 'error_category'),
      'SERVER_ERROR',
    );
    expect(
      await fixture.column('network-retry', 'error_category'),
      'NETWORK_ERROR',
    );
    expect(await fixture.column('server-retry', 'next_attempt_at'), isNotNull);
    expect(await fixture.column('network-retry', 'next_attempt_at'), isNotNull);
    expect(await fixture.column('network-retry', 'requires_action'), 0);
  });

  test(
    'terminal and action-required failures never re-enter automatic batch',
    () async {
      final fixture = await _SyncFixture.create();
      addTearDown(fixture.dispose);
      for (final id in ['authorization', 'validation', 'unsupported']) {
        await fixture.insertOperation(id);
      }
      final operations = await fixture.repository.nextBatch();
      await fixture.repository.markSyncing(operations);
      await fixture.repository.applyResults(const [
        SyncOperationResult(
          'authorization',
          'Rejected',
          errorCode: 'RoleDenied',
        ),
        SyncOperationResult(
          'validation',
          'Rejected',
          errorCode: 'ValidationFailed',
        ),
        SyncOperationResult(
          'unsupported',
          'Rejected',
          errorCode: 'UnsupportedOperation',
        ),
      ]);

      expect(await fixture.repository.nextBatch(), isEmpty);
      expect(await fixture.column('authorization', 'next_attempt_at'), isNull);
      expect(await fixture.column('validation', 'next_attempt_at'), isNull);
      expect(await fixture.column('unsupported', 'next_attempt_at'), isNull);
      expect(await fixture.column('authorization', 'requires_action'), 1);
      expect(await fixture.column('validation', 'requires_action'), 1);
      expect(await fixture.column('unsupported', 'requires_action'), 1);
    },
  );

  test('Conflict is preserved and excluded from automatic retry', () async {
    final fixture = await _SyncFixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertOperation('conflict');
    final operation = (await fixture.repository.nextBatch()).single;
    await fixture.repository.markSyncing([operation]);
    await fixture.repository.applyResults(const [
      SyncOperationResult(
        'conflict',
        'Conflict',
        errorCode: 'Conflict',
        remoteVersion: 4,
        remotePayload: {'name': 'Remote'},
      ),
    ]);

    expect(await fixture.column('conflict', 'error_category'), 'CONFLICT');
    expect(await fixture.column('conflict', 'next_attempt_at'), isNull);
    expect(await fixture.repository.nextBatch(), isEmpty);
    expect(await fixture.count('sync_conflicts'), 1);
  });

  test(
    'HTTP authentication recovery releases only auth-blocked operations',
    () async {
      final fixture = await _SyncFixture.create();
      addTearDown(fixture.dispose);
      for (final id in ['auth', 'authorization', 'validation']) {
        await fixture.insertOperation(id);
      }
      final operations = await fixture.repository.nextBatch();
      await fixture.repository.markSyncing(operations);
      await fixture.repository.markBatchFailure(
        [operations.singleWhere((item) => item.globalId == 'auth')],
        SyncFailure.fromException(
          const CloudApiException(CloudFailure.unauthorized, 'Expired'),
        ),
      );
      await fixture.repository.applyResults(const [
        SyncOperationResult(
          'authorization',
          'Rejected',
          errorCode: 'AuthorizationDenied',
        ),
        SyncOperationResult(
          'validation',
          'Rejected',
          errorCode: 'ValidationFailed',
        ),
      ]);

      expect(await fixture.repository.releaseAuthenticationRequired(), 1);
      expect(await fixture.column('auth', 'status'), 'Pending');
      expect(await fixture.column('authorization', 'status'), 'Error');
      expect(await fixture.column('validation', 'status'), 'Error');
      expect(
        (await fixture.repository.nextBatch()).map((item) => item.globalId),
        ['auth'],
      );
    },
  );

  test('HTTP 403 and DeviceReadOnly map to authorization without retry', () {
    final forbidden = SyncFailure.fromException(
      const CloudApiException(
        CloudFailure.forbidden,
        'Forbidden',
        statusCode: 403,
        errorCode: 'AuthorizationDenied',
      ),
    );
    final device = SyncFailure.fromOperationResult(
      const SyncOperationResult(
        'device-op',
        'Rejected',
        errorCode: 'DeviceReadOnly',
      ),
    );

    expect(forbidden.category, SyncErrorCategory.authorizationRejected);
    expect(forbidden.retryable, isFalse);
    expect(device.category, SyncErrorCategory.authorizationRejected);
    expect(device.retryable, isFalse);
  });

  test('HTTP validation and conflict statuses do not retry', () {
    final validation = SyncFailure.fromException(
      CloudApiException.fromStatus(400),
    );
    final conflict = SyncFailure.fromException(
      CloudApiException.fromStatus(409),
    );

    expect(validation.category, SyncErrorCategory.validationRejected);
    expect(validation.retryable, isFalse);
    expect(conflict.category, SyncErrorCategory.conflict);
    expect(conflict.retryable, isFalse);
  });

  test(
    'invalid pull protocol is terminal and leaves cursor untouched',
    () async {
      final fixture = await _SyncFixture.create();
      addTearDown(fixture.dispose);
      final failure = SyncFailure.fromPullException(
        StateError('invalid cursor'),
      );
      await fixture.repository.recordPullFailure(failure);

      expect(failure.category, SyncErrorCategory.validationRejected);
      expect(failure.retryable, isFalse);
      expect(await fixture.repository.currentPullCursor(), 0);
      final summary = await fixture.repository.summary(isOnline: true);
      expect(summary.pullFailure?.code, 'PullProtocolInvalid');
    },
  );

  test(
    'pull conflict blocks its local operation from automatic retry',
    () async {
      final fixture = await _SyncFixture.create();
      addTearDown(fixture.dispose);
      await fixture.seedProductAndLot();
      await fixture.insertOperation(
        'product-update',
        entityType: 'Product',
        entityGlobalId: 'product-1',
        operation: 'Update',
      );
      await fixture.repository.applyPullBatch(
        SyncPullBatch(
          nextCursor: 1,
          hasMore: false,
          serverTime: DateTime.utc(2026, 8, 29, 13),
          changes: [
            SyncPullChange(
              cursor: 1,
              entityType: 'Product',
              entityGlobalId: 'product-1',
              operation: 'Update',
              version: 2,
              changedAt: DateTime.utc(2026, 8, 29, 13),
              payload: const {
                'globalId': 'product-1',
                'businessGlobalId': 'business-1',
                'categoryGlobalId': null,
                'code': 'P1',
                'barcode': null,
                'name': 'Remote Product',
                'presentation': 'Piece',
                'salePriceCents': 110,
                'minimumStock': 0,
                'active': true,
                'updatedAt': '2026-08-29T13:00:00Z',
                'serverVersion': 2,
              },
            ),
          ],
        ),
      );

      expect(await fixture.column('product-update', 'status'), 'Error');
      expect(
        await fixture.column('product-update', 'error_category'),
        'CONFLICT',
      );
      expect(await fixture.column('product-update', 'next_attempt_at'), isNull);
      expect(await fixture.repository.nextBatch(), isEmpty);
      expect(await fixture.count('sync_conflicts'), 1);
    },
  );

  test(
    'authorization rejection preserves completed local cash sale and FIFO',
    () async {
      final fixture = await _SyncFixture.create();
      addTearDown(fixture.dispose);
      final productId = await fixture.seedProductAndLot();
      await CashRepository(fixture.database).open(0);
      await PosRepository(fixture.database).completeSale(
        [
          CartLine(
            productId: productId,
            productGlobalId: 'product-1',
            name: 'Product',
            quantity: 2,
            unitPriceCents: 100,
          ),
        ],
        paymentMethod: 'Cash',
        receivedCents: 200,
      );
      final saleRow = (await fixture.db.query(
        'sync_queue',
        where: 'entity_type=?',
        whereArgs: ['Sale'],
      )).single;
      final saleOperation = SyncOperationRecord.fromRow(saleRow);
      await fixture.repository.markSyncing([saleOperation]);
      await fixture.repository.applyResults([
        SyncOperationResult(
          saleOperation.globalId,
          'Rejected',
          errorCode: 'RoleDenied',
        ),
      ]);

      expect(await fixture.count('sales'), 1);
      expect(await fixture.count('sale_details'), 1);
      expect(await fixture.count('sale_detail_lots'), 1);
      expect(
        await fixture.columnBy('inventory_lots', 'lot-1', 'available_quantity'),
        8,
      );
      expect(await fixture.count('cash_movements'), 1);
      expect(await fixture.column(saleOperation.globalId, 'status'), 'Error');
      expect(
        await fixture.column(saleOperation.globalId, 'next_attempt_at'),
        isNull,
      );
      expect(
        (await fixture.repository.nextBatch()).where(
          (item) => item.globalId == saleOperation.globalId,
        ),
        isEmpty,
      );
    },
  );
}

final class _SyncFixture {
  _SyncFixture(this.database, this.db, this.repository, this.now);

  final AppDatabase database;
  final Database db;
  final SyncRepository repository;
  final String now;

  static Future<_SyncFixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.open();
    final now = DateTime.utc(2026, 8, 29, 12).toIso8601String();
    final businessId = await db.insert('businesses', {
      'global_id': 'business-1',
      'name': 'Business',
      'created_at': now,
      'updated_at': now,
    });
    final branchId = await db.insert('branches', {
      'global_id': 'branch-1',
      'business_id': businessId,
      'name': 'Main',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('devices', {
      'global_id': 'device-1',
      'branch_id': branchId,
      'name': 'POS',
      'mode': 'PointOfSale',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'global_id': 'user-1',
      'business_id': businessId,
      'name': 'Manager',
      'username': 'manager',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'role': 'Manager',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'local_device_global_id',
      'value': 'device-1',
      'updated_at': now,
    });
    await db.insert('app_settings', {
      'key': 'active_user_global_id',
      'value': 'user-1',
      'updated_at': now,
    });
    return _SyncFixture(database, db, SyncRepository(database: database), now);
  }

  Future<void> insertOperation(
    String globalId, {
    String entityType = 'Category',
    String? entityGlobalId,
    String operation = 'Create',
  }) => db.insert('sync_queue', {
    'global_id': globalId,
    'entity_type': entityType,
    'entity_global_id': entityGlobalId ?? 'entity-$globalId',
    'operation': operation,
    'payload_version': 1,
    'payload_json': '{}',
    'created_at': now,
  });

  Future<int> seedProductAndLot() async {
    final businessId = await columnBy('businesses', 'business-1', 'id') as int;
    final branchId = await columnBy('branches', 'branch-1', 'id') as int;
    final productId = await db.insert('products', {
      'global_id': 'product-1',
      'business_id': businessId,
      'code': 'P1',
      'name': 'Product',
      'presentation': 'Piece',
      'sale_price_cents': 100,
      'minimum_stock': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('inventory_lots', {
      'global_id': 'lot-1',
      'product_id': productId,
      'branch_id': branchId,
      'entry_date': now,
      'initial_quantity': 10,
      'available_quantity': 10,
      'unit_cost_cents': 40,
      'created_at': now,
    });
    return productId;
  }

  Future<Object?> column(String globalId, String column) =>
      columnBy('sync_queue', globalId, column);

  Future<Object?> columnBy(String table, String globalId, String column) async {
    final rows = await db.query(
      table,
      columns: [column],
      where: 'global_id=?',
      whereArgs: [globalId],
      limit: 1,
    );
    return rows.single[column];
  }

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) count FROM $table');
    return rows.single['count']! as int;
  }

  Future<void> dispose() => database.close();
}
