import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved without enhancement
Future<void> theDocumentIsSavedWithoutEnhancement(
    WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<NoneEnhancer>(),
      reason: 'expected NoneEnhancer to have been passed to onAccept');
}
