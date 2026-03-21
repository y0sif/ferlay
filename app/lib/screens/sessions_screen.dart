import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/relay_provider.dart';
import '../providers/sessions_provider.dart';
import '../services/relay_service.dart';
import '../widgets/session_card.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  @override
  void initState() {
    super.initState();
    // Request sessions list on load
    Future.microtask(() {
      ref.read(sessionsProvider.notifier).refreshSessions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final relayState = ref.watch(relayStateProvider);
    final encryptionState = ref.watch(encryptionStateProvider);
    final theme = Theme.of(context);

    // Haptic feedback when a session becomes ready
    ref.listen(sessionsProvider, (prev, next) {
      if (prev == null) return;
      final prevIds = prev.where((s) => s.status.name == 'ready').map((s) => s.id).toSet();
      final newReady = next.where(
        (s) => s.status.name == 'ready' && !prevIds.contains(s.id),
      );
      if (newReady.isNotEmpty) {
        HapticFeedback.mediumImpact();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          relayState.when(
            data: (s) => switch (s) {
              RelayConnectionState.disconnected => _ConnectionBanner(
                  message: 'Disconnected from relay',
                  color: theme.colorScheme.errorContainer,
                  textColor: theme.colorScheme.onErrorContainer,
                  icon: Icons.cloud_off,
                  onRetry: () {
                    ref.read(sessionsProvider.notifier).refreshSessions();
                  },
                ),
              RelayConnectionState.connecting => _ConnectionBanner(
                  message: 'Connecting to relay...',
                  color: theme.colorScheme.tertiaryContainer,
                  textColor: theme.colorScheme.onTertiaryContainer,
                  icon: Icons.cloud_sync,
                ),
              RelayConnectionState.connected => const SizedBox.shrink(),
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => _ConnectionBanner(
              message: 'Connection error',
              color: theme.colorScheme.errorContainer,
              textColor: theme.colorScheme.onErrorContainer,
              icon: Icons.error_outline,
            ),
          ),

          // Encryption status banner (only show if not established)
          encryptionState.when(
            data: (s) => switch (s) {
              EncryptionState.failed => _ConnectionBanner(
                  message: 'E2E encryption failed',
                  color: theme.colorScheme.errorContainer,
                  textColor: theme.colorScheme.onErrorContainer,
                  icon: Icons.lock_open,
                ),
              EncryptionState.establishing => _ConnectionBanner(
                  message: 'Establishing encryption...',
                  color: theme.colorScheme.tertiaryContainer,
                  textColor: theme.colorScheme.onTertiaryContainer,
                  icon: Icons.lock_clock,
                ),
              EncryptionState.notEstablished => _ConnectionBanner(
                  message: 'Encryption not established',
                  color: theme.colorScheme.errorContainer,
                  textColor: theme.colorScheme.onErrorContainer,
                  icon: Icons.no_encryption,
                ),
              EncryptionState.established => const SizedBox.shrink(),
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Sessions content
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terminal,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          'No sessions yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + to start a new Claude Code session',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.read(sessionsProvider.notifier).refreshSessions();
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return SessionCard(
                          session: session,
                          onTap: () => Navigator.of(context).pushNamed(
                            '/sessions/detail',
                            arguments: session,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pushNamed('/sessions/new');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final String message;
  final Color color;
  final Color textColor;
  final IconData icon;
  final VoidCallback? onRetry;

  const _ConnectionBanner({
    required this.message,
    required this.color,
    required this.textColor,
    required this.icon,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color,
      child: Row(
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: textColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
