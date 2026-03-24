import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/new_session_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_detail_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage_service.dart';

/// Tracks whether onboarding has been completed.
/// Loaded once at startup, then stays in memory.
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  return StorageService.isOnboardingComplete();
});

class FerlayApp extends ConsumerWidget {
  const FerlayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final onboardingAsync = ref.watch(onboardingCompleteProvider);

    final onboardingComplete =
        onboardingAsync.whenOrNull(data: (v) => v) ?? false;

    final Widget home;
    if (authState == PairingState.unknown) {
      home = const Scaffold(
        backgroundColor: Color(0xFF1C1B1F),
        body: Center(child: CircularProgressIndicator()),
      );
    } else if (authState == PairingState.paired) {
      home = const SessionsScreen();
    } else if (onboardingComplete) {
      home = const PairingScreen();
    } else {
      home = const OnboardingScreen();
    }

    return MaterialApp(
      title: 'Ferlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: home,
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/pairing': (context) => const PairingScreen(),
        '/sessions': (context) => const SessionsScreen(),
        '/sessions/new': (context) => const NewSessionScreen(),
        '/sessions/detail': (context) => const SessionDetailScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
