import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/bw_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  group('NoneEnhancer (regression)', () {
    test('returns the exact same bytes object unchanged', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await const NoneEnhancer().enhance(bytes);
      expect(identical(result, bytes), isTrue);
    });
  });

  group('BwEnhancer', () {
    test('every output pixel is near-binary after JPEG re-encode (≤10 or ≥245)', () async {
      // Build a 4×4 color image (various colors) and encode as JPEG.
      final src = img.Image(width: 4, height: 4, numChannels: 3);
      int i = 0;
      for (final p in src) {
        p.r = (i * 40) % 256;
        p.g = (i * 70) % 256;
        p.b = (i * 110) % 256;
        i++;
      }
      final inputBytes = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final resultBytes = await const BwEnhancer().enhance(inputBytes);

      final decoded = img.decodeImage(resultBytes)!;
      for (final p in decoded) {
        final r = p.r.toInt();
        expect(r <= 10 || r >= 245, isTrue,
            reason: 'Expected near-binary pixel (≤10 or ≥245), got $r at (${p.x},${p.y})');
      }
    });

    test('bimodal image: near-binary output after JPEG encode (≤10 or ≥245)', () async {
      // Left half black (0,0,0), right half white (255,255,255).
      // Otsu must find a threshold strictly between the two clusters.
      final src = img.Image(width: 8, height: 8, numChannels: 3);
      for (final p in src) {
        final isWhite = p.x >= 4;
        p.r = isWhite ? 255 : 0;
        p.g = isWhite ? 255 : 0;
        p.b = isWhite ? 255 : 0;
      }
      final inputBytes = Uint8List.fromList(img.encodeJpg(src, quality: 100));

      final resultBytes = await const BwEnhancer().enhance(inputBytes);

      // The output must be all-binary (inherited from the first test's logic).
      final decoded = img.decodeImage(resultBytes)!;
      for (final p in decoded) {
        final r = p.r.toInt();
        expect(r <= 10 || r >= 245, isTrue,
            reason: 'Expected near-binary pixel (≤10 or ≥245), got $r at (${p.x},${p.y})');
      }
    });

    test('returns input bytes unchanged when decoding fails (corrupt data)',
        () async {
      final garbage = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final result = await const BwEnhancer().enhance(garbage);
      expect(result, equals(garbage));
    });

    test(
        'bakes EXIF orientation: landscape_exif6 (200×100, orient=6) '
        'becomes portrait (100×200) after enhance', () async {
      // landscape_exif6.jpg is 200×100 pixels with EXIF Orientation = 6
      // (90° CW). After bakeOrientation the stored pixel matrix becomes
      // 100×200 (portrait). encodeJpg writes no EXIF, so the result is
      // already in display orientation — no further rotation needed.
      final bytes = Uint8List.fromList(
          File('test/fixtures/landscape_exif6.jpg').readAsBytesSync());
      final result = await const BwEnhancer().enhance(bytes);
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 100,
          reason: '90° CW bake swaps width and height');
      expect(decoded.height, 200);
    });
  });
}
