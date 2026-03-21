import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/relay_message.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

enum RelayConnectionState { disconnected, connecting, connected }

/// Encryption lifecycle state, exposed to the UI.
enum EncryptionState {
  /// No encryption keys established yet.
  notEstablished,
  /// Key exchange in progress.
  establishing,
  /// Encryption verified and active.
  established,
  /// Key derivation or verification failed.
  failed,
}

class RelayService {
  WebSocketChannel? _channel;
  RelayConnectionState _state = RelayConnectionState.disconnected;
  String? _relayUrl;
  String? _deviceId;
  String? _pairedDeviceId;
  int _backoff = 1;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _wasConnected = false;
  bool _intentionalClose = false;

  CryptoService? _crypto;
  EncryptionState _encryptionState = EncryptionState.notEstablished;

  /// Buffer for encrypted messages that arrive before crypto is ready.
  /// These are replayed once setCrypto() is called.
  final List<String> _pendingEncrypted = [];

  final _incomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<RelayConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _encryptionStateController = StreamController<EncryptionState>.broadcast();
  /// Emits events when reconnection occurs (true = reconnected, false = lost).
  final _reconnectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get incoming => _incomingController.stream;
  Stream<RelayConnectionState> get stateStream => _stateController.stream;
  Stream<String> get errors => _errorController.stream;
  Stream<EncryptionState> get encryptionStateStream => _encryptionStateController.stream;
  Stream<bool> get reconnectionStream => _reconnectionController.stream;
  RelayConnectionState get state => _state;
  EncryptionState get encryptionState => _encryptionState;
  int get reconnectAttempts => _reconnectAttempts;

  /// Sets the crypto service for encrypting/decrypting relay payloads.
  /// Also replays any encrypted messages that arrived before crypto was ready.
  void setCrypto(CryptoService crypto) {
    _crypto = crypto;
    _setEncryptionState(EncryptionState.establishing);

    // Replay any encrypted messages that were buffered before crypto was ready
    if (_pendingEncrypted.isNotEmpty) {
      final buffered = List<String>.from(_pendingEncrypted);
      _pendingEncrypted.clear();
      for (final encrypted in buffered) {
        _decryptAndEmit(encrypted);
      }
    }
  }

  /// Marks encryption as verified and working.
  void markEncryptionEstablished() {
    _setEncryptionState(EncryptionState.established);
  }

  /// Marks encryption as failed.
  void markEncryptionFailed() {
    _setEncryptionState(EncryptionState.failed);
  }

  void _setEncryptionState(EncryptionState s) {
    _encryptionState = s;
    if (!_encryptionStateController.isClosed) {
      _encryptionStateController.add(s);
    }
  }

  Future<void> connect(String relayUrl) async {
    // Close existing connection first to avoid zombie WebSockets.
    // Mark as intentional so onDone doesn't trigger auto-reconnect.
    _reconnectTimer?.cancel();
    if (_channel != null) {
      _intentionalClose = true;
      _channel!.sink.close();
      _channel = null;
    }

    _relayUrl = relayUrl;
    _deviceId = await StorageService.getDeviceId();
    _pairedDeviceId = await StorageService.getPairedDeviceId();
    _doConnect();
  }

  void _doConnect() {
    if (_disposed || _relayUrl == null) return;

    _intentionalClose = false;
    _setState(RelayConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_relayUrl!));

      _channel!.stream.listen(
        (data) {
          _backoff = 1;
          if (_state != RelayConnectionState.connected) {
            final wasReconnect = _wasConnected;
            _setState(RelayConnectionState.connected);
            _reconnectAttempts = 0;
            if (wasReconnect && !_reconnectionController.isClosed) {
              _reconnectionController.add(true); // reconnected
            }
            _wasConnected = true;
          }
          _handleMessage(data.toString());
        },
        onError: (error) {
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
      );

      // Register with relay (include paired device ID to restore pairing after relay restart)
      final register = ControlMessage.register(
        deviceId: _deviceId!,
        pairedDeviceId: _pairedDeviceId,
      );
      _channel!.sink.add(register.toJson());
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        final type = decoded['type'];

        // Check if this is a relay message with an encrypted payload
        if (type == 'relay' && decoded['payload'] is String) {
          final encrypted = decoded['payload'] as String;
          if (_crypto != null && _crypto!.isReady) {
            _decryptAndEmit(encrypted);
          } else {
            _pendingEncrypted.add(encrypted);
          }
          return;
        }
        // Relay messages with unencrypted JSON payload (e.g. KeyExchange before crypto)
        if (type == 'relay' && decoded['payload'] is Map<String, dynamic>) {
          _incomingController.add(decoded['payload'] as Map<String, dynamic>);
          return;
        }
        // Control messages (register, paired, error, etc.) are not encrypted
        _incomingController.add(decoded);
      } else if (decoded is String) {
        // Raw encrypted payload (base64 blob sent by relay as forwarded payload)
        if (_crypto != null && _crypto!.isReady) {
          _decryptAndEmit(decoded);
        } else {
          _pendingEncrypted.add(decoded);
        }
      }
    } catch (e) {
      _emitError('Failed to handle message: $e');
    }
  }

  Future<void> _decryptAndEmit(String encrypted) async {
    try {
      final plaintext = await _crypto!.decrypt(encrypted);
      final json = jsonDecode(plaintext) as Map<String, dynamic>;
      _incomingController.add(json);
    } catch (e) {
      _emitError('Failed to decrypt message from daemon: $e');
    }
  }

  void _emitError(String message) {
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }

  void send(ControlMessage msg) {
    _channel?.sink.add(msg.toJson());
  }

  /// Sends an app-level message via relay. Encryption is mandatory.
  /// Throws if no encryption key is available or encryption fails.
  void sendRelay(Map<String, dynamic> payload) {
    if (_crypto == null || !_crypto!.isReady) {
      _emitError('Cannot send message: no encryption key established');
      return;
    }
    _sendEncrypted(payload);
  }

  Future<void> _sendEncrypted(Map<String, dynamic> payload) async {
    try {
      final plaintext = jsonEncode(payload);
      final encrypted = await _crypto!.encrypt(plaintext);
      send(ControlMessage.relayEncrypted(encrypted));
    } catch (e) {
      _emitError('Encryption failed, message not sent: $e');
    }
  }

  /// Sends an unencrypted relay message (used for key exchange before encryption is set up).
  void sendRelayUnencrypted(Map<String, dynamic> payload) {
    send(ControlMessage.relay(payload));
  }

  /// Force-reconnect the WebSocket (e.g. from a Retry button or app foreground).
  Future<void> reconnect() async {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _backoff = 1;
    // Reload paired device ID in case it changed
    _pairedDeviceId = await StorageService.getPairedDeviceId();
    _doConnect();
  }

  void _scheduleReconnect() {
    _channel = null;
    // Don't auto-reconnect if we intentionally closed (e.g. connect() replacing the connection)
    if (_intentionalClose || _disposed) return;

    _setState(RelayConnectionState.disconnected);
    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoff), () {
      _backoff = (_backoff * 2).clamp(1, 30);
      _doConnect();
    });
  }

  void _setState(RelayConnectionState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _incomingController.close();
    _stateController.close();
    _errorController.close();
    _encryptionStateController.close();
    _reconnectionController.close();
  }
}
