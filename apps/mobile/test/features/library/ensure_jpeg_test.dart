import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/ensure_jpeg.dart';

void main() {
  test('PNG bytes are converted to JPEG (SOI marker + decodable)', () {
    final png = img.encodePng(img.Image(width: 4, height: 4));
    final out = ensureJpegBytes(png);
    expect(out[0], 0xFF, reason: 'JPEG SOI byte 0');
    expect(out[1], 0xD8, reason: 'JPEG SOI byte 1');
    expect(img.decodeImage(out), isNotNull);
  });

  test('JPEG bytes pass through unchanged (no re-encode)', () {
    final jpg = img.encodeJpg(img.Image(width: 4, height: 4), quality: 90);
    final out = ensureJpegBytes(jpg);
    expect(identical(out, jpg), isTrue);
  });

  test(
    'non-image bytes are returned unchanged (scrubber fails closed later)',
    () {
      final garbage = Uint8List.fromList([1, 2, 3, 4]);
      expect(ensureJpegBytes(garbage), same(garbage));
    },
  );
}
