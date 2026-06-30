import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/color_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with color enhancement
Future<void> theDocumentIsSavedWithColorEnhancement(WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<ColorEnhancer>(),
      reason: 'expected ColorEnhancer to have been passed to onAccept');
}
