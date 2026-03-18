import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/session.dart';
import '../providers/sessions_provider.dart';
import '../widgets/status_badge.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = ModalRoute.of(context)!.settings.arguments as Session;
    final theme = Theme.of(context);

    // Watch for live updates
    final sessions = ref.watch(sessionsProvider);
    final session = sessions.where((s) => s.id == arg.id).firstOrNull ?? arg;

    return Scaffold(
      appBar: AppBar(title: Text(session.name.isNotEmpty ? session.name : 'Session')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status
            Row(
              children: [
                Text('Status:', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                StatusBadge(status: session.status),
              ],
            ),
            const SizedBox(height: 20),

            // Directory
            if (session.directory.isNotEmpty) ...[
              _infoRow(theme, Icons.folder_outlined, 'Directory', session.directory),
              const SizedBox(height: 12),
            ],

            // Session ID
            _infoRow(theme, Icons.tag, 'Session ID', session.id),
            const SizedBox(height: 12),

            // URL
            if (session.url != null) ...[
              _infoRow(theme, Icons.link, 'URL', session.url!),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: session.url!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL copied')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy URL'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Error
            if (session.error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  session.error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Spacer(),

            // Open in Claude button
            if (session.url != null &&
                (session.status == SessionStatus.ready ||
                    session.status == SessionStatus.active)) ...[
              FilledButton.icon(
                onPressed: () => _openInClaude(context, session.url!),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Claude'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Stop button
            if (session.status == SessionStatus.starting ||
                session.status == SessionStatus.ready ||
                session.status == SessionStatus.active)
              OutlinedButton.icon(
                onPressed: () => _confirmStop(context, ref, session.id),
                icon: const Icon(Icons.stop),
                label: const Text('Stop Session'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openInClaude(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open URL')),
      );
    }
  }

  void _confirmStop(BuildContext context, WidgetRef ref, String sessionId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Session'),
        content: const Text('Are you sure you want to stop this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(sessionsProvider.notifier).stopSession(sessionId);
              Navigator.of(ctx).pop();
            },
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
