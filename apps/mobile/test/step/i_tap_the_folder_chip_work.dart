import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the folder chip "Work"
///
/// The chip label includes a document count (e.g. "Work (1)"), so match by
/// substring rather than exact text.
Future<void> iTapTheFolderChipWork(WidgetTester tester) async {
  await tester.tap(find.textContaining('Work'));
  await tester.pumpAndSettle();
}
