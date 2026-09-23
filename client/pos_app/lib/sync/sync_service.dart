import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pos_app/core/authorization/authorization_service.dart';
import 'package:pos_app/core/authorization/capability.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/remote_sync_repository.dart';
import 'package:pos_app/sync/sync_error.dart';
import 'package:pos_app/sync/sync_repository.dart';

final class SyncService {
  SyncService({
    required this._database,
    required this._local,
    required this._remote,
  });
  final AppDatabase _database;
  final SyncRepository _local;
  final RemoteSyncRepository _remote;
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
    final connectivity = await Connectivity().checkConnectivity();
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

      while (true) {
        final batch = await _local.nextBatch();
        if (batch.isEmpty) {
          break;
        }

        await _local.markSyncing(batch);

        try {
          await _local.applyResults(await _remote.push(batch));
        } on Object catch (error) {
          await _local.markBatchFailure(
            batch,
            SyncFailure.fromException(error),
          );

          // Do not retry a failed batch continuously in the same run.
          // SyncRepository owns the retry/backoff policy.
          break;
        }
      }
    }

    try {
      var more = true;
      while (more) {
        final cursor = await _local.currentPullCursor();
        final pull = await _remote.pull(cursor);
        await _local.applyPullBatch(pull);
        more = pull.hasMore;
      }
      await _local.clearPullFailure();
    } on Object catch (error) {
      await _local.recordPullFailure(SyncFailure.fromPullException(error));
    }
  }
}
