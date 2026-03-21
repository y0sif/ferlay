import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/relay_service.dart';

final relayServiceProvider = Provider<RelayService>((ref) {
  final service = RelayService();
  ref.onDispose(() => service.dispose());
  return service;
});

final relayStateProvider = StreamProvider<RelayConnectionState>((ref) {
  final relay = ref.watch(relayServiceProvider);
  return relay.stateStream;
});

final encryptionStateProvider = StreamProvider<EncryptionState>((ref) {
  final relay = ref.watch(relayServiceProvider);
  return relay.encryptionStateStream;
});
