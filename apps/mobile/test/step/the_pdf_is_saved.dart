import 'package:flutter_test/flutter_test.dart';

/// Usage: the PDF is saved
///
/// The success SnackBar only shows if repository.exportPdf completed — i.e. the
/// PDF was actually built from the real page image and written to device storage.
Future<void> thePdfIsSaved(WidgetTester tester) async {
  expect(find.text('PDF saved'), findsOneWidget);
}
