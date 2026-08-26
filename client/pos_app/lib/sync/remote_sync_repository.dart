import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/sync/sync_operation.dart';
import 'package:pos_app/sync/sync_pull.dart';

final class RemoteSyncRepository {
  RemoteSyncRepository(this._api); final CloudApiClient _api;
  Future<List<SyncOperationResult>> push(List<SyncOperationRecord> operations) async {final j=await _api.post('/api/sync/push',{'operations':operations.map((e)=>e.toJson()).toList()});return (j['results'] as List).map((e)=>SyncOperationResult.fromJson(Map<String,Object?>.from(e as Map))).toList();}
  Future<SyncPullBatch> pull(int cursor,{int limit=100}) async=>SyncPullBatch.fromJson(await _api.get('/api/sync/pull',query:{'cursor':'$cursor','limit':'$limit'}));
}
