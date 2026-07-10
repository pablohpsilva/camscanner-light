import 'package:flutter_test/flutter_test.dart';

import 'the_app_is_launched_with_a_fake_id_camera_returning_a_front_and_a_back.dart';

/// Usage: an ID card document with 2 pages is saved
///
/// Asserts that the shared [idScanRepo] recorded exactly one createFromCapture
/// call (front), one addPageToDocument call (back), and one markAsIdCard call.
Future<void> anIdCardDocumentWith2PagesIsSaved(WidgetTester tester) async {
  expect(idScanRepo.createCalls, 1);
  expect(idScanRepo.addPageCalls, 1);
  expect(idScanRepo.markIdCardCalls.length, 1);
}
