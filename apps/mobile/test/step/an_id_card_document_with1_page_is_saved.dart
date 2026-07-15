import 'package:flutter_test/flutter_test.dart';

import 'the_app_is_launched_with_a_fake_id_scanner_returning_a_front_and_a_back.dart';

/// Usage: an ID card document with 1 page is saved
///
/// After cancelling the back step, the already-captured front must be preserved
/// as a single-page document marked as an ID card (P04 T4, SF-4-IDSCAN): exactly
/// one createFromCapture, NO addPageToDocument, one markAsIdCard.
Future<void> anIdCardDocumentWith1PageIsSaved(WidgetTester tester) async {
  expect(idScanRepo.createCalls, 1);
  expect(idScanRepo.addPageCalls, 0);
  expect(idScanRepo.markIdCardCalls.length, 1);
}
