import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'storage_service.dart';

/// Handles X25519 key exchange, HKDF key derivation, and AES-256-GCM encryption.
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

    // HKDF-SHA256 to derive AES-256 key
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: utf8.encode(_hkdfSalt),
      info: utf8.encode(_hkdfInfo),
    );

    _aesKey = derivedKey;

    // Persist the derived key
    final keyBytes = await derivedKey.extractBytes();
    await StorageService.setEncryptionKey(keyBytes);
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
}
