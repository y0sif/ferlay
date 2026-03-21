import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/relay_message.dart';
import '../models/session.dart';
import '../services/storage_service.dart';
import 'relay_provider.dart';

class SessionsNotifier extends Notifier<List<Session>> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  List<Session> build() {
    final relay = ref.watch(relayServiceProvider);
    _sub?.cancel();
    _sub = relay.incoming.listen(_handleMessage);
    ref.onDispose(() => _sub?.cancel());
    _loadCachedSessions();
    return [];
  }

  Future<void> _loadCachedSessions() async {
    final cached = await StorageService.getSessions();
    if (cached != null && state.isEmpty) {
      try {
        final list = (jsonDecode(cached) as List<dynamic>)
            .map((s) => Session.fromJson(s as Map<String, dynamic>))
            .toList();
        state = list;
      } catch (_) {}
    }
  }

  void _persistSessions() {
    final json = jsonEncode(state.map((s) => {
      'id': s.id,
      'name': s.name,
      'directory': s.directory,
      'status': s.status.name,
      if (s.url != null) 'url': s.url,
      if (s.error != null) 'error': s.error,
    }).toList());
    StorageService.setSessions(json);
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
        _persistSessions();
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
    _persistSessions();
  }

  void _updateStatus(String sessionId, SessionStatus status, String? error) {
    final exists = state.any((s) => s.id == sessionId);
    if (exists) {
      state = state.map((s) {
        if (s.id == sessionId) {
          return s.copyWith(status: status, error: error);
        }
        return s;
      }).toList();
    } else {
      // Session was created on daemon side but app hasn't seen it yet
      // (e.g. daemon rejected the directory immediately).
      // Create a placeholder entry so the error is visible.
      state = [
        ...state,
        Session(
          id: sessionId,
          name: 'Session',
          directory: '',
          status: status,
          error: error,
        ),
      ];
    }
    _persistSessions();
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
