import '../services/relay_service.dart';

/// Daemon liveness state, determined via periodic heartbeat ping/pong.
enum DaemonState {
  /// Haven't received a heartbeat response yet.
  unknown,

  /// Daemon confirmed alive (heartbeat pong received recently).
  online,

  /// Daemon hasn't responded to heartbeat within the timeout window.
  offline,
}

/// Combined connection state of the three independent layers.
class AppConnectionState {
  final RelayConnectionState relay;
  final DaemonState daemon;
  final EncryptionState encryption;

  const AppConnectionState({
    this.relay = RelayConnectionState.disconnected,
    this.daemon = DaemonState.unknown,
    this.encryption = EncryptionState.notEstablished,
  });

  /// Whether all preconditions are met to start/manage sessions.
  bool get canStartSession =>
      relay == RelayConnectionState.connected &&
      daemon == DaemonState.online &&
      encryption == EncryptionState.established;

  /// Human-readable reason why sessions cannot be started, or null if they can.
  String? get disabledReason {
    if (relay == RelayConnectionState.disconnected) {
      return 'Not connected to relay';
    }
    if (relay == RelayConnectionState.connecting) {
      return 'Connecting to relay...';
    }
    if (encryption == EncryptionState.notEstablished) {
      return 'Encryption not established';
    }
    if (encryption == EncryptionState.failed) {
      return 'Encryption failed — try re-pairing';
    }
    if (encryption == EncryptionState.establishing) {
      return 'Establishing encryption...';
    }
    if (daemon == DaemonState.unknown) {
      return 'Checking daemon status...';
    }
    if (daemon == DaemonState.offline) {
      return 'Daemon is offline';
    }
    return null;
  }

  AppConnectionState copyWith({
    RelayConnectionState? relay,
    DaemonState? daemon,
    EncryptionState? encryption,
  }) {
    return AppConnectionState(
      relay: relay ?? this.relay,
      daemon: daemon ?? this.daemon,
      encryption: encryption ?? this.encryption,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConnectionState &&
          relay == other.relay &&
          daemon == other.daemon &&
          encryption == other.encryption;

  @override
  int get hashCode => Object.hash(relay, daemon, encryption);
}
