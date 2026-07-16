import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/oriented_enhance.dart';

/// P09 Task 4: the three enhancer isolate bodies (auto/color/grayscale) were
/// identical boilerplate — decode → null-guard → bakeOrientation → encodeJpg(
/// op(...), quality) → catch→return bytes. runOrientedEnhance is the single
/// shared body; only the op + quality differ. These host tests lock its
/// contract (no CV needed).
void main() {
  Uint8List jpegOf(img.Image image) =>
      Uint8List.fromList(img.encodeJpg(image, quality: 92));

  test('corrupt bytes are returned UNCHANGED (never lose a page)', () {
    final garbage = Uint8List.fromList(const [0, 1, 2, 3, 4, 5]);
    final out = runOrientedEnhance(garbage, (im) => im, quality: 95);
    expect(out, same(garbage));
  });

  test('the op is applied to the decoded image', () {
    // A 4x4 mid-grey image; the op fills it white. The result must decode to
    // an all-white image (the op ran), not the original grey.
    final src = img.Image(width: 4, height: 4);
    img.fill(src, color: img.ColorRgb8(128, 128, 128));
    final bytes = jpegOf(src);

    img.Image whiteOut(img.Image im) {
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      return im;
    }

    final out = runOrientedEnhance(bytes, whiteOut, quality: 92);
    final decoded = img.decodeImage(out)!;
    final px = decoded.getPixel(0, 0);
    expect(px.r, greaterThan(250));
    expect(px.g, greaterThan(250));
    expect(px.b, greaterThan(250));
  });

  test('identity op round-trips a valid JPEG (decodes back to same size)', () {
    final src = img.Image(width: 8, height: 6);
    img.fill(src, color: img.ColorRgb8(10, 200, 30));
    final out = runOrientedEnhance(jpegOf(src), (im) => im);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 8);
    expect(decoded.height, 6);
  });

  test('quality is passed through to the encoder (95 > 92 file size)', () {
    // A noisy image so JPEG quality visibly changes the encoded size.
    final src = img.Image(width: 64, height: 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        src.setPixelRgb(x, y, (x * 37) % 256, (y * 53) % 256, (x * y) % 256);
      }
    }
    final bytes = jpegOf(src);
    final q95 = runOrientedEnhance(bytes, (im) => im, quality: 95);
    final q92 = runOrientedEnhance(bytes, (im) => im, quality: 92);
    expect(q95.length, greaterThan(q92.length));
  });
}
