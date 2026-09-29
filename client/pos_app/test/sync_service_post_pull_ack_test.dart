import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/features/inventory/data/inventory_read_repository.dart';
import 'package:pos_app/sync/remote_sync_repository.dart';
import 'package:pos_app/sync/sync_operation.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:pos_app/sync/sync_repository.dart';
import 'package:pos_app/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'post-pull push sends CentralTransferApplied in the same synchronization',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final events = <String>[];

      final service = SyncService(
        database: fixture.database,
        local: fixture.repository,
        remote: RemoteSyncRepository(CloudApiClient()),
        connectivity: () async => [ConnectivityResult.wifi],
        pull: (cursor) async {
          events.add('pull:$cursor');
          return fixture.batch();
        },
        push: (operations) async {
          events.add(
            'push:${operations.map((item) => item.entityType).join(",")}',
          );

          return [
            for (final operation in operations)
              SyncOperationResult(operation.globalId, 'Applied'),
          ];
        },
      );

      await service.synchronize();

      expect(events, ['pull:0', 'push:CentralTransferApplied']);

      expect(await fixture.count('inventory_lots'), 1);
      expect(await fixture.count('inventory_movements'), 1);
      expect(await fixture.repository.currentPullCursor(), 1);

      final acknowledgements = await fixture.ackRows();

      expect(acknowledgements, hasLength(1));
      expect(acknowledgements.single['status'], 'Synced');
      expect(acknowledgements.single['error_category'], isNull);
      expect(acknowledgements.single['next_attempt_at'], isNull);
    },
  );

  test(
    'post-pull network failure preserves inventory and leaves ACK retryable',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      var pushCalls = 0;

      final service = SyncService(
        database: fixture.database,
        local: fixture.repository,
        remote: RemoteSyncRepository(CloudApiClient()),
        connectivity: () async => [ConnectivityResult.wifi],
        pull: (_) async => fixture.batch(),
        push: (operations) async {
          pushCalls++;

          expect(operations.map((item) => item.entityType), [
            'CentralTransferApplied',
          ]);

          throw const CloudApiException(
            CloudFailure.network,
            'Sin conexión con el servidor.',
          );
        },
      );

      await service.synchronize();

      expect(pushCalls, 1);

      expect(await fixture.count('inventory_lots'), 1);
      expect(await fixture.count('inventory_movements'), 1);
      expect(await fixture.repository.currentPullCursor(), 1);

      final acknowledgements = await fixture.ackRows();

      expect(acknowledgements, hasLength(1));

      final acknowledgement = acknowledgements.single;

      expect(acknowledgement['status'], 'Error');
      expect(acknowledgement['error_category'], 'NETWORK_ERROR');
      expect(acknowledgement['error_code'], 'NetworkError');
      expect(acknowledgement['requires_action'], 0);
      expect(acknowledgement['next_attempt_at'], isNotNull);
    },
  );

  test('later synchronization retries due ACK and marks it Synced', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    var pushCalls = 0;
    var firstRun = true;

    final service = SyncService(
      database: fixture.database,
      local: fixture.repository,
      remote: RemoteSyncRepository(CloudApiClient()),
      connectivity: () async => [ConnectivityResult.wifi],
      pull: (cursor) async {
        if (cursor == 0) {
          return fixture.batch();
        }

        return fixture.emptyBatch(cursor);
      },
      push: (operations) async {
        pushCalls++;

        expect(operations.map((item) => item.entityType), [
          'CentralTransferApplied',
        ]);

        if (firstRun) {
          firstRun = false;

          throw const CloudApiException(
            CloudFailure.network,
            'Sin conexión con el servidor.',
          );
        }

        return [
          for (final operation in operations)
            SyncOperationResult(operation.globalId, 'Applied'),
        ];
      },
    );

    await service.synchronize();

    var acknowledgements = await fixture.ackRows();

    expect(pushCalls, 1);
    expect(acknowledgements, hasLength(1));
    expect(acknowledgements.single['status'], 'Error');
    expect(acknowledgements.single['error_category'], 'NETWORK_ERROR');
    expect(acknowledgements.single['next_attempt_at'], isNotNull);
    expect(await fixture.repository.currentPullCursor(), 1);

    await fixture.makeAckRetryDue();

    await service.synchronize();

    acknowledgements = await fixture.ackRows();

    expect(pushCalls, 2);
    expect(acknowledgements, hasLength(1));
    expect(acknowledgements.single['status'], 'Synced');
    expect(acknowledgements.single['error_category'], isNull);
    expect(acknowledgements.single['next_attempt_at'], isNull);

    expect(await fixture.count('inventory_lots'), 1);
    expect(await fixture.count('inventory_movements'), 1);
    expect(await fixture.repository.currentPullCursor(), 1);
  });

  test(
    'recoverInterrupted sends ACK left Syncing without duplicating inventory',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      await fixture.repository.applyPullBatch(fixture.batch());

      expect(await fixture.count('inventory_lots'), 1);
      expect(await fixture.count('inventory_movements'), 1);

      await fixture.markAckSyncing();

      var pushCalls = 0;

      final service = SyncService(
        database: fixture.database,
        local: fixture.repository,
        remote: RemoteSyncRepository(CloudApiClient()),
        connectivity: () async => [ConnectivityResult.wifi],
        pull: (cursor) async => fixture.emptyBatch(cursor),
        push: (operations) async {
          pushCalls++;

          expect(operations.map((item) => item.entityType), [
            'CentralTransferApplied',
          ]);

          return [
            for (final operation in operations)
              SyncOperationResult(operation.globalId, 'Applied'),
          ];
        },
      );

      await service.synchronize();

      final acknowledgements = await fixture.ackRows();

      expect(pushCalls, 1);
      expect(acknowledgements, hasLength(1));
      expect(acknowledgements.single['status'], 'Synced');

      expect(await fixture.count('inventory_lots'), 1);
      expect(await fixture.count('inventory_movements'), 1);
      expect(await fixture.repository.currentPullCursor(), 1);
    },
  );

  test(
    'offline synchronization preserves local ACK and performs no remote calls',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      await fixture.repository.applyPullBatch(fixture.batch());

      var pushCalls = 0;
      var pullCalls = 0;

      final service = SyncService(
        database: fixture.database,
        local: fixture.repository,
        remote: RemoteSyncRepository(CloudApiClient()),
        connectivity: () async => [ConnectivityResult.none],
        pull: (cursor) async {
          pullCalls++;
          return fixture.emptyBatch(cursor);
        },
        push: (operations) async {
          pushCalls++;

          return [
            for (final operation in operations)
              SyncOperationResult(operation.globalId, 'Applied'),
          ];
        },
      );

      await service.synchronize();

      final acknowledgements = await fixture.ackRows();

      expect(pushCalls, 0);
      expect(pullCalls, 0);

      expect(acknowledgements, hasLength(1));
      expect(acknowledgements.single['status'], 'Pending');

      expect(await fixture.count('inventory_lots'), 1);
      expect(await fixture.count('inventory_movements'), 1);
      expect(await fixture.repository.currentPullCursor(), 1);
    },
  );

  test(
    'central transfer history derives ACK lifecycle without new storage',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      await fixture.repository.applyPullBatch(fixture.batch());

      final historyRepository = InventoryReadRepository(fixture.database);

      var history = await historyRepository.centralTransferHistory();

      expect(history, hasLength(1));

      var item = history.single;

      expect(item.transferGlobalId, 'transfer-1');
      expect(item.productCount, 1);
      expect(item.totalQuantity, 7);
      expect(item.status, CentralTransferHistoryStatus.pendingAck);
      expect(item.retryCount, 0);
      expect(item.appliedAt, isNotNull);

      await fixture.db.update(
        'sync_queue',
        {
          'status': 'Error',
          'retry_count': 1,
          'error_category': 'NETWORK_ERROR',
          'requires_action': 0,
          'next_attempt_at': DateTime.utc(2030).toIso8601String(),
        },
        where: 'entity_type=?',
        whereArgs: ['CentralTransferApplied'],
      );

      history = await historyRepository.centralTransferHistory();

      item = history.single;

      expect(item.status, CentralTransferHistoryStatus.retrying);
      expect(item.retryCount, 1);
      expect(item.errorCategory, 'NETWORK_ERROR');
      expect(item.nextAttemptAt, isNotNull);

      await fixture.db.update(
        'sync_queue',
        {
          'status': 'Synced',
          'error_category': null,
          'requires_action': 0,
          'next_attempt_at': null,
        },
        where: 'entity_type=?',
        whereArgs: ['CentralTransferApplied'],
      );

      history = await historyRepository.centralTransferHistory();

      item = history.single;

      expect(item.status, CentralTransferHistoryStatus.confirmed);
      expect(item.errorCategory, isNull);
      expect(item.nextAttemptAt, isNull);

      expect(await fixture.count('inventory_lots'), 1);
      expect(await fixture.count('inventory_movements'), 1);
      expect(await fixture.repository.currentPullCursor(), 1);
    },
  );

  test(
    'more than fifty new transfer ACKs bypass backlog and sync in the same run',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      var pullCalls = 0;
      var backlogInserted = false;
      final pushedAckIds = <String>{};
      final pushBatchSizes = <int>[];

      final service = SyncService(
        database: fixture.database,
        local: fixture.repository,
        remote: RemoteSyncRepository(CloudApiClient()),
        connectivity: () async => [ConnectivityResult.wifi],
        pull: (cursor) async {
          pullCalls++;

          if (!backlogInserted) {
            backlogInserted = true;

            // This happens after the normal pre-pull push and after the
            // post-pull watermark has already been captured.
            await fixture.insertPendingBacklog(count: 60);

            return fixture.largeTransferBatch(count: 60);
          }

          return fixture.emptyBatch(cursor);
        },
        push: (operations) async {
          pushBatchSizes.add(operations.length);

          for (final operation in operations) {
            if (operation.entityType == 'CentralTransferApplied') {
              pushedAckIds.add(operation.globalId);
            }
          }

          return [
            for (final operation in operations)
              SyncOperationResult(operation.globalId, 'Applied'),
          ];
        },
      );

      await service.synchronize();

      expect(pullCalls, 1);

      // All 60 ACKs created by the pull must be sent immediately,
      // despite 60 older/non-ACK operations inserted after the watermark.
      expect(pushedAckIds, hasLength(60));
      expect(pushBatchSizes, [60]);

      final acknowledgements = await fixture.ackRows();

      expect(acknowledgements, hasLength(60));
      expect(
        acknowledgements.every((row) => row['status'] == 'Synced'),
        isTrue,
      );

      // The filtered post-pull drain must not consume unrelated backlog.
      expect(await fixture.pendingBacklogCount(), 60);

      expect(await fixture.count('inventory_lots'), 60);

      expect(await fixture.count('inventory_movements'), 60);

      expect(await fixture.repository.currentPullCursor(), 60);
    },
  );
}

