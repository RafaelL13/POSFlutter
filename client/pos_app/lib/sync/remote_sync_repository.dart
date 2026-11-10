import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/sync/sync_operation.dart';
import 'package:pos_app/sync/sync_pull.dart';

final class RemoteSyncRepository {
  static const webSaleCapabilityHeader = 'X-POSFlutter-Sync-Capability';
  static const webSaleCapability = 'WebSaleInventoryV1';

  RemoteSyncRepository(this._api);
  final JsonApiClient _api;
  Future<List<SyncOperationResult>> push(
    List<SyncOperationRecord> operations,
  ) async {
    final j = await _api.post('/api/sync/push', {
      'operations': operations.map((e) => e.toJson()).toList(),
    });
    return (j['results'] as List)
        .map(
          (e) =>
              SyncOperationResult.fromJson(Map<String, Object?>.from(e as Map)),
        )
        .toList();
  }

  /// Updated clients explicitly opt in to the compatible channel. Older app
  /// versions continue using the legacy path and never receive this event.
  Future<SyncPullBatch> pull(int cursor, {int limit = 100}) async =>
      SyncPullBatch.fromJson(
        await _api.get(
          '/api/sync/pull-v2',
          query: {'cursor': '$cursor', 'limit': '$limit', 'purchaseV1': 'true'},
          headers: {webSaleCapabilityHeader: webSaleCapability},
        ),
      );
}
