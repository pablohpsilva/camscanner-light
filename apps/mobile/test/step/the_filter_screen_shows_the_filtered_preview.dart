import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the filter screen shows the filtered preview
///
/// B3: after a filter is selected on the edit-filter screen, the base image
/// swaps from the raw `Image.file` to an enhanced `Image.memory` preview. As in
/// B2, the debounce + enhance `compute()` must finish before the spinner clears,
/// so advance the clock in fixed increments (pumpAndSettle would hang on the
/// animating spinner).
Future<void> theFilterScreenShowsTheFilteredPreview(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  final image = tester.widget<Image>(
    find.byKey(const Key('edit-filter-image')),
  );
  expect(
    image.image,
    isA<MemoryImage>(),
    reason: 'the edit-filter base image must show the enhanced live preview',
  );
}
