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

  // --- Pairing logic (identical to PairingScreen) ---

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

    await _doPairing(relay, code);
  }

  Future<void> _doPairing(String relayUrl, String code,
      {String? daemonPublicKey}) async {
    setState(() => _processingMessage = 'Connecting to relay...');

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
      await StorageService.setOnboardingComplete(true);
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

  // --- Page builders ---

  Widget _buildWelcomePage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          Image.asset(
            'assets/images/ferlay_logo.png',
            height: 96,
          ),
          const SizedBox(height: 24),
          Text(
            'Ferlay',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: const Color(0xFFE6E1E5),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your AI agent, always within reach.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFCAC4D0),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'Control Claude Code sessions from your phone — anywhere, anytime.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFCAC4D0),
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _goToPage(1),
              child: const Text('Get Started'),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildHowItWorksPage(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          Text(
            'How It Works',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: const Color(0xFFE6E1E5),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFlowIcon(Icons.phone_android_rounded, 'Phone', theme),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.sync_alt_rounded,
                  color: const Color(0xFF7C4DFF),
                  size: 28,
                ),
              ),
              _buildFlowIcon(Icons.cloud_rounded, 'Relay', theme),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.sync_alt_rounded,
                  color: const Color(0xFF7C4DFF),
                  size: 28,
                ),
              ),
              _buildFlowIcon(Icons.terminal_rounded, 'Terminal', theme),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Ferlay connects securely to your dev machine through an encrypted relay. Pair once, then start and manage sessions remotely.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFFCAC4D0),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildFeatureRow(
            Icons.lock_rounded,
            'End-to-end encrypted',
            theme,
          ),
          const SizedBox(height: 12),
          _buildFeatureRow(
            Icons.shield_rounded,
            'Zero-trust architecture',
            theme,
          ),
          const SizedBox(height: 12),
          _buildFeatureRow(
            Icons.wifi_rounded,
            'Session control from anywhere',
            theme,
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _goToPage(2),
              child: const Text('Next'),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildFlowIcon(IconData icon, String label, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 36,
          color: const Color(0xFFE6E1E5),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: const Color(0xFFCAC4D0),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(IconData icon, String text, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF7C4DFF)),
        const SizedBox(width: 12),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFE6E1E5),
          ),
        ),
      ],
    );
  }

  Widget _buildPairingPage(ThemeData theme) {
    return _showManualInput
        ? _buildManualInput(theme)
        : _buildScanner(theme);
  }

  Widget _buildScanner(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Text(
          'Pair Your Device',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFFE6E1E5),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Run `ferlay pair` on your computer, then scan the QR code.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFCAC4D0),
            ),
            textAlign: TextAlign.center,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MobileScanner(
                      onDetect: (BarcodeCapture capture) {
                        final value =
                            capture.barcodes.firstOrNull?.rawValue;
                        if (value != null) {
                          _handleQrData(value);
                        }
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
          padding: const EdgeInsets.all(16),
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
            Text(
              'Pair Your Device',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFFE6E1E5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Run `ferlay pair` on your computer and enter the details below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFCAC4D0),
              ),
            ),
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

  Widget _buildDotIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isActive = index == _currentPage;
        return Container(
          width: isActive ? 10 : 8,
          height: isActive ? 10 : 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? const Color(0xFF7C4DFF)
                : const Color(0xFFCAC4D0).withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1C1B1F),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                children: [
                  _buildWelcomePage(theme),
                  _buildHowItWorksPage(theme),
                  _buildPairingPage(theme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildDotIndicator(),
            ),
          ],
        ),
      ),
    );
  }
}
