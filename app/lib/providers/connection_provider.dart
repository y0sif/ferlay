import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_state.dart';
import '../services/relay_service.dart';
import 'relay_provider.dart';

/// Manages the combined three-layer connection state:
/// relay WebSocket + daemon heartbeat + encryption.
class ConnectionNotifier extends Notifier<AppConnectionState> {
  StreamSubscription<RelayConnectionState>? _relaySub;
  StreamSubscription<EncryptionState>? _encryptionSub;

  @override
  AppConnectionState build() {
    final relay = ref.watch(relayServiceProvider);

    _relaySub?.cancel();
    _relaySub = relay.stateStream.listen((relayState) {
      state = state.copyWith(relay: relayState);

      // When relay disconnects, daemon state is unknown
      if (relayState == RelayConnectionState.disconnected) {
        state = state.copyWith(daemon: DaemonState.unknown);
      }
    });

    _encryptionSub?.cancel();
    _encryptionSub = relay.encryptionStateStream.listen((encState) {
      state = state.copyWith(encryption: encState);
    });

    ref.onDispose(() {
      _relaySub?.cancel();
      _encryptionSub?.cancel();
    });

    // Initialize with current values
    return AppConnectionState(
      relay: relay.state,
      encryption: relay.encryptionState,
    );
  }

  /// Update daemon state (called from heartbeat logic).
  void setDaemonState(DaemonState daemonState) {
    state = state.copyWith(daemon: daemonState);
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, AppConnectionState>(
  ConnectionNotifier.new,
);
