import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_state.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/relay_provider.dart';
import '../services/relay_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Connection Status section
          _SectionHeader(title: 'Connection Status', theme: theme),

          // Relay status
          ListTile(
            leading: _StatusDot(color: switch (connState.relay) {
              RelayConnectionState.connected => Colors.green,
              RelayConnectionState.connecting => Colors.amber,
              RelayConnectionState.disconnected => Colors.red,
            }),
            title: const Text('Relay'),
            subtitle: FutureBuilder<String?>(
              future: StorageService.getRelayUrl(),
              builder: (context, snapshot) {
                final status = switch (connState.relay) {
                  RelayConnectionState.connected => 'Connected',
                  RelayConnectionState.connecting => 'Reconnecting...',
                  RelayConnectionState.disconnected => 'Disconnected',
                };
                final url = snapshot.data;
                return Text(url != null ? '$status  \u2022  $url' : status);
              },
            ),
          ),

          // Daemon status
          ListTile(
            leading: _StatusDot(color: switch (connState.daemon) {
              DaemonState.online => Colors.green,
              DaemonState.offline => Colors.red,
              DaemonState.unknown => Colors.grey,
            }),
            title: const Text('Daemon'),
            subtitle: Builder(builder: (context) {
              final status = switch (connState.daemon) {
                DaemonState.online => 'Online',
                DaemonState.offline => 'Offline',
                DaemonState.unknown => 'Unknown',
              };
              final lastPong =
                  ref.read(connectionProvider.notifier).lastPongTime;
              if (lastPong != null && connState.daemon == DaemonState.online) {
                final ago = DateTime.now().difference(lastPong);
                final agoStr = ago.inSeconds < 60
                    ? '${ago.inSeconds}s ago'
                    : '${ago.inMinutes}m ago';
                return Text('$status  \u2022  last seen $agoStr');
              }
              return Text(status);
            }),
          ),

          // Encryption status
          ListTile(
            leading: _StatusDot(color: switch (connState.encryption) {
              EncryptionState.established => Colors.green,
              EncryptionState.establishing => Colors.amber,
              EncryptionState.notEstablished => Colors.grey,
              EncryptionState.failed => Colors.red,
            }),
            title: const Text('Encryption'),
            subtitle: Text(switch (connState.encryption) {
              EncryptionState.established => 'End-to-end encrypted',
              EncryptionState.establishing => 'Key exchange in progress...',
              EncryptionState.notEstablished => 'Not established',
              EncryptionState.failed => 'Failed',
            }),
          ),

          const Divider(indent: 16, endIndent: 16),

          // Actions section
          _SectionHeader(title: 'Actions', theme: theme),

          // Reconnect button
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reconnect'),
            subtitle: const Text('Force-reconnect to relay server'),
            onTap: () {
              final relay = ref.read(relayServiceProvider);
              relay.reconnect();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reconnecting...')),
              );
            },
          ),

          // Re-pair
          ListTile(
            leading: Icon(Icons.link_off, color: theme.colorScheme.error),
            title: Text('Unpair Device',
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle:
                const Text('Clear keys and pair with a new daemon'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Unpair Device?'),
                  content: const Text(
                      'This will clear your encryption keys and disconnect. You will need to scan a new QR code from the daemon.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Unpair'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(authProvider.notifier).unpair();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/pairing',
                    (route) => false,
                  );
                }
              }
            },
          ),

          const Divider(indent: 16, endIndent: 16),

          // About section
          _SectionHeader(title: 'About', theme: theme),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Ferlay'),
            subtitle: const Text('Version 0.1.0'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Remote session manager for Claude Code'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