final class _Fixture {
  const _Fixture(this.database, this.db, this.repository);

  final AppDatabase database;
  final dynamic db;
  final SyncRepository repository;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    final db = await database.open();

    final now = DateTime.utc(2026, 9, 29).toIso8601String();

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

    await db.insert('products', {
      'global_id': 'product-1',
      'business_id': businessId,
      'code': 'P1',
      'name': 'Product',
      'presentation': 'Piece',
      'sale_price_cents': 2000,
      'minimum_stock': 0,
      'active': 1,
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

    return _Fixture(database, db, SyncRepository(database: database));
  }

  SyncPullBatch batch() => SyncPullBatch(
    nextCursor: 1,
    hasMore: false,
    serverTime: DateTime.utc(2026, 9, 29, 12, 1),
    changes: [
      SyncPullChange(
        cursor: 1,
        entityType: 'CentralTransferIn',
        entityGlobalId: 'transfer-1',
        operation: 'Create',
        version: 1,
        changedAt: DateTime.utc(2026, 9, 29, 12),
        payload: const {
          'globalId': 'transfer-1',
          'businessGlobalId': 'business-1',
          'branchGlobalId': 'branch-1',
          'date': '2026-09-29T12:00:00Z',
          'serverVersion': 1,
          'lines': [
            {
              'productGlobalId': 'product-1',
              'lotGlobalId': 'central-lot-1',
              'quantity': 7,
              'unitCostCents': 1234,
            },
          ],
        },
      ),
    ],
  );

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) count FROM $table');

