// This is a basic Flutter widget test for DrawnOut.

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_demo/main.dart';

void main() {
  testWidgets('App smoke test - shows login page', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DrawnOutApp());

    // Verify that the login page shows
    expect(find.text('Welcome to Drawn Out!'), findsOneWidget);
  });
}
