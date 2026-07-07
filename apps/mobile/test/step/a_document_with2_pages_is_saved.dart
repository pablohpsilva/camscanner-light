import 'package:flutter_test/flutter_test.dart';

import 'the_app_is_launched_with_a_fake_scanner_returning2_pages.dart';

/// Usage: a document with 2 pages is saved
///
/// Asserts that the shared [scanPlatformRepo] recorded exactly one createFromCapture
/// call (first page) and one addPageToDocument call (second page).
Future<void> aDocumentWith2PagesIsSaved(WidgetTester tester) async {
  expect(scanPlatformRepo.createCalls, 1);
  expect(scanPlatformRepo.addPageCalls, 1);
}
