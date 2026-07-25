import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the big image shows the filtered preview
///
/// B2: after a filter is selected, the large review image swaps from the raw
/// `Image.file` to an enhanced `Image.memory` preview. The debounce (~250ms)
/// must fire and the enhance `compute()` finish before the spinner clears;
/// `pumpAndSettle` can't be used while that spinner animates, so advance the
/// clock in fixed increments instead.
Future<void> theBigImageShowsTheFilteredPreview(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  final image = tester.widget<Image>(find.byKey(const Key('review-image')));
  expect(
    image.image,
    isA<MemoryImage>(),
    reason: 'the big review image must show the enhanced live preview',
  );
}
