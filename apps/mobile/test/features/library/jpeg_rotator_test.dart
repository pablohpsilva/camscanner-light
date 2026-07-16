import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/jpeg_rotator.dart';

/// Unit tests for the injectable rotate seam (P05 TEST-01). The seam contract:
/// decode+bake+rotate+re-encode, returning null on an undecodable input. A fake
/// implementing [JpegRotator] lets the derivative pipeline be host-tested
/// without a real `compute()` isolate; here we prove the real one honors the
/// contract on both a valid and a garbage input.
void main() {
  Uint8List jpeg(int w, int h) =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

  group('rotateAndBakeJpeg (isolate entrypoint)', () {
    test('re-encodes a valid JPEG and swaps dimensions on a quarter-turn', () {
      final out = rotateAndBakeJpeg(RotateJpegArgs(jpeg(4, 8), 1));
      expect(out, isNotNull);
      // JPEG SOI marker — real re-encoded pixels.
      expect(out!.sublist(0, 2), [0xFF, 0xD8]);
      final decoded = img.decodeImage(out)!;
      // 90° rotation swaps width/height.
      expect(decoded.width, 8);
      expect(decoded.height, 4);
    });

    test('quarterTurns 0 keeps dimensions (bake-only, no rotation)', () {
      final out = rotateAndBakeJpeg(RotateJpegArgs(jpeg(4, 8), 0))!;
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 4);
      expect(decoded.height, 8);
    });

    test('returns null for undecodable bytes', () {
      expect(
        rotateAndBakeJpeg(RotateJpegArgs(Uint8List.fromList([0, 1, 2]), 1)),
        isNull,
      );
    });
  });

  group('ComputeJpegRotator', () {
    test(
      'rotate() delegates to the isolate and returns rotated bytes',
      () async {
        final out = await const ComputeJpegRotator().rotate(jpeg(4, 8), 1);
        expect(out, isNotNull);
        final decoded = img.decodeImage(out!)!;
        expect(decoded.width, 8);
        expect(decoded.height, 4);
      },
    );
  });
}
