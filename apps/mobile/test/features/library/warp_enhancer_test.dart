import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/warp_enhancer.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Synthesize a solid-colour JPEG the fused pass can decode.
Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(180, 100, 60));
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// A runner that never resolves — stands in for a wedged isolate so the
/// timeout branch of [warpAndEnhance] can be exercised deterministically.
Future<Uint8List?> _neverCompletes() => Completer<Uint8List?>().future;

/// Quad taking 80% of the display frame: [0.1,0.9]×[0.1,0.9].
/// On a 200×100 source: TL(20,10) TR(180,10) BR(180,90) BL(20,90),
/// so top=bottom=160 → outW=160 and left=right=80 → outH=80.
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

  // fullFrame short-circuits to null with no isolate spawned.
  test('fullFrame → null', () async {
    expect(
      await warpAndEnhance(_jpeg(100, 80), CropCorners.fullFrame,
          EnhancerMode.none),
      isNull,
    );
  });

  // NORMAL parity: a real cropped pass returns non-null bytes decoding to the
  // edge-length dimensions — proves the success path is unchanged.
  test('valid quad → JPEG with edge-length dimensions (success unchanged)',
      () async {
    final result =
        await warpAndEnhance(_jpeg(200, 100), _kRect, EnhancerMode.none);
    expect(result, isNotNull);
    final out = img.decodeImage(result!)!;
    expect(out.width, 160);
    expect(out.height, 80);
  });

  // TIMEOUT: an injected never-completing runner + a tiny timeout → null,
  // within the bound. Mirrors the fallback contract on any failure.
  test('never-completing runner + tiny timeout → null within bound', () async {
    final sw = Stopwatch()..start();
    final result = await warpAndEnhance(
      _jpeg(200, 100),
      _kRect,
      EnhancerMode.none,
      timeout: const Duration(milliseconds: 50),
      runner: _neverCompletes,
    );
    sw.stop();
    expect(result, isNull);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
