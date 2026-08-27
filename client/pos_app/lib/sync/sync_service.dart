import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pos_app/core/context/local_app_context.dart';
import 'package:pos_app/database/app_database.dart';
import 'package:pos_app/sync/remote_sync_repository.dart';
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
  Future<void> synchronize() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((e) => e == ConnectivityResult.none)) return;
    final ctx = await LocalAppContext.load(_database);
    await _local.recoverInterrupted();
    if (!ctx.isAdminReadOnly) {
      final batch = await _local.nextBatch();
      if (batch.isNotEmpty) {
        await _local.markSyncing(batch);
        try {
          await _local.applyResults(await _remote.push(batch));
        } catch (e) {
          await _local.markTransportFailure(batch, e.toString());
        }
      }
    }
    var more = true;
    while (more) {
      final cursor = await _local.currentPullCursor();
      final pull = await _remote.pull(cursor);
      await _local.applyPullBatch(pull);
      more = pull.hasMore;
    }
  }
}
