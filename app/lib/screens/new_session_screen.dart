import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';
import '../providers/connection_provider.dart';
import '../providers/relay_provider.dart';
import '../providers/sessions_provider.dart';
import '../services/relay_service.dart';

class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _directoryController = TextEditingController(text: '~/Projects/');
  final _nameController = TextEditingController();
  bool _loading = false;
  String _loadingMessage = '';
  StreamSubscription<RelayConnectionState>? _disconnectSub;
  Timer? _progressTimer;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _directoryController.dispose();
    _nameController.dispose();
    _disconnectSub?.cancel();
    _progressTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  String? _validateDirectory(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Directory is required';
    }
    final trimmed = value.trim();
    if (!trimmed.startsWith('/') && !trimmed.startsWith('~/')) {
      return 'Directory must be an absolute path (start with / or ~/)';
    }
    return null;
  }

  void _startSession() {
    if (!_formKey.currentState!.validate()) return;

    final directory = _directoryController.text.trim();
    final name = _nameController.text.trim();

    final connState = ref.read(connectionProvider);
    if (!connState.canStartSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(connState.disabledReason ?? 'Cannot start session')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _loadingMessage = 'Sending to daemon...';
    });
    HapticFeedback.lightImpact();

    ref.read(sessionsProvider.notifier).startSession(
          directory: directory,
          name: name.isNotEmpty ? name : 'session',
        );

    // Progressive loading messages
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _loading) {
        setState(() => _loadingMessage = 'Daemon is starting Claude...');
      }
    });
    Timer(const Duration(seconds: 8), () {
      if (mounted && _loading) {
        setState(() => _loadingMessage = 'Waiting for session URL...');
      }
    });
    Timer(const Duration(seconds: 14), () {
      if (mounted && _loading) {
        setState(() => _loadingMessage =
            'Taking longer than usual. Check that the daemon is running.');
      }
    });

    // Watch for disconnection while waiting
    _disconnectSub?.cancel();
    _disconnectSub =
        ref.read(relayServiceProvider).stateStream.listen((relayState) {
      if (relayState == RelayConnectionState.disconnected && _loading) {
        _cancelLoading();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Connection lost while starting session')),
          );
        }
      }
    });

    // Timeout after 20s
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _loading) {
        _cancelLoading();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Session start timed out. Check: daemon running, directory exists, Claude installed.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    });
  }

  void _cancelLoading() {
    setState(() {
      _loading = false;
      _loadingMessage = '';
    });
    _disconnectSub?.cancel();
    _progressTimer?.cancel();
    _timeoutTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(connectionProvider);

    // Watch for new sessions (ready → navigate, crashed → show error)
    ref.listen(sessionsProvider, (prev, next) {
      if (!_loading) return;
      final prevIds = prev?.map((s) => s.id).toSet() ?? {};
      final newSessions =
          next.where((s) => !prevIds.contains(s.id)).toList();

      // Check for crashed sessions first (e.g. invalid directory error)
      final newCrashed = newSessions
          .where((s) => s.status == SessionStatus.crashed)
          .toList();
      if (newCrashed.isNotEmpty) {
        _cancelLoading();
        final errorMsg =
            newCrashed.first.error ?? 'Session failed to start';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            duration: const Duration(seconds: 5),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      // Check for ready sessions → navigate to detail
      final newReady = newSessions
          .where((s) => s.status == SessionStatus.ready)
          .toList();
      if (newReady.isNotEmpty) {
        _cancelLoading();
        Navigator.of(context).pushReplacementNamed(
          '/sessions/detail',
          arguments: newReady.first,
        );
      }
    });

    final canStart = connState.canStartSession && !_loading;

    return Scaffold(
      appBar: AppBar(title: const Text('New Session')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _directoryController,
                validator: _validateDirectory,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Directory',
                  hintText: '~/Projects/my-app',
                  prefixIcon: Icon(Icons.folder),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Session Name',
                  hintText: 'e.g. refactor, bugfix, feature',
                  helperText: 'Optional \u2014 defaults to "session"',
                  prefixIcon: Icon(Icons.label),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: canStart ? _startSession : null,
                icon: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_loading
                    ? _loadingMessage
                    : connState.canStartSession
                        ? 'Start Session'
                        : connState.disabledReason ?? 'Cannot start'),
              ),
              if (_loading) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cancelLoading,
                  child: const Text('Cancel'),
                ),
              ],
              if (!connState.canStartSession && !_loading) ...[
                const SizedBox(height: 8),
                Text(
                  connState.disabledReason ?? 'Cannot start session',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
