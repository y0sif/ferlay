import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/connection_state.dart';
import '../models/session.dart';
import '../providers/connection_provider.dart';
import '../providers/sessions_provider.dart';
import '../services/relay_service.dart';
import '../widgets/status_badge.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = ModalRoute.of(context)!.settings.arguments as Session;
    final theme = Theme.of(context);
    final connState = ref.watch(connectionProvider);

    // Watch for live updates
    final sessions = ref.watch(sessionsProvider);
    final session = sessions.where((s) => s.id == arg.id).firstOrNull ?? arg;

    final canSendCommands = connState.relay == RelayConnectionState.connected &&
        connState.daemon != DaemonState.offline;

    return Scaffold(
      appBar:
          AppBar(title: Text(session.name.isNotEmpty ? session.name : 'Session')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Status chip
          Row(
            children: [
              StatusBadge(status: session.status),
              const Spacer(),
              Text(
                session.id.length > 8 ? session.id.substring(0, 8) : session.id,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Directory
          if (session.directory.isNotEmpty) ...[
            _infoRow(
                theme, Icons.folder_outlined, 'Directory', session.directory),
            const SizedBox(height: 16),
          ],

          // Session options
          if (session.permissionMode != null &&
              session.permissionMode != 'default') ...[
            _infoRow(theme, Icons.shield_outlined, 'Permission Mode',
                session.permissionMode!),
            const SizedBox(height: 16),
          ],

          // URL section - prominent card
          if (session.url != null) ...[
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link, size: 18,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Session URL',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      session.url!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: session.url!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('URL copied to clipboard')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy URL'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Error card
          if (session.error != null) ...[
            Card(
              elevation: 0,
              color: theme.colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 20,
                        color: theme.colorScheme.onError),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        session.error!,
                        style: TextStyle(color: theme.colorScheme.onError),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          const SizedBox(height: 16),

          // Open in Claude button — full-width filled, prominent
          if (session.url != null) ...[
            FilledButton.icon(
              onPressed: () => _openInClaude(context, session.url!),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in Claude'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Stop button — disabled when relay disconnected or daemon offline
          if (session.status == SessionStatus.starting ||
              session.status == SessionStatus.ready ||
              session.status == SessionStatus.active)
            OutlinedButton.icon(
              onPressed: canSendCommands
                  ? () => _confirmStop(context, ref, session.id)
                  : null,
              icon: const Icon(Icons.stop),
              label: Text(canSendCommands
                  ? 'Stop Session'
                  : 'Stop Session (offline)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(
      ThemeData theme, IconData icon, String label, String value) {
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
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openInClaude(BuildContext context, String url) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(url);
    final opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open URL')),
      );
    }
  }

  void _confirmStop(BuildContext context, WidgetRef ref, String sessionId) {
    HapticFeedback.lightImpact();
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
              HapticFeedback.mediumImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Session stopped')),
              );
            },
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
