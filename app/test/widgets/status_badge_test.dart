import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ferlay/models/session.dart';
import 'package:ferlay/widgets/status_badge.dart';

void main() {
  Widget buildBadge(SessionStatus status) {
    return MaterialApp(
      home: Scaffold(body: StatusBadge(status: status)),
    );
  }

  group('StatusBadge', () {
    testWidgets('shows correct label for each status', (tester) async {
      for (final status in SessionStatus.values) {
        await tester.pumpWidget(buildBadge(status));
        expect(find.text(status.label), findsOneWidget);
      }
    });

    testWidgets('displays icon for ready status', (tester) async {
      await tester.pumpWidget(buildBadge(SessionStatus.ready));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('displays icon for crashed status', (tester) async {
      await tester.pumpWidget(buildBadge(SessionStatus.crashed));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('displays icon for starting status', (tester) async {
      await tester.pumpWidget(buildBadge(SessionStatus.starting));
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    });
  });
}
