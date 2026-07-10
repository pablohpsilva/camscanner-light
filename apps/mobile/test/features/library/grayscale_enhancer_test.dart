import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  group('NoneEnhancer', () {
    test('returns the exact same bytes object unchanged', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await const NoneEnhancer().enhance(bytes);
      expect(identical(result, bytes), isTrue);
    });
  });

  group('GrayscaleEnhancer', () {
    test(
      'converts a color JPEG so every pixel has R == G == B (±5 tolerance)',
      () async {
        // Build a 4×4 solid-red image in memory and encode as JPEG.
        final src = img.Image(width: 4, height: 4, numChannels: 3);
        for (final p in src) {
          p.r = 200;
          p.g = 50;
          p.b = 50;
        }
        final inputBytes = Uint8List.fromList(img.encodeJpg(src, quality: 95));

        final resultBytes = await const GrayscaleEnhancer().enhance(inputBytes);

        final decoded = img.decodeImage(resultBytes)!;
        for (final p in decoded) {
          expect(
            (p.r - p.g).abs(),
            lessThanOrEqualTo(5),
            reason: 'R≠G at (${p.x},${p.y})',
          );
          expect(
            (p.g - p.b).abs(),
            lessThanOrEqualTo(5),
            reason: 'G≠B at (${p.x},${p.y})',
          );
        }
      },
    );

    test(
      'returns input bytes unchanged when decoding fails (corrupt data)',
      () async {
        final garbage = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final result = await const GrayscaleEnhancer().enhance(garbage);
        expect(result, equals(garbage));
      },
    );

    test('bakes EXIF orientation: landscape_exif6 (200×100, orient=6) '
        'becomes portrait (100×200) after enhance', () async {
      // landscape_exif6.jpg is 200×100 pixels with EXIF Orientation = 6
      // (90° CW). After bakeOrientation the stored pixel matrix becomes
      // 100×200 (portrait). encodeJpg writes no EXIF, so the result is
      // already in display orientation — no further rotation needed.
      final bytes = Uint8List.fromList(
        File('test/fixtures/landscape_exif6.jpg').readAsBytesSync(),
      );
      final result = await const GrayscaleEnhancer().enhance(bytes);
      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 100, reason: '90° CW bake swaps width and height');
      expect(decoded.height, 200);
    });
  });
}
