import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/remote_sync_repository.dart';
import 'package:pos_app/sync/sync_operation.dart';
import 'package:pos_app/sync/sync_pull.dart';
import 'package:pos_app/sync/sync_error.dart';
import 'package:pos_app/sync/sync_repository.dart';

typedef SyncConnectivityLoader = Future<List<ConnectivityResult>> Function();
typedef SyncPushExecutor = Future<List<SyncOperationResult>> Function(
  List<SyncOperationRecord> operations,
);
typedef SyncPullExecutor = Future<SyncPullBatch> Function(int cursor);

final class SyncService {
  SyncService({
    required this._database,
    required this._local,
    required RemoteSyncRepository remote,
    SyncConnectivityLoader? connectivity,
    SyncPushExecutor? push,
    SyncPullExecutor? pull,
  }) : _connectivity =
           connectivity ?? (() => Connectivity().checkConnectivity()),
       _push = push ?? remote.push,
       _pull = pull ?? ((cursor) => remote.pull(cursor));
  final AppDatabase _database;
  final SyncRepository _local;
  final SyncConnectivityLoader _connectivity;
  final SyncPushExecutor _push;
  final SyncPullExecutor _pull;
  Future<void>? _activeSynchronization;

  Future<void> synchronize() {
    final active = _activeSynchronization;
    if (active != null) {
      return active;
    }

    final synchronization = _synchronize();
    _activeSynchronization = synchronization;

    return synchronization.whenComplete(() {
      if (identical(_activeSynchronization, synchronization)) {
        _activeSynchronization = null;
      }
    });
  }

  Future<void> _synchronize() async {
    final connectivity = await _connectivity();
    if (connectivity.every((e) => e == ConnectivityResult.none)) {
      await _local.recordPullFailure(
        const SyncFailure(
          category: SyncErrorCategory.networkError,
          code: 'Offline',
          disposition: SyncFailureDisposition.transient,
          message: 'Sin conexión; los cambios permanecen pendientes.',
        ),
      );
      return;
    }

    final authorization = await AuthorizationService(_database)
        .require(Capability.syncPull);

    if (authorization.can(Capability.syncPush)) {
      await _local.recoverInterrupted();
      await _local.repairFirstSyncQueue();

      await _drainPushQueue();
    }

    try {
      var more = true;

      while (more) {
        final cursor = await _local.currentPullCursor();
        final queueWatermark = authorization.can(Capability.syncPush)
            ? await _local.currentQueueMaxId()
            : null;

        final pull = await _pull(cursor);
        await _local.applyPullBatch(pull);

        if (queueWatermark != null) {
          final maxBatches = ((pull.changes.length + 99) ~/ 100).clamp(1, 100);

          await _drainPushQueue(
            maxBatches: maxBatches,
            batchLimit: 100,
            idGreaterThan: queueWatermark,
            entityType: 'CentralTransferApplied',
          );
        }

        more = pull.hasMore;
      }

      await _local.clearPullFailure();
    } on Object catch (error) {
      await _local.recordPullFailure(SyncFailure.fromPullException(error));
    }
  }

  Future<void> _drainPushQueue({
    int? maxBatches,
    int batchLimit = 50,
    int? idGreaterThan,
    String? entityType,
  }) async {
    var processedBatches = 0;

    while (maxBatches == null || processedBatches < maxBatches) {
      final batch = await _local.nextBatch(
        limit: batchLimit,
        idGreaterThan: idGreaterThan,
        entityType: entityType,
      );

      if (batch.isEmpty) {
        break;
      }

      await _local.markSyncing(batch);

      try {
        await _local.applyResults(await _push(batch));
      } on Object catch (error) {
        await _local.markBatchFailure(batch, SyncFailure.fromException(error));

        // Do not retry a failed batch continuously in the same run.
        // SyncRepository owns the retry/backoff policy.
        break;
      }

      processedBatches++;
    }
  }
}
