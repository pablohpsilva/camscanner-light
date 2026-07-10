import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_warper.dart';
import 'package:mobile/features/library/perspective_warper.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Synthesize a solid-colour JPEG. If [orientation] != 1, embeds that EXIF
/// Orientation tag so bakeOrientation rotates the pixel data.
Uint8List _jpeg(int w, int h, {int orientation = 1}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(180, 100, 60));
  if (orientation != 1) {
    image.exif.imageIfd.orientation = orientation;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Quad that takes 80 % of a display-frame image: [0.1,0.9]×[0.1,0.9].
const _kRect = CropCorners(
  topLeft: Offset(0.1, 0.1),
  topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9),
  bottomLeft: Offset(0.1, 0.9),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warper = const PerspectiveWarper();

  // 1. Full-frame → null (no-op, no isolate spawned).
  test('fullFrame → null', () async {
    expect(await warper.warp(_jpeg(100, 80), CropCorners.fullFrame), isNull);
  });

  // 2. Valid rectangular quad → JPEG with correct edge-length dimensions.
  //    Source: 200×100.  Quad pixel coords: TL(20,10) TR(180,10) BR(180,90) BL(20,90).
  //    top=bottom=160 → outW=160; left=right=80 → outH=80.
  test('valid quad → JPEG dimensions match edge-length formula', () async {
    final result = await warper.warp(_jpeg(200, 100), _kRect);
    expect(result, isNotNull);
    final out = img.decodeImage(result!)!;
    expect(out.width, 160);
    expect(out.height, 80);
  });

  // 3. Self-crossing quad → WarpException.
  test('self-crossing quad → WarpException', () async {
    const crossed = CropCorners(
      topLeft: Offset(0.9, 0.1), // TL/TR swapped
      topRight: Offset(0.1, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    await expectLater(
      warper.warp(_jpeg(100, 80), crossed),
      throwsA(isA<WarpException>()),
    );
  });

  // 4. Degenerate quad (all corners coincide) → WarpException.
  test('degenerate quad (zero-area) → WarpException', () async {
    const degen = CropCorners(
      topLeft: Offset(0.5, 0.5),
      topRight: Offset(0.5, 0.5),
      bottomRight: Offset(0.5, 0.5),
      bottomLeft: Offset(0.5, 0.5),
    );
    await expectLater(
      warper.warp(_jpeg(100, 80), degen),
      throwsA(isA<WarpException>()),
    );
  });

  // 4b. Output long side capped by maxDimension.
  //     Source 400×300, _kRect → 320×240 quad; cap 50 → both ≤ 50.
  test('output long side is capped by maxDimension', () async {
    const warperSmall = PerspectiveWarper(maxDimension: 50);
    final result = await warperSmall.warp(_jpeg(400, 300), _kRect);
    expect(result, isNotNull);
    final out = img.decodeImage(result!)!;
    expect(out.width, lessThanOrEqualTo(50));
    expect(out.height, lessThanOrEqualTo(50));
    expect(out.width, greaterThan(2));
  });

  // 5. EXIF orientation alignment.
  //    Source: 40×80 sensor with Orientation=6 (90° CW) → display is 80×40.
  //    _kRect in display frame: TL(8,4) TR(72,4) BR(72,36) BL(8,36).
  //    top=bottom=64 → outW=64; left=right=32 → outH=32.
  //    WITHOUT bakeOrientation (raw 40×80): outW=32, outH=64 — flipped.
  test(
    'EXIF Orientation 6: bakeOrientation applied before denormalization',
    () async {
      final bytes = _jpeg(40, 80, orientation: 6);
      final result = await warper.warp(bytes, _kRect);
      expect(result, isNotNull);
      final out = img.decodeImage(result!)!;
      expect(
        out.width,
        64,
        reason:
            'display-frame top edge = 0.8×80 = 64; '
            'without bakeOrientation would be 32',
      );
      expect(
        out.height,
        32,
        reason:
            'display-frame left edge = 0.8×40 = 32; '
            'without bakeOrientation would be 64',
      );
    },
  );
}
