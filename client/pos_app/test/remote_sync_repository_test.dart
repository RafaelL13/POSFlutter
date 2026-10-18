import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/network/cloud_api_client.dart';
import 'package:pos_app/sync/remote_sync_repository.dart';

void main() {
  test(
    'updated client opts in to the compatible web-sale pull channel',
    () async {
      final api = _FakeApi();

      final batch = await RemoteSyncRepository(api).pull(42, limit: 25);

      expect(api.path, '/api/sync/pull-v2');
      expect(api.query, {'cursor': '42', 'limit': '25'});
      expect(api.headers, {
        RemoteSyncRepository.webSaleCapabilityHeader:
            RemoteSyncRepository.webSaleCapability,
      });
      expect(batch.nextCursor, 42);
      expect(batch.changes, isEmpty);
    },
  );
}

final class _FakeApi implements JsonApiClient {
  String? path;
  Map<String, String>? query;
  Map<String, String>? headers;

  @override
  Future<Map<String, Object?>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.query = query;
    this.headers = headers;
    return {
      'nextCursor': 42,
      'hasMore': false,
      'changes': <Object?>[],
      'serverTime': '2026-10-17T00:00:00Z',
    };
  }

  @override
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
  }) => throw UnimplementedError();
}
