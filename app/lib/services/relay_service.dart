import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/relay_message.dart';
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

  final _incomingController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<RelayConnectionState>.broadcast();

  Stream<Map<String, dynamic>> get incoming => _incomingController.stream;
  Stream<RelayConnectionState> get stateStream => _stateController.stream;
  RelayConnectionState get state => _state;

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
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _incomingController.add(json);
    } catch (_) {}
  }

  void send(ControlMessage msg) {
    _channel?.sink.add(msg.toJson());
  }

  void sendRelay(Map<String, dynamic> payload) {
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
  }
}
