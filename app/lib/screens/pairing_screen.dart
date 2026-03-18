import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/auth_provider.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();
  final _relayController = TextEditingController();
  bool _showManualInput = false;
  bool _processing = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _relayController.dispose();
    super.dispose();
  }

  Future<void> _handleQrData(String data) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final relay = json['relay'] as String?;
      final code = json['code'] as String?;

      if (relay == null || code == null) {
        setState(() {
          _error = 'Invalid QR code format';
          _processing = false;
        });
        return;
      }

      await _doPairing(relay, code);
    } catch (e) {
      setState(() {
        _error = 'Invalid QR code: $e';
        _processing = false;
      });
    }
  }

  Future<void> _handleManualPairing() async {
    final relay = _relayController.text.trim();
    final code = _codeController.text.trim();

    if (relay.isEmpty || code.isEmpty) {
      setState(() => _error = 'Both fields are required');
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    await _doPairing(relay, code);
  }

  Future<void> _doPairing(String relayUrl, String code) async {
    await ref.read(authProvider.notifier).startPairing(relayUrl, code);

    if (!mounted) return;

    final state = ref.read(authProvider);
    if (state == PairingState.paired) {
      Navigator.of(context).pushReplacementNamed('/sessions');
    } else {
      setState(() {
        _error = 'Pairing failed. Check the code and try again.';
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pair with Daemon')),
      body: _showManualInput ? _buildManualInput(theme) : _buildScanner(theme),
    );
  }

  Widget _buildScanner(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: _processing
              ? const Center(child: CircularProgressIndicator())
              : MobileScanner(
                  onDetect: (BarcodeCapture capture) {
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (value != null) {
                      _handleQrData(value);
                    }
                  },
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Scan the QR code from "ferlay pair"',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showManualInput = true),
                child: const Text('Enter code manually'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualInput(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Manual Pairing', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          TextField(
            controller: _relayController,
            decoration: const InputDecoration(
              labelText: 'Relay URL',
              hintText: 'wss://relay.ferlay.dev/ws',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Pairing Code',
              hintText: 'ABC123',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _processing ? null : _handleManualPairing,
            child: _processing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pair'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _showManualInput = false),
            child: const Text('Scan QR code instead'),
          ),
        ],
      ),
    );
  }
}
