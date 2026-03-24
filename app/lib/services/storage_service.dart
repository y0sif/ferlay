import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';

class StorageService {
  static const _storage = FlutterSecureStorage();

  static const _keyRelayUrl = 'relay_url';
  static const _keyDeviceId = 'device_id';
  static const _keyPairedDeviceId = 'paired_device_id';
  static const _keyEncryptionKey = 'encryption_key';

  static Future<String?> getRelayUrl() => _storage.read(key: _keyRelayUrl);
  static Future<void> setRelayUrl(String url) =>
      _storage.write(key: _keyRelayUrl, value: url);

  static Future<String> getDeviceId() async {
    var id = await _storage.read(key: _keyDeviceId);
    if (id == null) {
      id = _generateUuid();
      await _storage.write(key: _keyDeviceId, value: id);
    }
    return id;
  }

  static Future<String?> getPairedDeviceId() =>
      _storage.read(key: _keyPairedDeviceId);
  static Future<void> setPairedDeviceId(String id) =>
      _storage.write(key: _keyPairedDeviceId, value: id);

  static Future<bool> isPaired() async {
    final relayUrl = await getRelayUrl();
    final pairedId = await getPairedDeviceId();
    return relayUrl != null && pairedId != null;
  }

  static Future<void> clearPairing() async {
    await _storage.delete(key: _keyRelayUrl);
    await _storage.delete(key: _keyPairedDeviceId);
    await _storage.delete(key: _keyEncryptionKey);
  }

  /// Stores the derived AES-256-GCM key as base64.
  static Future<void> setEncryptionKey(List<int> keyBytes) =>
      _storage.write(key: _keyEncryptionKey, value: base64Encode(keyBytes));

  /// Loads the stored AES key, or null if not set.
  static Future<List<int>?> getEncryptionKey() async {
    final encoded = await _storage.read(key: _keyEncryptionKey);
    if (encoded == null) return null;
    return base64Decode(encoded);
  }

  /// Clears only the encryption key.
  static Future<void> clearEncryptionKey() =>
      _storage.delete(key: _keyEncryptionKey);

  static const _keyOnboardingComplete = 'onboarding_complete';

  static Future<bool> isOnboardingComplete() async {
    final value = await _storage.read(key: _keyOnboardingComplete);
    return value == 'true';
  }

  static Future<void> setOnboardingComplete(bool complete) =>
      _storage.write(key: _keyOnboardingComplete, value: complete.toString());

  static const _keySessions = 'sessions_cache';

  /// Persists the sessions list as JSON for offline access.
  static Future<void> setSessions(String sessionsJson) =>
      _storage.write(key: _keySessions, value: sessionsJson);

  /// Loads persisted sessions list, or null if none.
  static Future<String?> getSessions() =>
      _storage.read(key: _keySessions);

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
