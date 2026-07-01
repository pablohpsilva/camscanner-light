import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the all images export confirmation
Future<void> iSeeTheAllImagesExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.textContaining('Exported'), findsOneWidget);
}
