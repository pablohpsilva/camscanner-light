import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with auto enhancement
Future<void> theDocumentIsSavedWithAutoEnhancement(WidgetTester tester) async {
  expect(
    g1Repo.lastSavedEnhancer,
    isA<AutoEnhancer>(),
    reason: 'expected AutoEnhancer to have been passed to onAccept',
  );
}
