import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/relay_message.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

enum RelayConnectionState { disconnected, connecting, connected }

class RelayService {
  WebSocketChannel? _channel;
  RelayConnectionState _state = RelayConnectionState.disconnected;
  String? _relayUrl;
  String? _deviceId;
  int _backoff = 1;
  Timer? _reconnectTimer;
  bool _disposed = false;

  CryptoService? _crypto;

  final _incomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<RelayConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get incoming => _incomingController.stream;
  Stream<RelayConnectionState> get stateStream => _stateController.stream;
  Stream<String> get errors => _errorController.stream;
  RelayConnectionState get state => _state;

  /// Sets the crypto service for encrypting/decrypting relay payloads.
  void setCrypto(CryptoService crypto) {
    _crypto = crypto;
  }

  Future<void> connect(String relayUrl) async {
    _relayUrl = relayUrl;
    _deviceId = await StorageService.getDeviceId();
    _doConnect();
  }

  void _doConnect() {
    if (_disposed || _relayUrl == null) return;

    _setState(RelayConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_relayUrl!));

      _channel!.stream.listen(
        (data) {
          _backoff = 1;
          if (_state != RelayConnectionState.connected) {
            _setState(RelayConnectionState.connected);
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

      // Register with relay
      final register = ControlMessage.register(deviceId: _deviceId!);
      _channel!.sink.add(register.toJson());
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        // Check if this is a relay message with an encrypted payload
        if (decoded['type'] == 'relay' && decoded['payload'] is String) {
          if (_crypto != null && _crypto!.isReady) {
            _decryptAndEmit(decoded['payload'] as String);
          } else {
            _emitError('Received encrypted message but no encryption key established');
          }
          return;
        }
        // Control messages (register, paired, error, etc.) are not encrypted
        _incomingController.add(decoded);
      } else if (decoded is String && _crypto != null && _crypto!.isReady) {
        // Encrypted relay payload (JSON string containing base64 blob)
        _decryptAndEmit(decoded);
      } else if (decoded is String) {
        _emitError('Received encrypted message but no encryption key established');
      }
    } catch (_) {}
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

  void _scheduleReconnect() {
    _channel = null;
    _setState(RelayConnectionState.disconnected);
    if (_disposed) return;

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
  }
}
