import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer preserves the photo
///
/// Verifies the enhancer the UI selected (recorded in [g1Repo.lastSavedEnhancer]
/// when Accept was tapped) does not blow out a large dark region: a synthetic
/// page with an 80x80 dark block must keep that block dark after enhancement,
/// while surrounding paper still brightens.
Future<void> theAutoEnhancerPreservesThePhoto(WidgetTester tester) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(enhancer, isA<AutoEnhancer>(),
      reason: 'UI must have selected AutoEnhancer');

  const w = 200, h = 200;
  final src = img.Image(width: w, height: h);
  for (final px in src) {
    px..r = 235..g = 235..b = 235; // bright paper
  }
  for (var y = 60; y < 140; y++) {
    for (var x = 60; x < 140; x++) {
      src.getPixel(x, y)..r = 40..g = 40..b = 40; // embedded photo
    }
  }
  final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

  final output = await enhancer!.enhance(input);
  final out = img.decodeImage(output)!;

  expect(out.getPixel(100, 100).luminance, lessThan(100),
      reason: 'embedded photo must be preserved, not blown out to white');
  expect(out.getPixel(10, 10).luminance, greaterThan(200),
      reason: 'paper around the photo must still be bright');
}
