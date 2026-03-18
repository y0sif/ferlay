import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/relay_message.dart';
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
        ref.read(relayServiceProvider).connect(relayUrl);
      }
    } else {
      state = PairingState.unpaired;
    }
  }

  Future<void> startPairing(String relayUrl, String pairingCode) async {
    state = PairingState.pairing;

    final relay = ref.read(relayServiceProvider);
    await StorageService.setRelayUrl(relayUrl);
    await relay.connect(relayUrl);

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

    if (success) {
      state = PairingState.paired;
    } else {
      await StorageService.clearPairing();
      state = PairingState.unpaired;
    }
  }

  Future<void> unpair() async {
    await StorageService.clearPairing();
    state = PairingState.unpaired;
  }
}

final authProvider = NotifierProvider<AuthNotifier, PairingState>(
  AuthNotifier.new,
);
