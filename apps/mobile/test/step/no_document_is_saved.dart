import 'package:flutter_test/flutter_test.dart';

import 'the_app_is_launched_with_a_fake_scanner_returning2_pages.dart';

/// Usage: no document is saved
///
/// Asserts that the shared [scanPlatformRepo] was never asked to create a document.
Future<void> noDocumentIsSaved(WidgetTester tester) async {
  expect(scanPlatformRepo.createCalls, 0);
}
