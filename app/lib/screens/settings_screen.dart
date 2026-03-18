import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/relay_provider.dart';
import '../services/relay_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relayState = ref.watch(relayStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Connection status
          ListTile(
            leading: Icon(
              Icons.cloud,
              color: relayState.when(
                data: (s) => switch (s) {
                  RelayConnectionState.connected => Colors.green,
                  RelayConnectionState.connecting => Colors.amber,
                  RelayConnectionState.disconnected => Colors.red,
                },
                loading: () => Colors.grey,
                error: (_, _) => Colors.red,
              ),
            ),
            title: const Text('Relay Connection'),
            subtitle: Text(relayState.when(
              data: (s) => switch (s) {
                RelayConnectionState.connected => 'Connected',
                RelayConnectionState.connecting => 'Connecting...',
                RelayConnectionState.disconnected => 'Disconnected',
              },
              loading: () => 'Unknown',
              error: (_, _) => 'Error',
            )),
          ),

          // Relay URL
          FutureBuilder<String?>(
            future: StorageService.getRelayUrl(),
            builder: (context, snapshot) {
              return ListTile(
                leading: const Icon(Icons.dns),
                title: const Text('Relay URL'),
                subtitle: Text(snapshot.data ?? 'Not configured'),
              );
            },
          ),

          const Divider(),

          // Re-pair
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Re-pair'),
            subtitle: const Text('Scan a new QR code from your daemon'),
            onTap: () async {
              await ref.read(authProvider.notifier).unpair();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/pairing',
                  (route) => false,
                );
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
