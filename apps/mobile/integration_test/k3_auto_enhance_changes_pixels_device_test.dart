import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/dart_page_processor.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/fallback_page_processor.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/native_page_processor.dart';

/// Guards the second half of the report — "Automatic filter does not affect the
/// image at all". Runs the PRODUCTION processor (native OpenCV primary + Dart
/// fallback) with EnhancerMode.auto over a full frame on a synthetic image that
/// has real per-channel lighting variation, and asserts the enhanced pixels
/// actually differ from the input. Must run on device (native libs).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Production wiring, mirroring LibraryDependencies.
  const processor = FallbackPageProcessor(
    primary: NativePageProcessor(),
    fallback: DartPageProcessor(HybridWarper()),
  );

  // A gradient with an off-white cast + vignette — the kind of uneven lighting
  // the flat-field Auto is meant to correct (a flat solid image is a no-op).
  Uint8List gradientJpeg() {
    final image = img.Image(width: 300, height: 400);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final vignette = 1.0 - 0.35 * ((x - 150).abs() / 150);
        final r = (255 * vignette).clamp(0, 255).toInt();
        final g = (245 * vignette).clamp(0, 255).toInt();
        final b = (225 * vignette).clamp(0, 255).toInt();
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  testWidgets('Auto visibly changes the pixels through the real processor', (
    tester,
  ) async {
    final input = gradientJpeg();

    final out = await processor.process(
      input,
      CropCorners.fullFrame,
      EnhancerMode.auto,
    );

    expect(
      out,
      isNotNull,
      reason: 'Auto must not fall through to a null (unenhanced) result',
    );

    final before = img.decodeImage(input)!;
    final after = img.decodeImage(out!)!;
    expect(after.width, before.width);
    expect(after.height, before.height);

    // Count pixels whose luma moved by more than a JPEG-noise threshold.
    var changed = 0;
    var total = 0;
    for (var y = 0; y < before.height; y += 7) {
      for (var x = 0; x < before.width; x += 7) {
        final p = before.getPixel(x, y);
        final q = after.getPixel(x, y);
        final dl = (p.luminance - q.luminance).abs();
        if (dl > 12) changed++;
        total++;
      }
    }
    // Flat-field lifts the vignette/cast broadly — expect a large fraction moved.
    expect(
      changed / total,
      greaterThan(0.25),
      reason:
          'Auto should alter a substantial fraction of pixels ('
          '$changed/$total moved) — it currently does nothing to the image',
    );
  });
}
