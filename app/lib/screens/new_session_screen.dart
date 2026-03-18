import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';
import '../providers/sessions_provider.dart';

class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _directoryController = TextEditingController(text: '~/Projects/');
  final _nameController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _directoryController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _startSession() {
    final directory = _directoryController.text.trim();
    final name = _nameController.text.trim();

    if (directory.isEmpty) return;

    setState(() => _loading = true);

    ref.read(sessionsProvider.notifier).startSession(
          directory: directory,
          name: name.isNotEmpty ? name : 'session',
        );

    // Timeout after 30s
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _loading) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session start timed out')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch for new ready sessions and navigate
    ref.listen(sessionsProvider, (prev, next) {
      if (!_loading) return;
      final prevIds = prev?.map((s) => s.id).toSet() ?? {};
      final newReady = next.where(
          (s) => s.status == SessionStatus.ready && !prevIds.contains(s.id));
      if (newReady.isNotEmpty) {
        setState(() => _loading = false);
        Navigator.of(context).pushReplacementNamed(
          '/sessions/detail',
          arguments: newReady.first,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('New Session')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _directoryController,
              decoration: const InputDecoration(
                labelText: 'Directory',
                hintText: '~/Projects/my-app',
                prefixIcon: Icon(Icons.folder),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Session Name (optional)',
                hintText: 'refactor',
                prefixIcon: Icon(Icons.label),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _startSession,
              icon: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_loading ? 'Starting...' : 'Start Session'),
            ),
          ],
        ),
      ),
    );
  }
}
