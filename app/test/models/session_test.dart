import 'package:flutter_test/flutter_test.dart';
import 'package:ferlay/models/session.dart';

void main() {
  group('SessionStatus', () {
    test('fromString maps known statuses', () {
      expect(SessionStatus.fromString('starting'), SessionStatus.starting);
      expect(SessionStatus.fromString('ready'), SessionStatus.ready);
      expect(SessionStatus.fromString('active'), SessionStatus.active);
      expect(SessionStatus.fromString('finished'), SessionStatus.finished);
      expect(SessionStatus.fromString('crashed'), SessionStatus.crashed);
    });

    test('fromString defaults to starting for unknown', () {
      expect(SessionStatus.fromString('bogus'), SessionStatus.starting);
      expect(SessionStatus.fromString(''), SessionStatus.starting);
    });

    test('label returns capitalized name', () {
      expect(SessionStatus.starting.label, 'Starting');
      expect(SessionStatus.ready.label, 'Ready');
      expect(SessionStatus.active.label, 'Active');
      expect(SessionStatus.finished.label, 'Finished');
      expect(SessionStatus.crashed.label, 'Crashed');
    });
  });

  group('Session', () {
    test('fromJson with session_id key', () {
      final session = Session.fromJson({
        'session_id': 'abc-123',
        'name': 'test',
        'directory': '/tmp',
        'status': 'ready',
        'url': 'https://claude.ai/code?bridge=env_xyz',
      });

      expect(session.id, 'abc-123');
      expect(session.name, 'test');
      expect(session.directory, '/tmp');
      expect(session.status, SessionStatus.ready);
      expect(session.url, 'https://claude.ai/code?bridge=env_xyz');
    });

    test('fromJson with id key (sessions_list format)', () {
      final session = Session.fromJson({
        'id': 'def-456',
        'name': 'refactor',
        'directory': '~/Projects',
        'status': 'active',
      });

      expect(session.id, 'def-456');
      expect(session.url, isNull);
    });

    test('fromJson handles missing fields gracefully', () {
      final session = Session.fromJson({});

      expect(session.id, '');
      expect(session.name, '');
      expect(session.directory, '');
      expect(session.status, SessionStatus.starting);
      expect(session.url, isNull);
      expect(session.error, isNull);
    });

    test('copyWith overrides specified fields', () {
      final original = Session(
        id: '1',
        name: 'orig',
        directory: '/tmp',
        status: SessionStatus.starting,
      );

      final updated = original.copyWith(
        status: SessionStatus.ready,
        url: 'https://example.com',
      );

      expect(updated.id, '1');
      expect(updated.name, 'orig');
      expect(updated.status, SessionStatus.ready);
      expect(updated.url, 'https://example.com');
    });

    test('copyWith preserves unspecified fields', () {
      final original = Session(
        id: '1',
        name: 'test',
        directory: '/home',
        status: SessionStatus.crashed,
        error: 'failed',
      );

      final updated = original.copyWith(status: SessionStatus.finished);

      expect(updated.error, 'failed');
      expect(updated.directory, '/home');
    });
  });
}
