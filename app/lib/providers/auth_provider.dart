import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/relay_message.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import 'relay_provider.dart';

enum PairingState { unknown, unpaired, pairing, paired }

class AuthNotifier extends Notifier<PairingState> {
  @override
  PairingState build() {
    _checkPairing();
    return PairingState.unknown;
  }

  Future<void> _checkPairing() async {
    final paired = await StorageService.isPaired();
    if (paired) {
      state = PairingState.paired;
      final relayUrl = await StorageService.getRelayUrl();
      if (relayUrl != null) {
        final relay = ref.read(relayServiceProvider);

        // Load persisted encryption key
        final crypto = CryptoService();
        final hasKey = await crypto.loadKey();
        if (hasKey) {
          relay.setCrypto(crypto);
          relay.markEncryptionEstablished();
        }

        relay.connect(relayUrl);
      }
    } else {
      state = PairingState.unpaired;
    }
  }

  /// Starts the pairing flow with X25519 key exchange.
  ///
  /// Two paths:
  /// - **QR scan**: `daemonPublicKeyB64` is provided — key exchange is atomic
  ///   with pairing (app's public key sent in pair_with_code).
  /// - **Manual code entry**: `daemonPublicKeyB64` is null — after pairing,
  ///   daemon sends KeyExchange via relay, app responds with its own.
  Future<void> startPairing(
    String relayUrl,
    String pairingCode, {
    String? daemonPublicKeyB64,
  }) async {
    state = PairingState.pairing;

    final relay = ref.read(relayServiceProvider);
    await StorageService.setRelayUrl(relayUrl);
    await relay.connect(relayUrl);

    // Generate keypair (always needed for encryption)
    final keyResult = await CryptoService.generateKeyPair();
    final myKeyPair = keyResult.keyPair;
    final myPublicKeyB64 = base64Encode(keyResult.publicKeyBytes);
    dev.log('Generated keypair, publicKey: $myPublicKeyB64', name: 'Ferlay');

    // Only include public key in pair_with_code if we have the daemon's key (QR path)
    final includeKeyInPairing = daemonPublicKeyB64 != null;

    // Listen for registration + pairing responses
    final completer = Completer<bool>();
    var registered = false;

    final sub = relay.incoming.listen((msg) {
      final type = msg['type'];

      if (type == 'registered' && !registered) {
        registered = true;
        dev.log(
          'Registered, sending pair_with_code (includeKey=$includeKeyInPairing)',
          name: 'Ferlay',
        );
        relay.send(
          ControlMessage.pairWithCode(
            pairingCode,
            publicKey: includeKeyInPairing ? myPublicKeyB64 : null,
          ),
        );
      } else if (type == 'paired') {
        final pairedWith = msg['paired_with'] ?? '';
        StorageService.setPairedDeviceId(pairedWith);
        if (!completer.isCompleted) completer.complete(true);
      } else if (type == 'error') {
        dev.log('Relay error: ${msg['message']}', name: 'Ferlay');
        if (!completer.isCompleted) completer.complete(false);
      }
    });

    final success = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );

    await sub.cancel();

    if (!success) {
      await StorageService.clearPairing();
      state = PairingState.unpaired;
      return;
    }

    // Derive encryption key
    final crypto = CryptoService();
    String? peerPublicKeyB64 = daemonPublicKeyB64;

    if (peerPublicKeyB64 == null) {
      // Manual pairing path: wait for daemon's KeyExchange, then send ours
      dev.log('Manual pairing — waiting for daemon KeyExchange...', name: 'Ferlay');
      peerPublicKeyB64 = await _waitForKeyExchange(relay);
      if (peerPublicKeyB64 == null) {
        dev.log('KeyExchange timed out', name: 'Ferlay');
        await StorageService.clearPairing();
        state = PairingState.unpaired;
        return;
      }
      // Send our public key back (unencrypted, via relay)
      relay.sendRelayUnencrypted(AppMessage.keyExchange(myPublicKeyB64));
      dev.log('Sent our KeyExchange response', name: 'Ferlay');
    }

    final peerPkBytes = base64Decode(peerPublicKeyB64);
    await crypto.deriveKey(
      myKeyPair: myKeyPair,
      peerPublicKeyBytes: peerPkBytes,
    );
    relay.setCrypto(crypto);
    dev.log('E2E encryption keys derived, waiting for verification...', name: 'Ferlay');

    // Wait for encryption verification challenge from daemon
    final verified = await _waitForEncryptionVerification(relay);
    if (verified) {
      dev.log('E2E encryption verified successfully', name: 'Ferlay');
      relay.markEncryptionEstablished();
      state = PairingState.paired;
    } else {
      dev.log('E2E encryption verification failed', name: 'Ferlay');
      relay.markEncryptionFailed();
      await crypto.clearKey();
      await StorageService.clearPairing();
      state = PairingState.unpaired;
    }
  }

  /// Waits for the daemon to send its public key via KeyExchange relay message.
  /// Returns the base64 public key string, or null on timeout.
  Future<String?> _waitForKeyExchange(dynamic relay) async {
    final completer = Completer<String?>();

    final sub = relay.incoming.listen((Map<String, dynamic> msg) {
      if (msg['type'] == 'key_exchange') {
        final pk = msg['public_key'] as String?;
        if (pk != null && !completer.isCompleted) {
          completer.complete(pk);
        }
      }
    });

    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Waits for the daemon's encryption_verify challenge and responds with ack.
  Future<bool> _waitForEncryptionVerification(dynamic relay) async {
    final completer = Completer<bool>();

    final sub = relay.incoming.listen((Map<String, dynamic> msg) {
      if (msg['type'] == 'encryption_verify') {
        final challenge = msg['challenge'] as String?;
        if (challenge != null) {
          dev.log('Received encryption verification challenge', name: 'Ferlay');
          // Respond with the same challenge
          relay.sendRelay(AppMessage.encryptionVerifyAck(challenge));
          if (!completer.isCompleted) completer.complete(true);
        }
      }
    });

    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          dev.log('Encryption verification timed out', name: 'Ferlay');
          return false;
        },
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<void> unpair() async {
    final crypto = CryptoService();
    await crypto.clearKey();
    await StorageService.clearPairing();
    state = PairingState.unpaired;
  }
}

final authProvider = NotifierProvider<AuthNotifier, PairingState>(
  AuthNotifier.new,
);
