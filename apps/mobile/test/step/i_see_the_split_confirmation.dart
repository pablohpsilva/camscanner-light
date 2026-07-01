import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the split confirmation
Future<void> iSeeTheSplitConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Split into a new document'), findsOneWidget);
}
