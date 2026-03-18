import 'dart:async';
import 'dart:convert';

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
        }

        relay.connect(relayUrl);
      }
    } else {
      state = PairingState.unpaired;
    }
  }

  /// Starts the pairing flow with X25519 key exchange.
  /// [daemonPublicKeyB64] is the daemon's public key from the QR code (may be null for legacy).
  Future<void> startPairing(
    String relayUrl,
    String pairingCode, {
    String? daemonPublicKeyB64,
  }) async {
    state = PairingState.pairing;

    final relay = ref.read(relayServiceProvider);
    await StorageService.setRelayUrl(relayUrl);
    await relay.connect(relayUrl);

    // Pre-generate X25519 keypair so we can send it immediately on pairing
    String? myPublicKeyB64;
    ({
      dynamic keyPair,
      List<int> publicKeyBytes,
    })? keypairResult;

    if (daemonPublicKeyB64 != null) {
      try {
        final result = await CryptoService.generateKeyPair();
        keypairResult = (
          keyPair: result.keyPair,
          publicKeyBytes: result.publicKeyBytes,
        );
        myPublicKeyB64 = base64Encode(result.publicKeyBytes);
      } catch (e) {
        // Key generation failed — proceed without encryption
      }
    }

    // Listen for registration + pairing responses
    final completer = Completer<bool>();
    var registered = false;

    final sub = relay.incoming.listen((msg) {
      final type = msg['type'];

      if (type == 'registered' && !registered) {
        registered = true;
        relay.send(ControlMessage.pairWithCode(pairingCode));
      } else if (type == 'paired') {
        final pairedWith = msg['paired_with'] ?? '';
        StorageService.setPairedDeviceId(pairedWith);

        // Send key exchange immediately while the listener is active
        if (myPublicKeyB64 != null) {
          relay.sendRelayUnencrypted(AppMessage.keyExchange(myPublicKeyB64));
        }

        if (!completer.isCompleted) completer.complete(true);
      } else if (type == 'error') {
        if (!completer.isCompleted) completer.complete(false);
      }
    });

    final success = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );

    await sub.cancel();

    // Derive shared secret after pairing succeeds
    if (success &&
        daemonPublicKeyB64 != null &&
        keypairResult != null) {
      try {
        final daemonPkBytes = base64Decode(daemonPublicKeyB64);
        final crypto = CryptoService();
        await crypto.deriveKey(
          myKeyPair: keypairResult.keyPair,
          peerPublicKeyBytes: daemonPkBytes,
        );
        relay.setCrypto(crypto);
      } catch (e) {
        // Key derivation failed — continue without encryption
      }
    }

    if (success) {
      state = PairingState.paired;
    } else {
      await StorageService.clearPairing();
      state = PairingState.unpaired;
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
