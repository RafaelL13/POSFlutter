import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/security/password_hasher.dart';

void main() {
  test('native-capable hasher verifies legacy PBKDF2 hashes', () async {
    const password = 'existing-password-123';
    final salt = List<int>.generate(16, (index) => index + 1);
    final legacy = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 210000,
      bits: 256,
    );
    final key = await legacy.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );

    final verified = await PasswordHasher().verify(
      password,
      base64Encode(await key.extractBytes()),
      base64Encode(salt),
    );

    expect(verified, isTrue);
  });

  test('new hashes keep the existing PBKDF2 security parameters', () async {
    final hashed = await PasswordHasher().hash('new-password-456');

    expect(
      await PasswordHasher().verify(
        'new-password-456',
        hashed.hash,
        hashed.salt,
      ),
      isTrue,
    );
    expect(
      await PasswordHasher().verify('wrong-password', hashed.hash, hashed.salt),
      isFalse,
    );
  });

  test('new hashes use independent random salts', () async {
    final hasher = PasswordHasher();
    final first = await hasher.hash('same-password');
    final second = await hasher.hash('same-password');

    expect(base64Decode(first.salt), hasLength(16));
    expect(base64Decode(second.salt), hasLength(16));
    expect(second.salt, isNot(first.salt));
    expect(second.hash, isNot(first.hash));
    expect(
      await hasher.verify('same-password', first.hash, first.salt),
      isTrue,
    );
    expect(
      await hasher.verify('same-password', second.hash, second.salt),
      isTrue,
    );
  });
}
