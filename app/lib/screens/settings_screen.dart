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
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Connection Status',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          // Relay status
          ListTile(
            leading: Icon(
              Icons.cloud,
              color: switch (connState.relay) {
                RelayConnectionState.connected => Colors.green,
                RelayConnectionState.connecting => Colors.amber,
                RelayConnectionState.disconnected => Colors.red,
              },
            ),
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
                return Text(url != null ? '$status ($url)' : status);
              },
            ),
          ),

          // Daemon status
          ListTile(
            leading: Icon(
              Icons.computer,
              color: switch (connState.daemon) {
                DaemonState.online => Colors.green,
                DaemonState.offline => Colors.red,
                DaemonState.unknown => Colors.grey,
              },
            ),
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
                return Text('$status (last seen $agoStr)');
              }
              return Text(status);
            }),
          ),

          // Encryption status
          ListTile(
            leading: Icon(
              switch (connState.encryption) {
                EncryptionState.established => Icons.lock,
                EncryptionState.establishing => Icons.lock_clock,
                EncryptionState.notEstablished => Icons.no_encryption,
                EncryptionState.failed => Icons.lock_open,
              },
              color: switch (connState.encryption) {
                EncryptionState.established => Colors.green,
                EncryptionState.establishing => Colors.amber,
                EncryptionState.notEstablished => Colors.grey,
                EncryptionState.failed => Colors.red,
              },
            ),
            title: const Text('E2E Encryption'),
            subtitle: Text(switch (connState.encryption) {
              EncryptionState.established => 'Active',
              EncryptionState.establishing => 'Key exchange in progress...',
              EncryptionState.notEstablished => 'Not established',
              EncryptionState.failed => 'Failed',
            }),
          ),

          const Divider(),

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
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Re-pair'),
            subtitle:
                const Text('Clear keys and scan a new QR code'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Re-pair?'),
                  content: const Text(
                      'This will clear your encryption keys and disconnect. You will need to scan a new QR code from the daemon.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Re-pair'),
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

          const Divider(),

          // About
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Ferlay v0.1.0'),
          ),
        ],
      ),
    );
  }
}
