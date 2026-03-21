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
  StreamSubscription<RelayConnectionState>? _disconnectSub;

  @override
  void dispose() {
    _directoryController.dispose();
    _nameController.dispose();
    _disconnectSub?.cancel();
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

    setState(() => _loading = true);
    HapticFeedback.lightImpact();

    ref.read(sessionsProvider.notifier).startSession(
          directory: directory,
          name: name.isNotEmpty ? name : 'session',
        );

    // Watch for disconnection while waiting
    _disconnectSub?.cancel();
    _disconnectSub =
        ref.read(relayServiceProvider).stateStream.listen((relayState) {
      if (relayState == RelayConnectionState.disconnected && _loading) {
        setState(() => _loading = false);
        _disconnectSub?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Connection lost while starting session')),
          );
        }
      }
    });

    // Timeout after 20s
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _loading) {
        setState(() => _loading = false);
        _disconnectSub?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(connectionProvider);

    // Watch for new ready sessions and navigate
    ref.listen(sessionsProvider, (prev, next) {
      if (!_loading) return;
      final prevIds = prev?.map((s) => s.id).toSet() ?? {};
      final newReady = next.where(
          (s) => s.status == SessionStatus.ready && !prevIds.contains(s.id));
      if (newReady.isNotEmpty) {
        setState(() => _loading = false);
        _disconnectSub?.cancel();
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
                decoration: const InputDecoration(
                  labelText: 'Session Name (optional)',
                  hintText: 'refactor',
                  helperText: 'Defaults to "session" if empty',
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
                    ? 'Starting...'
                    : connState.canStartSession
                        ? 'Start Session'
                        : connState.disabledReason ?? 'Cannot start'),
              ),
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
