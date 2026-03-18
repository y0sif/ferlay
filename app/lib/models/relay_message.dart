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
  }) {
    return ControlMessage(
      type: 'register',
      data: {
        'type': 'register',
        'device_id': deviceId,
        // ignore: use_null_aware_elements
        if (fcmToken != null) 'fcm_token': fcmToken,
      },
    );
  }

  static ControlMessage pairWithCode(String code) {
    return ControlMessage(
      type: 'pair_with_code',
      data: {'type': 'pair_with_code', 'code': code},
    );
  }

  static ControlMessage relay(Map<String, dynamic> payload) {
    return ControlMessage(
      type: 'relay',
      data: {'type': 'relay', 'payload': payload},
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
}
