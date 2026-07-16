import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_size_resolver.dart';

/// P07 Task 6: the shared image-size resolver (one copy — was duplicated verbatim
/// in capture_review_screen + edit_crop_screen). Contract: a bad/undecodable path
/// completes with an ERROR rather than hanging, so screens fall back to an
/// overlay-free view instead of spinning forever.
void main() {
  testWidgets('an undecodable path completes with an error (does not hang)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        resolveImageSize('/nonexistent/definitely-not-an-image.jpg'),
        throwsA(anything),
      );
    });
  });
}
