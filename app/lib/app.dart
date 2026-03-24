import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/new_session_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/session_detail_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';

class FerlayApp extends ConsumerWidget {
  const FerlayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final initialRoute = switch (authState) {
      PairingState.paired => '/sessions',
      PairingState.unknown => '/sessions', // will redirect if needed
      _ => '/onboarding',
    };

    return MaterialApp(
      title: 'Ferlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
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
