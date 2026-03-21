import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ferlay/services/crypto_service.dart';

/// Cross-platform test vectors that MUST match the Rust daemon's crypto tests.
/// If either side changes HKDF params, salt, info, or wire format, these tests
/// will fail — that's the point.
void main() {
  // Shared secret: bytes 0x01..0x20 (32 bytes)
  final testVectorSharedSecret = Uint8List.fromList(
    List.generate(32, (i) => i + 1),
  );

  // Expected AES-256 key from HKDF-SHA256(salt="ferlay-e2e", info="aes-256-gcm-key")
  const testVectorDerivedKeyHex =
      '2e90c43fca2aa11bbb14df8f2ab1f04aad5786dde88f5db4478506e2c72052bb';

  // Known ciphertext from Rust: nonce=0x000102...0b, plaintext="hello ferlay e2e"
  const testVectorEncryptedB64 =
      'AAECAwQFBgcICQoLgK9jfCrkWqdHI0p3R6fcKthFmtSawxJI5XvOqQmMfsI=';

  const testVectorPlaintext = 'hello ferlay e2e';

  group('Cross-platform HKDF', () {
    test('derives the same AES key as Rust', () {
      final keyBytes = CryptoService.hkdfSha256(
        ikm: testVectorSharedSecret,
        salt: Uint8List.fromList(utf8.encode('ferlay-e2e')),
        info: Uint8List.fromList(utf8.encode('aes-256-gcm-key')),
        length: 32,
      );

      final keyHex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(keyHex, equals(testVectorDerivedKeyHex),
          reason: 'HKDF-derived AES key must match cross-platform test vector');
    });
  });

  group('Cross-platform decryption', () {
    test('Dart decrypts Rust-produced ciphertext', () async {
      // Derive the key
      final keyBytes = CryptoService.hkdfSha256(
        ikm: testVectorSharedSecret,
        salt: Uint8List.fromList(utf8.encode('ferlay-e2e')),
        info: Uint8List.fromList(utf8.encode('aes-256-gcm-key')),
        length: 32,
      );

      final crypto = CryptoService();
      crypto.setKeyForTesting(keyBytes);

      // Decrypt Rust-produced ciphertext
      final plaintext = await crypto.decrypt(testVectorEncryptedB64);
      expect(plaintext, equals(testVectorPlaintext),
          reason: 'Dart must decrypt Rust-produced ciphertext correctly');
    });
  });

  group('Cross-platform encrypt/decrypt roundtrip', () {
    test('Dart encrypt then decrypt roundtrip', () async {
      final keyBytes = CryptoService.hkdfSha256(
        ikm: testVectorSharedSecret,
        salt: Uint8List.fromList(utf8.encode('ferlay-e2e')),
        info: Uint8List.fromList(utf8.encode('aes-256-gcm-key')),
        length: 32,
      );

      final crypto = CryptoService();
      crypto.setKeyForTesting(keyBytes);

      const original = '{"type":"start_session","directory":"/tmp","name":"test"}';
      final encrypted = await crypto.encrypt(original);
      final decrypted = await crypto.decrypt(encrypted);
      expect(decrypted, equals(original));
    });
  });

  group('CryptoService.deriveKeyFromSharedSecret', () {
    test('produces same key as manual HKDF', () async {
      final crypto = CryptoService();
      crypto.deriveKeyFromSharedSecret(testVectorSharedSecret);

      final keyBytes = await crypto.aesKeyBytes;
      final keyHex = keyBytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(keyHex, equals(testVectorDerivedKeyHex));
    });
  });
}
