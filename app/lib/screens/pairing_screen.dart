import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/auth_provider.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _manualFormKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _relayController = TextEditingController();
  bool _showManualInput = false;
  bool _processing = false;
  String? _error;
  String _processingMessage = 'Pairing...';

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

    // Validate QR code with specific error messages
    Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      setState(() {
        _error = 'QR code is not a Ferlay pairing code';
        _processing = false;
      });
      return;
    }

    final relay = json['relay'] as String?;
    final code = json['code'] as String?;
    final pk = json['pk'] as String?;

    if (relay == null) {
      setState(() {
        _error = 'QR code missing relay URL';
        _processing = false;
      });
      return;
    }

    if (code == null) {
      setState(() {
        _error = 'QR code missing pairing code';
        _processing = false;
      });
      return;
    }

    if (pk == null) {
      setState(() {
        _error = 'QR code missing encryption key -- daemon may be outdated';
        _processing = false;
      });
      return;
    }

    await _doPairing(relay, code, daemonPublicKey: pk);
  }

  String? _validateRelayUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Relay URL is required';
    }
    final trimmed = value.trim();
    if (!trimmed.startsWith('ws://') && !trimmed.startsWith('wss://')) {
      return 'URL must start with ws:// or wss://';
    }
    return null;
  }

  String? _validatePairingCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Pairing code is required';
    }
    final trimmed = value.trim();
    if (trimmed.length != 6) {
      return 'Code must be 6 characters';
    }
    return null;
  }

  Future<void> _handleManualPairing() async {
    if (!_manualFormKey.currentState!.validate()) return;

    final relay = _relayController.text.trim();
    final code = _codeController.text.trim();

    setState(() {
      _processing = true;
      _error = null;
    });

    // Manual pairing doesn't include public key -- key exchange happens over relay
    await _doPairing(relay, code);
  }

  Future<void> _doPairing(String relayUrl, String code,
      {String? daemonPublicKey}) async {
    setState(() => _processingMessage = 'Connecting to relay...');

    // Show progress updates
    Timer(const Duration(seconds: 3), () {
      if (mounted && _processing) {
        setState(
            () => _processingMessage = 'Waiting for daemon response...');
      }
    });
    Timer(const Duration(seconds: 8), () {
      if (mounted && _processing) {
        setState(
            () => _processingMessage = 'Establishing encryption...');
      }
    });

    await ref
        .read(authProvider.notifier)
        .startPairing(relayUrl, code, daemonPublicKeyB64: daemonPublicKey);

    if (!mounted) return;

    final state = ref.read(authProvider);
    if (state == PairingState.paired) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paired successfully!')),
        );
      }
      Navigator.of(context).pushReplacementNamed('/sessions');
    } else {
      setState(() {
        _error =
            'Pairing timed out. Make sure the daemon is running and showing the QR code.';
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body:
          _showManualInput ? _buildManualInput(theme) : _buildScanner(theme),
    );
  }

  Widget _buildScanner(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Image.asset(
          'assets/images/ferlay_logo.png',
          height: 64,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _processing
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_processingMessage),
                    ],
                  ),
                )
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
            child: Column(
              children: [
                Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _processing = false;
                    });
                  },
                  child: const Text('Try Again'),
                ),
              ],
            ),
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
      child: Form(
        key: _manualFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset(
                'assets/images/ferlay_logo.png',
                height: 64,
              ),
            ),
            const SizedBox(height: 16),
            Text('Manual Pairing', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            TextFormField(
              controller: _relayController,
              validator: _validateRelayUrl,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Relay URL',
                hintText: 'wss://ferlay.dev/ws',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              validator: _validatePairingCode,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Pairing Code',
                hintText: 'ABC123',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
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
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _showManualInput = false),
              child: const Text('Scan QR code instead'),
            ),
          ],
        ),
      ),
    );
  }
}
