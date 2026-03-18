import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/relay_message.dart';
import '../models/session.dart';
import 'relay_provider.dart';

class SessionsNotifier extends Notifier<List<Session>> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  List<Session> build() {
    final relay = ref.watch(relayServiceProvider);
    _sub?.cancel();
    _sub = relay.incoming.listen(_handleMessage);
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'];

    switch (type) {
      case 'session_ready':
        _upsertSession(Session(
          id: msg['session_id'] ?? '',
          name: msg['name'] ?? '',
          directory: '',
          status: SessionStatus.ready,
          url: msg['url'],
        ));
      case 'session_status':
        _updateStatus(
          msg['session_id'] ?? '',
          SessionStatus.fromString(msg['status'] ?? ''),
          msg['error'],
        );
      case 'sessions_list':
        final list = (msg['sessions'] as List<dynamic>?)
                ?.map((s) => Session.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [];
        state = list;
    }
  }

  void _upsertSession(Session session) {
    final idx = state.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      final updated = List<Session>.from(state);
      updated[idx] = session;
      state = updated;
    } else {
      state = [...state, session];
    }
  }

  void _updateStatus(String sessionId, SessionStatus status, String? error) {
    state = state.map((s) {
      if (s.id == sessionId) {
        return s.copyWith(status: status, error: error);
      }
      return s;
    }).toList();
  }

  void startSession({required String directory, required String name}) {
    ref.read(relayServiceProvider).sendRelay(AppMessage.startSession(
          directory: directory,
          name: name,
        ));
  }

  void stopSession(String sessionId) {
    ref.read(relayServiceProvider).sendRelay(AppMessage.stopSession(sessionId));
  }

  void refreshSessions() {
    ref.read(relayServiceProvider).sendRelay(AppMessage.listSessions());
  }
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, List<Session>>(
  SessionsNotifier.new,
);
