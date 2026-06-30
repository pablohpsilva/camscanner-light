import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with grayscale enhancement
Future<void> theDocumentIsSavedWithGrayscaleEnhancement(
    WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<GrayscaleEnhancer>(),
      reason: 'expected GrayscaleEnhancer to have been passed to onAccept');
}
