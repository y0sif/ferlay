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
        }

        relay.connect(relayUrl);
      }
    } else {
      state = PairingState.unpaired;
    }
  }

  /// Starts the pairing flow with X25519 key exchange.
  /// The app's public key is sent inside pair_with_code so the relay
  /// forwards it to the daemon atomically in the paired notification.
  Future<void> startPairing(
    String relayUrl,
    String pairingCode, {
    String? daemonPublicKeyB64,
  }) async {
    state = PairingState.pairing;

    final relay = ref.read(relayServiceProvider);
    await StorageService.setRelayUrl(relayUrl);
    await relay.connect(relayUrl);

    // Always generate X25519 keypair — encryption is mandatory
    if (daemonPublicKeyB64 == null) {
      dev.log('ERROR: No daemon public key — encryption is mandatory', name: 'Ferlay');
      state = PairingState.unpaired;
      return;
    }

    final result = await CryptoService.generateKeyPair();
    final myKeyPair = result.keyPair;
    final myPublicKeyB64 = base64Encode(result.publicKeyBytes);
    dev.log('Generated keypair, publicKey: $myPublicKeyB64', name: 'Ferlay');

    // Listen for registration + pairing responses
    final completer = Completer<bool>();
    var registered = false;

    final sub = relay.incoming.listen((msg) {
      final type = msg['type'];

      if (type == 'registered' && !registered) {
        registered = true;
        dev.log('Registered, sending pair_with_code with publicKey', name: 'Ferlay');
        // Include our public key in pair_with_code — relay forwards it
        // to the daemon inside the paired notification
        relay.send(
          ControlMessage.pairWithCode(pairingCode, publicKey: myPublicKeyB64),
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

    // Derive shared secret after pairing succeeds — encryption is mandatory
    if (success) {
      final daemonPkBytes = base64Decode(daemonPublicKeyB64);
      final crypto = CryptoService();
      await crypto.deriveKey(
        myKeyPair: myKeyPair,
        peerPublicKeyBytes: daemonPkBytes,
      );
      relay.setCrypto(crypto);
      dev.log('E2E encryption established', name: 'Ferlay');
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
