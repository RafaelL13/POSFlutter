import 'package:pos_app/core/network/cloud_api_client.dart';

final class CloudAdminRepository {
  CloudAdminRepository(this._api);
  final JsonApiClient _api;

  Future<Map<String, Object?>> dashboard() => _api.get('/api/admin/reports/summary');

  Future<List<Object?>> list(String path) async {
    final json = await _api.get(path);
    return List<Object?>.from(json['items'] as List? ?? const []);
  }

  Future<Map<String, Object?>> createInvitation({int minutes = 15}) => _api.post('/api/device-enrollment/invitations', {'expiresInMinutes': minutes});
}
