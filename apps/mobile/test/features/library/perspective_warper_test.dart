import 'dart:async';
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

/// A runner that never resolves — stands in for a wedged isolate so the
/// timeout branch of warp() can be exercised deterministically.
Future<Uint8List?> _neverCompletes(Uint8List bytes, CropCorners corners) =>
    Completer<Uint8List?>().future;

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

  // 6. Timeout path: an injected runner whose Future never completes must
  //    resolve to null (never-throws contract) within the configured bound.
  test('never-completing runner + tiny timeout → null (no hang)', () async {
    const warperTimeout = PerspectiveWarper(
      timeout: Duration(milliseconds: 50),
      runnerOverride: _neverCompletes,
    );
    final result = await warperTimeout
        .warp(_jpeg(100, 80), _kRect)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('warp() did not honor its timeout'),
        );
    expect(result, isNull);
  });

  // P01 T4: NORMAL source (≤ 2×cap) — output bytes/dimensions are byte-for-byte
  //   UNCHANGED vs the pre-bound implementation. computeWorkResolution returns
  //   scale==1.0 so no source resize happens and normal inputs are untouched.
  test('P01 T4: small source (≤ 2×cap) → output unchanged (scale==1.0)', () async {
    // 200×100 long side 200 ≪ 2×3500 → no resize path.
    final expected = await warper.warp(_jpeg(200, 100), _kRect);
    expect(expected, isNotNull);
    final out = img.decodeImage(expected!)!;
    // Same edge-length dims as test #2 — proves geometry is preserved.
    expect(out.width, 160);
    expect(out.height, 80);
  });

  // P01 T4: LARGE source (long side > 2×cap) — the warp still succeeds and
  //   produces the same-capped output dims; the SOURCE buffer is now bounded so
  //   it must not throw and the output long side stays ≤ kDefaultFlatMaxDimension.
  test('P01 T4: large source (> 2×cap) → bounded, output long side ≤ cap', () async {
    // Long side 8000 > 2×3500=7000 → source-bound path engages.
    const cap = kDefaultFlatMaxDimension;
    final bytes = _jpeg(8000, 6000);
    final result = await warper.warp(bytes, _kRect);
    expect(result, isNotNull);
    final out = img.decodeImage(result!)!;
    final longest = out.width > out.height ? out.width : out.height;
    expect(longest, lessThanOrEqualTo(cap));
    // Geometry: _kRect quad is 0.8×8000=6400 wide, 0.8×6000=4800 tall → capped
    // to 3500 long side keeps the 4:3 aspect (3500×2625).
    expect(out.width, 3500);
    expect(out.height, 2625);
  });

  // P01 T4 (direct): the sampling loop reads a SOURCE buffer bounded to
  //   2×maxDim. Calling warpPerspectiveToImage on an oversized img.Image must
  //   downscale the source it samples (super-sampling headroom = 2×cap).
  test('P01 T4: source long side bounded to 2×maxDim in sampling loop', () {
    final big = img.Image(width: 8000, height: 6000, numChannels: 3);
    img.fill(big, color: img.ColorRgb8(180, 100, 60));
    lastSampledSourceSize = null;
    warpPerspectiveToImage(big, _kRect, kDefaultFlatMaxDimension);
    expect(lastSampledSourceSize, isNotNull);
    // 8000 > 2×3500=7000 → bounded to 7000×5250.
    expect(lastSampledSourceSize!.$1, 7000);
    expect(lastSampledSourceSize!.$2, 5250);
  });

  // P01 T4 (direct): a source already ≤ 2×maxDim is NOT resized — the sampling
  //   loop reads the original buffer, so normal inputs are byte-identical.
  test('P01 T4: source ≤ 2×maxDim is not resized', () {
    final small = img.Image(width: 200, height: 100, numChannels: 3);
    img.fill(small, color: img.ColorRgb8(180, 100, 60));
    lastSampledSourceSize = null;
    warpPerspectiveToImage(small, _kRect, kDefaultFlatMaxDimension);
    expect(lastSampledSourceSize, (200, 100));
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
