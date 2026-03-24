import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/auth_provider.dart';
import '../services/storage_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Pairing state (page 3)
  final _manualFormKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _relayController = TextEditingController();
  bool _showManualInput = false;
  bool _processing = false;
  String? _error;
  String _processingMessage = 'Pairing...';

  @override
  void dispose() {
    _pageController.dispose();
    _codeController.dispose();
    _relayController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Pairing logic (same as PairingScreen) ──

  Future<void> _handleQrData(String data) async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });

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
    if (value == null || value.trim().isEmpty) return 'Relay URL is required';
    final trimmed = value.trim();
    if (!trimmed.startsWith('ws://') && !trimmed.startsWith('wss://')) {
      return 'URL must start with ws:// or wss://';
    }
    return null;
  }

  String? _validatePairingCode(String? value) {
    if (value == null || value.trim().isEmpty) return 'Pairing code is required';
    if (value.trim().length != 6) return 'Code must be 6 characters';
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

    await _doPairing(relay, code);
  }

  Future<void> _doPairing(String relayUrl, String code,
      {String? daemonPublicKey}) async {
    setState(() => _processingMessage = 'Connecting to relay...');

    Timer(const Duration(seconds: 3), () {
      if (mounted && _processing) {
        setState(() => _processingMessage = 'Waiting for daemon response...');
      }
    });
    Timer(const Duration(seconds: 8), () {
      if (mounted && _processing) {
        setState(() => _processingMessage = 'Establishing encryption...');
      }
    });

    await ref
        .read(authProvider.notifier)
        .startPairing(relayUrl, code, daemonPublicKeyB64: daemonPublicKey);

    if (!mounted) return;

    final state = ref.read(authProvider);
    if (state == PairingState.paired) {
      HapticFeedback.heavyImpact();
      await StorageService.setOnboardingComplete(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paired successfully!')),
        );
        Navigator.of(context).pushReplacementNamed('/sessions');
      }
    } else {
      setState(() {
        _error =
            'Pairing timed out. Make sure the daemon is running and showing the QR code.';
        _processing = false;
      });
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                physics: _currentPage < 2
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomePage(theme),
                  _buildHowItWorksPage(theme),
                  _buildPairingPage(theme),
                ],
              ),
            ),
            if (_currentPage < 2) ...[
              _buildDotIndicator(theme),
              _buildBottomButton(theme),
            ] else ...[
              _buildDotIndicator(theme),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDotIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          final isActive = index == _currentPage;
          return Container(
            width: isActive ? 24 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBottomButton(ThemeData theme) {
    final label = _currentPage == 0 ? 'Get Started' : 'Next';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => _goToPage(_currentPage + 1),
          child: Text(label),
        ),
      ),
    );
  }

  // ── Page 1: Welcome ──

  Widget _buildWelcomePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 96,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Ferlay',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your AI agent, always within reach.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Control Claude Code sessions from your phone\u2009—\u2009anywhere, anytime.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Page 2: How It Works ──

  Widget _buildHowItWorksPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Connection flow diagram
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFlowIcon(theme, Icons.phone_android_rounded, 'Phone'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.sync_alt_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              _buildFlowIcon(theme, Icons.cloud_rounded, 'Relay'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.sync_alt_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              _buildFlowIcon(theme, Icons.terminal_rounded, 'Terminal'),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Ferlay connects securely to your dev machine through an encrypted relay. Pair once, then start and manage sessions remotely.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildFeatureRow(
              theme, Icons.lock_rounded, 'End-to-end encrypted'),
          const SizedBox(height: 16),
          _buildFeatureRow(
              theme, Icons.shield_rounded, 'Zero-trust architecture'),
          const SizedBox(height: 16),
          _buildFeatureRow(
              theme, Icons.wifi_rounded, 'Session control from anywhere'),
        ],
      ),
    );
  }

  Widget _buildFlowIcon(ThemeData theme, IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 12),
        Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ── Page 3: Pair Your Device ──

  Widget _buildPairingPage(ThemeData theme) {
    if (_showManualInput) return _buildManualInput(theme);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            children: [
              Text(
                'Pair Your Device',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Run  ferlay pair  on your computer, then scan the QR code.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: MobileScanner(
                      onDetect: (BarcodeCapture capture) {
                        final value = capture.barcodes.firstOrNull?.rawValue;
                        if (value != null) _handleQrData(value);
                      },
                    ),
                  ),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextButton(
            onPressed: () => setState(() => _showManualInput = true),
            child: const Text('Enter code manually'),
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
            Text('Pair Your Device', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Enter the relay URL and pairing code from your terminal.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _relayController,
              validator: _validateRelayUrl,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: const InputDecoration(
                labelText: 'Relay URL',
                hintText: 'wss://relay.ferlay.dev/ws',
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
