import 'dart:convert';

/// Control-level messages (register, pair, relay wrapper).
/// Mirrors furlay-shared ControlMessage.
class ControlMessage {
  final String type;
  final Map<String, dynamic> data;

  const ControlMessage({required this.type, required this.data});

  factory ControlMessage.fromJson(Map<String, dynamic> json) {
    return ControlMessage(type: json['type'] ?? '', data: json);
  }

  String toJson() => jsonEncode(data);

  static ControlMessage register({
    required String deviceId,
    String? fcmToken,
    String? pairedDeviceId,
  }) {
    return ControlMessage(
      type: 'register',
      data: {
        'type': 'register',
        'device_id': deviceId,
        if (fcmToken != null) 'fcm_token': fcmToken,
        if (pairedDeviceId != null) 'paired_device_id': pairedDeviceId,
      },
    );
  }

  static ControlMessage pairWithCode(String code, {String? publicKey}) {
    return ControlMessage(
      type: 'pair_with_code',
      data: {
        'type': 'pair_with_code',
        'code': code,
        if (publicKey != null) 'public_key': publicKey,
      },
    );
  }

  static ControlMessage relay(Map<String, dynamic> payload) {
    return ControlMessage(
      type: 'relay',
      data: {'type': 'relay', 'payload': payload},
    );
  }

  /// Sends an encrypted payload as a relay message.
  /// The payload is a base64-encoded encrypted string.
  static ControlMessage relayEncrypted(String encryptedPayload) {
    return ControlMessage(
      type: 'relay',
      data: {'type': 'relay', 'payload': encryptedPayload},
    );
  }
}

/// App-level messages (start_session, stop_session, etc.).
/// These are sent/received inside the relay payload.
class AppMessage {
  static Map<String, dynamic> startSession({
    required String directory,
    required String name,
  }) {
    return {
      'type': 'start_session',
      'directory': directory,
      'name': name,
    };
  }

  static Map<String, dynamic> stopSession(String sessionId) {
    return {
      'type': 'stop_session',
      'session_id': sessionId,
    };
  }

  static Map<String, dynamic> listSessions() {
    return {'type': 'list_sessions'};
  }

  static Map<String, dynamic> keyExchange(String publicKey) {
    return {
      'type': 'key_exchange',
      'public_key': publicKey,
    };
  }

  static Map<String, dynamic> encryptionVerifyAck(String challenge) {
    return {
      'type': 'encryption_verify_ack',
      'challenge': challenge,
    };
  }

  static Map<String, dynamic> ping(int timestamp) {
    return {
      'type': 'ping',
      'timestamp': timestamp,
    };
  }
}
