import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_state.dart';
import '../models/relay_message.dart';
import '../services/relay_service.dart';
import 'relay_provider.dart';

/// Manages the combined three-layer connection state:
/// relay WebSocket + daemon heartbeat + encryption.
class ConnectionNotifier extends Notifier<AppConnectionState> {
  StreamSubscription<RelayConnectionState>? _relaySub;
  StreamSubscription<EncryptionState>? _encryptionSub;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  DateTime? _lastPongTime;

  static const _pingInterval = Duration(seconds: 15);
  static const _pongTimeout = Duration(seconds: 10);

  @override
  AppConnectionState build() {
    final relay = ref.watch(relayServiceProvider);

    _relaySub?.cancel();
    _relaySub = relay.stateStream.listen((relayState) {
      state = state.copyWith(relay: relayState);

      if (relayState == RelayConnectionState.connected) {
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        state = state.copyWith(daemon: DaemonState.unknown);
      }
    });

    _encryptionSub?.cancel();
    _encryptionSub = relay.encryptionStateStream.listen((encState) {
      state = state.copyWith(encryption: encState);

      // Start heartbeat when encryption is established and relay is connected
      if (encState == EncryptionState.established &&
          state.relay == RelayConnectionState.connected) {
        _startHeartbeat();
      }
    });

    _messageSub?.cancel();
    _messageSub = relay.incoming.listen(_handleMessage);

    ref.onDispose(() {
      _relaySub?.cancel();
      _encryptionSub?.cancel();
      _messageSub?.cancel();
      _stopHeartbeat();
    });

    // Initialize with current values
    return AppConnectionState(
      relay: relay.state,
      encryption: relay.encryptionState,
    );
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'pong') {
      _lastPongTime = DateTime.now();
      _pongTimeoutTimer?.cancel();
      if (state.daemon != DaemonState.online) {
        state = state.copyWith(daemon: DaemonState.online);
      }
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();

    // Only send pings if encryption is established
    if (state.encryption != EncryptionState.established) return;

    // Send first ping immediately
    _sendPing();

    _heartbeatTimer = Timer.periodic(_pingInterval, (_) {
      _sendPing();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
  }

  void _sendPing() {
    final relay = ref.read(relayServiceProvider);
    if (relay.state != RelayConnectionState.connected) return;
    if (relay.encryptionState != EncryptionState.established) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    relay.sendRelay(AppMessage.ping(timestamp));

    // Start pong timeout
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = Timer(_pongTimeout, () {
      if (state.daemon != DaemonState.offline) {
        state = state.copyWith(daemon: DaemonState.offline);
      }
    });
  }

  /// Last time a pong was received from the daemon.
  DateTime? get lastPongTime => _lastPongTime;

  /// Update daemon state (called externally if needed).
  void setDaemonState(DaemonState daemonState) {
    state = state.copyWith(daemon: daemonState);
  }

  /// Force a heartbeat ping immediately (e.g. after reconnect).
  void sendImmediatePing() {
    _sendPing();
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, AppConnectionState>(
  ConnectionNotifier.new,
);
