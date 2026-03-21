import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart';

import 'storage_service.dart';

/// Handles X25519 key exchange, HKDF key derivation, and AES-256-GCM encryption.
///
/// HKDF is implemented manually using HMAC-SHA256 to ensure exact parity
/// with the Rust daemon's hkdf crate (RFC 5869).
class CryptoService {
  static const _hkdfSalt = 'ferlay-e2e';
  static const _hkdfInfo = 'aes-256-gcm-key';

  SecretKey? _aesKey;

  bool get isReady => _aesKey != null;

  /// Generates an X25519 keypair and returns the public key bytes.
  static Future<({SimpleKeyPair keyPair, List<int> publicKeyBytes})>
      generateKeyPair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return (keyPair: keyPair, publicKeyBytes: publicKey.bytes);
  }

  /// Performs X25519 ECDH, derives AES key via HKDF, and stores it.
  Future<void> deriveKey({
    required SimpleKeyPair myKeyPair,
    required List<int> peerPublicKeyBytes,
  }) async {
    final algorithm = X25519();
    final peerPublicKey =
        SimplePublicKey(peerPublicKeyBytes, type: KeyPairType.x25519);

    // X25519 ECDH
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );
    final sharedBytes = await sharedSecret.extractBytes();

    // HKDF-SHA256 to derive AES-256 key (manual implementation for Rust parity)
    final keyBytes = hkdfSha256(
      ikm: Uint8List.fromList(sharedBytes),
      salt: Uint8List.fromList(utf8.encode(_hkdfSalt)),
      info: Uint8List.fromList(utf8.encode(_hkdfInfo)),
      length: 32,
    );

    _aesKey = SecretKey(keyBytes);

    // Persist the derived key
    await StorageService.setEncryptionKey(keyBytes);
  }

  /// Derives an AES key from raw shared secret bytes (for testing or manual key setup).
  void deriveKeyFromSharedSecret(Uint8List sharedBytes) {
    final keyBytes = hkdfSha256(
      ikm: sharedBytes,
      salt: Uint8List.fromList(utf8.encode(_hkdfSalt)),
      info: Uint8List.fromList(utf8.encode(_hkdfInfo)),
      length: 32,
    );
    _aesKey = SecretKey(keyBytes);
  }

  /// Loads a previously persisted AES key.
  Future<bool> loadKey() async {
    final keyBytes = await StorageService.getEncryptionKey();
    if (keyBytes != null) {
      _aesKey = SecretKey(keyBytes);
      return true;
    }
    return false;
  }

  /// Sets the AES key directly (for testing).
  void setKeyForTesting(List<int> keyBytes) {
    _aesKey = SecretKey(keyBytes);
  }

  /// Encrypts plaintext and returns base64(nonce[12] + ciphertext + mac[16]).
  Future<String> encrypt(String plaintext) async {
    if (_aesKey == null) throw StateError('No encryption key');

    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: _aesKey!,
    );

    // Concatenate: nonce(12) + ciphertext + mac(16)
    final combined = Uint8List(
        secretBox.nonce.length +
            secretBox.cipherText.length +
            secretBox.mac.bytes.length);
    var offset = 0;
    combined.setRange(offset, offset + secretBox.nonce.length, secretBox.nonce);
    offset += secretBox.nonce.length;
    combined.setRange(
        offset, offset + secretBox.cipherText.length, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setRange(
        offset, offset + secretBox.mac.bytes.length, secretBox.mac.bytes);

    return base64Encode(combined);
  }

  /// Decrypts base64(nonce[12] + ciphertext + mac[16]) and returns plaintext.
  Future<String> decrypt(String encoded) async {
    if (_aesKey == null) throw StateError('No encryption key');

    final combined = base64Decode(encoded);
    if (combined.length < 12 + 16) {
      throw ArgumentError('Ciphertext too short');
    }

    // Split: nonce(12) + ciphertext(len-28) + mac(16)
    final nonce = combined.sublist(0, 12);
    final cipherText = combined.sublist(12, combined.length - 16);
    final macBytes = combined.sublist(combined.length - 16);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final algorithm = AesGcm.with256bits();
    final plainBytes = await algorithm.decrypt(
      secretBox,
      secretKey: _aesKey!,
    );

    return utf8.decode(plainBytes);
  }

  /// Clears the stored key (used on re-pairing).
  Future<void> clearKey() async {
    _aesKey = null;
    await StorageService.clearEncryptionKey();
  }

  /// Returns the raw AES key bytes (for testing/debugging).
  Future<List<int>?> get aesKeyBytes async {
    if (_aesKey == null) return null;
    return await _aesKey!.extractBytes();
  }

  // ---------------------------------------------------------------------------
  // HKDF-SHA256 (RFC 5869) — manual implementation for exact Rust parity.
  // ---------------------------------------------------------------------------

  /// HKDF-SHA256: Extract-then-Expand.
  static Uint8List hkdfSha256({
    required Uint8List ikm,
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    // Extract: PRK = HMAC-SHA256(salt, IKM)
    final prk = _hmacSha256(salt, ikm);

    // Expand: OKM = T(1) || T(2) || ... truncated to `length`
    // T(i) = HMAC-SHA256(PRK, T(i-1) || info || i)
    final n = (length + 31) ~/ 32; // ceil(length / hashLen)
    final okm = BytesBuilder();
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      final input = BytesBuilder();
      input.add(prev);
      input.add(info);
      input.addByte(i);
      prev = _hmacSha256(Uint8List.fromList(prk), Uint8List.fromList(input.toBytes()));
      okm.add(prev);
    }

    return Uint8List.fromList(okm.toBytes().sublist(0, length));
  }

  /// HMAC-SHA256(key, data) using the crypto package.
  static Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, key);
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }
}
