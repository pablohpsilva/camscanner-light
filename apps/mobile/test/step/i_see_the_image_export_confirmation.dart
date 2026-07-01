import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the image export confirmation
Future<void> iSeeTheImageExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Page saved as image'), findsOneWidget);
}
