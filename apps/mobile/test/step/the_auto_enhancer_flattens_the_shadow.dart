import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer flattens the shadow
///
/// Verifies the enhancer the UI selected (recorded in [g1Repo.lastSavedEnhancer]
/// when Accept was tapped) actually removes a shadow gradient: a synthetic page
/// with a dark-left / lit-right illumination gradient must come out with a
/// uniform near-white background.
Future<void> theAutoEnhancerFlattensTheShadow(WidgetTester tester) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(enhancer, isA<AutoEnhancer>(),
      reason: 'UI must have selected AutoEnhancer');

  const w = 120, h = 40;
  final src = img.Image(width: w, height: h);
  int bgVal(int x) => 120 + (x * 120 ~/ (w - 1)); // 120 (shadow) .. 240 (lit)
  for (final px in src) {
    final v = bgVal(px.x);
    px..r = v..g = v..b = v;
  }
  final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

  final output = await enhancer!.enhance(input);
  final out = img.decodeImage(output)!;

  final left = out.getPixel(2, 20).luminance.toDouble();
  final right = out.getPixel(117, 20).luminance.toDouble();
  expect(left, greaterThan(220),
      reason: 'shadowed-left background must be flattened to near-white');
  expect(right, greaterThan(220),
      reason: 'lit-right background stays near-white');
  expect((left - right).abs(), lessThan(20),
      reason: 'shadow gradient removed → left and right are equally bright');
}
