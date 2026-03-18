import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ferlay/app.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FerlayApp()),
    );
    await tester.pump();

    // App should render without crashing
    expect(find.byType(FerlayApp), findsOneWidget);
  });
}
