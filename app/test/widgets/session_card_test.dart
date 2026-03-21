import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ferlay/models/session.dart';
import 'package:ferlay/widgets/session_card.dart';

void main() {
  Widget buildCard(Session session, {VoidCallback? onTap}) {
    return MaterialApp(
      home: Scaffold(
        body: SessionCard(
          session: session,
          onTap: onTap ?? () {},
        ),
      ),
    );
  }

  group('SessionCard', () {
    testWidgets('displays session name', (tester) async {
      await tester.pumpWidget(buildCard(const Session(
        id: '1',
        name: 'my-session',
        directory: '/tmp',
        status: SessionStatus.ready,
      )));

      expect(find.text('my-session'), findsOneWidget);
    });

    testWidgets('displays Unnamed for empty name', (tester) async {
      await tester.pumpWidget(buildCard(const Session(
        id: '1',
        name: '',
        directory: '/tmp',
        status: SessionStatus.starting,
      )));

      expect(find.text('Unnamed'), findsOneWidget);
    });

    testWidgets('displays directory', (tester) async {
      await tester.pumpWidget(buildCard(const Session(
        id: '1',
        name: 'test',
        directory: '~/Projects/ferlay',
        status: SessionStatus.ready,
      )));

      expect(find.text('~/Projects/ferlay'), findsOneWidget);
    });

    testWidgets('displays status badge', (tester) async {
      await tester.pumpWidget(buildCard(const Session(
        id: '1',
        name: 'test',
        directory: '/tmp',
        status: SessionStatus.crashed,
      )));

      expect(find.text('Crashed'), findsOneWidget);
    });

    testWidgets('displays error text when present', (tester) async {
      await tester.pumpWidget(buildCard(const Session(
        id: '1',
        name: 'test',
        directory: '/tmp',
        status: SessionStatus.crashed,
        error: 'spawn failed: not found',
      )));

      expect(find.text('spawn failed: not found'), findsOneWidget);
    });

    testWidgets('tapping invokes onTap callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(buildCard(
        const Session(
          id: '1',
          name: 'test',
          directory: '/tmp',
          status: SessionStatus.ready,
        ),
        onTap: () => tapped = true,
      ));

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('hides directory when empty', (tester) async {
      await tester.pumpWidget(buildCard(const Session(
        id: '1',
        name: 'test',
        directory: '',
        status: SessionStatus.starting,
      )));

      expect(find.byIcon(Icons.folder_outlined), findsNothing);
    });
  });
}
