import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ferlay/models/relay_message.dart';

void main() {
  group('ControlMessage', () {
    test('register creates correct JSON', () {
      final msg = ControlMessage.register(deviceId: 'dev-1');
      final json = jsonDecode(msg.toJson());

      expect(json['type'], 'register');
      expect(json['device_id'], 'dev-1');
      expect(json.containsKey('fcm_token'), isFalse);
    });

    test('register with fcm token', () {
      final msg =
          ControlMessage.register(deviceId: 'dev-1', fcmToken: 'tok-123');
      final json = jsonDecode(msg.toJson());

      expect(json['fcm_token'], 'tok-123');
    });

    test('pairWithCode creates correct JSON', () {
      final msg = ControlMessage.pairWithCode('ABC123');
      final json = jsonDecode(msg.toJson());

      expect(json['type'], 'pair_with_code');
      expect(json['code'], 'ABC123');
    });

    test('relay wraps payload', () {
      final msg = ControlMessage.relay({'type': 'start_session', 'name': 'x'});
      final json = jsonDecode(msg.toJson());

      expect(json['type'], 'relay');
      expect(json['payload']['type'], 'start_session');
      expect(json['payload']['name'], 'x');
    });

    test('relayEncrypted wraps string payload', () {
      final msg = ControlMessage.relayEncrypted('base64blob==');
      final json = jsonDecode(msg.toJson());

      expect(json['type'], 'relay');
      expect(json['payload'], 'base64blob==');
    });

    test('fromJson parses type correctly', () {
      final msg = ControlMessage.fromJson({
        'type': 'paired',
        'paired_with': 'dev-2',
      });

      expect(msg.type, 'paired');
      expect(msg.data['paired_with'], 'dev-2');
    });
  });

  group('AppMessage', () {
    test('startSession creates correct payload', () {
      final msg =
          AppMessage.startSession(directory: '~/Projects', name: 'test');

      expect(msg['type'], 'start_session');
      expect(msg['directory'], '~/Projects');
      expect(msg['name'], 'test');
    });

    test('stopSession creates correct payload', () {
      final msg = AppMessage.stopSession('session-123');

      expect(msg['type'], 'stop_session');
      expect(msg['session_id'], 'session-123');
    });

    test('listSessions creates correct payload', () {
      final msg = AppMessage.listSessions();

      expect(msg['type'], 'list_sessions');
    });

    test('keyExchange creates correct payload', () {
      final msg = AppMessage.keyExchange('base64pubkey');

      expect(msg['type'], 'key_exchange');
      expect(msg['public_key'], 'base64pubkey');
    });
  });
}
