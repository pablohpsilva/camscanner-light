import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the save error
Future<void> iSeeTheSaveError(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text("Couldn't save document. Try again."), findsOneWidget);
}
