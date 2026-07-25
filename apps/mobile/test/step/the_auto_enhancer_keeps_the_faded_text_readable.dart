import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import '../features/library/local_contrast_fixture.dart';
import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer keeps the faded text readable
///
/// Verifies the enhancer the UI selected (recorded in [g1Repo.lastSavedEnhancer]
/// when Accept was tapped) applies the color-preserving LOCAL contrast stretch:
/// a synthetic bright-background page with faded gray text must come out with
/// the ink darkened well below the surrounding paper, so faded print stays
/// readable instead of washing out under a global stretch.
Future<void> theAutoEnhancerKeepsTheFadedTextReadable(
  WidgetTester tester,
) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(
    enhancer,
    isA<AutoEnhancer>(),
    reason: 'UI must have selected AutoEnhancer',
  );

  const w = 240, h = 160;
  final input = brightBgFadedTextJpg(w: w, h: h);
  final (l, t, _, b) = fadedTextRect(w, h);
  final y = (t + b) ~/ 2;
  final inkX = l + 4; // l is a multiple of 4 by construction -> ink column
  final paperX = l + 5; // adjacent non-ink (paper) column

  final output = await enhancer!.enhance(input);
  final out = img.decodeImage(output)!;

  final inkLuma = out.getPixel(inkX, y).luminance.toDouble();
  final paperLuma = out.getPixel(paperX, y).luminance.toDouble();

  expect(
    inkLuma,
    lessThan(paperLuma - 40),
    reason:
        'faded text must darken well below the surrounding paper to stay readable',
  );
  expect(
    paperLuma,
    greaterThan(220),
    reason: 'surrounding paper stays near-white',
  );
}