    return rows.single['count']! as int;
  }

  Future<List<Map<String, Object?>>> ackRows() async {
    final rows = await db.query(
      'sync_queue',
      where: 'entity_type=?',
      whereArgs: ['CentralTransferApplied'],
    );

    return [for (final row in rows) Map<String, Object?>.from(row)];
  }

  SyncPullBatch emptyBatch(int cursor) => SyncPullBatch(
    nextCursor: cursor,
    hasMore: false,
    changes: const [],
    serverTime: DateTime.utc(2026, 9, 29, 12, 2),
  );

  SyncPullBatch largeTransferBatch({required int count}) {
    final changes = <SyncPullChange>[];

    for (var i = 1; i <= count; i++) {
      final changedAt = DateTime.utc(2026, 9, 29, 12).add(Duration(seconds: i));

      changes.add(
        SyncPullChange(
          cursor: i,
          entityType: 'CentralTransferIn',
          entityGlobalId: 'transfer-$i',
          operation: 'Create',
          version: 1,
          changedAt: changedAt,
          payload: {
            'globalId': 'transfer-$i',
            'businessGlobalId': 'business-1',
            'branchGlobalId': 'branch-1',
            'date': changedAt.toIso8601String(),
            'serverVersion': 1,
            'lines': [
              {
                'productGlobalId': 'product-1',
                'lotGlobalId': 'central-lot-$i',
                'quantity': 1,
                'unitCostCents': 1234,
              },
            ],
          },
        ),
      );
    }

    return SyncPullBatch(
      nextCursor: count,
      hasMore: false,
      changes: changes,
      serverTime: DateTime.utc(2026, 9, 29, 12, 5),
    );
  }

  Future<void> insertPendingBacklog({required int count}) async {
    final createdAt = DateTime.utc(2026, 9, 29, 11).toIso8601String();

    for (var i = 1; i <= count; i++) {
      await db.insert('sync_queue', {
        'global_id': 'backlog-operation-$i',
        'entity_type': 'Category',
        'entity_global_id': 'backlog-category-$i',
        'operation': 'Create',
        'payload_version': 1,
        'payload_json': '{}',
        'created_at': createdAt,
        'status': 'Pending',
      });
    }
  }

  Future<int> pendingBacklogCount() async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM sync_queue
      WHERE entity_type = 'Category'
        AND global_id LIKE 'backlog-operation-%'
        AND status = 'Pending'
      ''');

    return rows.single['count']! as int;
  }

  Future<void> makeAckRetryDue() async {
    await db.update(
      'sync_queue',
      {'next_attempt_at': DateTime.utc(2000).toIso8601String()},
      where: 'entity_type=?',
      whereArgs: ['CentralTransferApplied'],
    );
  }

  Future<void> markAckSyncing() async {
    await db.update(
      'sync_queue',
      {
        'status': 'Syncing',
        'last_attempt_at': DateTime.utc(2026, 9, 29, 12, 3).toIso8601String(),
      },
      where: 'entity_type=?',
      whereArgs: ['CentralTransferApplied'],
    );
  }

  Future<void> dispose() => database.close();
}
