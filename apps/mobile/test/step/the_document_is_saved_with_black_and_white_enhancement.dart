import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/bw_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with black and white enhancement
Future<void> theDocumentIsSavedWithBlackAndWhiteEnhancement(
    WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<BwEnhancer>(),
      reason: 'expected BwEnhancer to have been passed to onAccept');
}
