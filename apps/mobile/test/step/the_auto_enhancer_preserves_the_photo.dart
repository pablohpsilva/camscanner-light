import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer preserves the photo
///
/// Verifies the UI-selected enhancer ([g1Repo.lastSavedEnhancer]) preserves a
/// colourful embedded photo region (not blown to white, colour kept) while the
/// surrounding paper stays bright.
Future<void> theAutoEnhancerPreservesThePhoto(WidgetTester tester) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(enhancer, isA<AutoEnhancer>(),
      reason: 'UI must have selected AutoEnhancer');

  const w = 240, h = 240;
  final src = img.Image(width: w, height: h);
  for (final px in src) { px..r = 235..g = 235..b = 235; } // paper
  for (var y = 60; y < 180; y++) {
    for (var x = 60; x < 180; x++) { src.getPixel(x, y)..r = 210..g = 60..b = 55; } // colourful photo
  }
  final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

  final out = img.decodeImage(await enhancer!.enhance(input))!;
  final p = out.getPixel(120, 120);

  expect(p.luminance, lessThan(215),
      reason: 'colourful photo must not be blown out to white');
  expect((p.r.toInt() - p.g.toInt()).abs(), greaterThan(40),
      reason: 'photo keeps its colour');
  expect(out.getPixel(10, 10).luminance, greaterThan(200),
      reason: 'paper around the photo must still be bright');
}
