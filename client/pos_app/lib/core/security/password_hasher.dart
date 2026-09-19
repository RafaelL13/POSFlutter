import 'dart:convert';
import 'dart:math';

import 'package:webcrypto/webcrypto.dart' as webcrypto;

final class PasswordHash {
  const PasswordHash(this.hash, this.salt);

  final String hash;
  final String salt;
}

final class PasswordHasher {
  static const int _iterations = 210000;
  static const int _bits = 256;

  Future<PasswordHash> hash(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));

    final derived = await _derive(password: password, salt: salt);

    return PasswordHash(base64Encode(derived), base64Encode(salt));
  }

  Future<bool> verify(
    String password,
    String encodedHash,
    String encodedSalt,
  ) async {
    final salt = base64Decode(encodedSalt);
    final expected = base64Decode(encodedHash);
    final candidate = await _derive(password: password, salt: salt);
    return _constantTimeEquals(candidate, expected);
  }

  Future<List<int>> _derive({
    required String password,
    required List<int> salt,
  }) async {
    final key = await webcrypto.Pbkdf2SecretKey.importRawKey(
      utf8.encode(password),
    );

    return key.deriveBits(_bits, webcrypto.Hash.sha256, salt, _iterations);
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var difference = 0;

    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }

    return difference == 0;
  }
}
