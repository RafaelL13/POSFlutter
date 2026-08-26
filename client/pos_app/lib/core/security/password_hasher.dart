import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

final class PasswordHash {
  const PasswordHash(this.hash, this.salt);
  final String hash;
  final String salt;
}

final class PasswordHasher {
  PasswordHasher()
      : _algorithm = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 210000,
          bits: 256,
        );

  final Pbkdf2 _algorithm;

  Future<PasswordHash> hash(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return PasswordHash(
      base64Encode(await key.extractBytes()),
      base64Encode(salt),
    );
  }

  Future<bool> verify(
    String password,
    String encodedHash,
    String encodedSalt,
  ) async {
    final salt = base64Decode(encodedSalt);
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final candidate = await key.extractBytes();
    final expected = base64Decode(encodedHash);
    return _constantTimeEquals(candidate, expected);
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}
