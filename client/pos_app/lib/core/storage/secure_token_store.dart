import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class SecureTokenStore {
  const SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }
  Future<String?> accessToken() => _storage.read(key: 'access_token');
  Future<String?> refreshToken() => _storage.read(key: 'refresh_token');
  Future<void> clear() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
