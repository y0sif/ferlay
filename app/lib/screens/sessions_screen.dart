import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_state.dart';
import '../providers/connection_provider.dart';
import '../providers/relay_provider.dart';
import '../providers/sessions_provider.dart';
import '../services/relay_service.dart';
import '../widgets/session_card.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen>
    with WidgetsBindingObserver {
  bool _showReconnectedBanner = false;
  Timer? _reconnectedBannerTimer;
  StreamSubscription<bool>? _reconnectionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Request sessions list on load
    Future.microtask(() {
      ref.read(sessionsProvider.notifier).refreshSessions();

      // Listen for reconnection events
      final relay = ref.read(relayServiceProvider);
      _reconnectionSub = relay.reconnectionStream.listen((reconnected) {
        if (reconnected && mounted) {
          // Flash green banner for 3 seconds
          setState(() => _showReconnectedBanner = true);
          _reconnectedBannerTimer?.cancel();
          _reconnectedBannerTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _showReconnectedBanner = false);
            }
          });
          // Auto-refresh sessions on reconnect
          ref.read(sessionsProvider.notifier).refreshSessions();
          // Send immediate heartbeat
          ref.read(connectionProvider.notifier).sendImmediatePing();
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectedBannerTimer?.cancel();
    _reconnectionSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App returning from background — force reconnect if needed
      final relay = ref.read(relayServiceProvider);
      if (relay.state != RelayConnectionState.connected) {
        relay.reconnect();
      } else {
        // Already connected — send heartbeat to check daemon
        ref.read(connectionProvider.notifier).sendImmediatePing();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final connState = ref.watch(connectionProvider);
    final theme = Theme.of(context);

    // Haptic feedback when a session becomes ready
    ref.listen(sessionsProvider, (prev, next) {
      if (prev == null) return;
      final prevIds =
          prev.where((s) => s.status.name == 'ready').map((s) => s.id).toSet();
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
          // Reconnected banner (flashes green for 3s)
          if (_showReconnectedBanner)
            _ConnectionBanner(
              message: 'Connected',
              color: Colors.green.shade100,
              textColor: Colors.green.shade900,
              icon: Icons.cloud_done,
            ),

          // Connection status banners
          _buildConnectionBanners(connState, theme),

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
                          connState.canStartSession
                              ? 'Tap + to start a new Claude Code session'
                              : connState.disabledReason ??
                                  'Cannot start sessions',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      if (connState.relay !=
                          RelayConnectionState.connected) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Cannot refresh -- not connected'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        return;
                      }
                      ref.read(sessionsProvider.notifier).refreshSessions();
                      // Cap the spinner at 2 seconds
                      await Future.delayed(const Duration(seconds: 2));
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
        onPressed: connState.canStartSession
            ? () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pushNamed('/sessions/new');
              }
            : null,
        backgroundColor: connState.canStartSession
            ? null
            : theme.colorScheme.onSurface.withValues(alpha: 0.12),
        tooltip: connState.canStartSession
            ? 'New session'
            : connState.disabledReason ?? 'Cannot start sessions',
        child: Icon(
          Icons.add,
          color: connState.canStartSession
              ? null
              : theme.colorScheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
    );
  }

  Widget _buildConnectionBanners(
      AppConnectionState connState, ThemeData theme) {
    final banners = <Widget>[];
    final relay = ref.read(relayServiceProvider);

    // Relay state
    switch (connState.relay) {
      case RelayConnectionState.disconnected:
        final attempts = relay.reconnectAttempts;
        banners.add(_ConnectionBanner(
          message: attempts > 0
              ? 'Disconnected from relay. Reconnecting... (attempt $attempts)'
              : 'Disconnected from relay',
          color: theme.colorScheme.errorContainer,
          textColor: theme.colorScheme.onErrorContainer,
          icon: Icons.cloud_off,
          onRetry: () {
            relay.reconnect();
          },
        ));
      case RelayConnectionState.connecting:
        final attempts = relay.reconnectAttempts;
        banners.add(_ConnectionBanner(
          message: attempts > 1
              ? 'Reconnecting to relay... (attempt $attempts)'
              : 'Connecting to relay...',
          color: theme.colorScheme.tertiaryContainer,
          textColor: theme.colorScheme.onTertiaryContainer,
          icon: Icons.cloud_sync,
        ));
      case RelayConnectionState.connected:
        break;
    }

    // Encryption state (only show non-established)
    switch (connState.encryption) {
      case EncryptionState.failed:
        banners.add(_ConnectionBanner(
          message: 'E2E encryption failed',
          color: theme.colorScheme.errorContainer,
          textColor: theme.colorScheme.onErrorContainer,
          icon: Icons.lock_open,
        ));
      case EncryptionState.establishing:
        banners.add(_ConnectionBanner(
          message: 'Establishing encryption...',
          color: theme.colorScheme.tertiaryContainer,
          textColor: theme.colorScheme.onTertiaryContainer,
          icon: Icons.lock_clock,
        ));
      case EncryptionState.notEstablished:
        if (connState.relay == RelayConnectionState.connected) {
          banners.add(_ConnectionBanner(
            message: 'Encryption not established',
            color: theme.colorScheme.errorContainer,
            textColor: theme.colorScheme.onErrorContainer,
            icon: Icons.no_encryption,
          ));
        }
      case EncryptionState.established:
        break;
    }

    // Daemon state (only show when relay is connected and encrypted)
    if (connState.relay == RelayConnectionState.connected &&
        connState.encryption == EncryptionState.established) {
      if (connState.daemon == DaemonState.offline) {
        banners.add(_ConnectionBanner(
          message: 'Daemon appears offline. Sessions may be stale.',
          color: theme.colorScheme.errorContainer,
          textColor: theme.colorScheme.onErrorContainer,
          icon: Icons.computer,
        ));
      }
    }

    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(children: banners);
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
