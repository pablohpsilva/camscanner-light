import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/color_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  group('AutoEnhancer', () {
    test('stretches contrast: max channel value reaches near-255 after enhancement', () async {
      final src = img.Image(width: 4, height: 4);
      final rVals = [80, 93, 107, 120];
      int i = 0;
      for (final px in src) {
        px.r = rVals[i % 4];
        px.g = rVals[i % 4] - 20;
        px.b = rVals[i % 4] + 10;
        i++;
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      int maxR = 0;
      for (final px in decoded) {
        if (px.r.toInt() > maxR) maxR = px.r.toInt();
      }
      expect(maxR, greaterThan(220),
          reason: 'Auto-levels should stretch R to near-255');
    });

    test('preserves color: output is not grayscale (R channel differs from G)', () async {
      final src = img.Image(width: 4, height: 4);
      int i = 0;
      for (final px in src) {
        if (i < 8) { px.r = 200; px.g = 50; px.b = 50; }
        else        { px.r = 50;  px.g = 200; px.b = 50; }
        i++;
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      bool hasColorVariation = false;
      for (final px in decoded) {
        if ((px.r.toInt() - px.g.toInt()).abs() > 30) {
          hasColorVariation = true;
          break;
        }
      }
      expect(hasColorVariation, isTrue,
          reason: 'AutoEnhancer must not convert image to grayscale');
    });

    test('returns bytes unchanged when decoding fails (corrupt data)', () async {
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final output = await const AutoEnhancer().enhance(corrupt);
      expect(output, equals(corrupt));
    });

    test('bakes EXIF orientation: landscape_exif6 (200x100, orient=6) becomes portrait (100x200)',
        () async {
      final bytes = Uint8List.fromList(
          await File('test/fixtures/landscape_exif6.jpg').readAsBytes());
      final output = await const AutoEnhancer().enhance(bytes);
      final decoded = img.decodeImage(output)!;
      expect(decoded.width, 100);
      expect(decoded.height, 200);
    });

    test('uniform image (all same color) returns valid JPEG without crash', () async {
      final src = img.Image(width: 4, height: 4);
      for (final px in src) { px.r = 128; px.g = 128; px.b = 128; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      expect(img.decodeImage(output), isNotNull,
          reason: 'Uniform image must not crash; degenerate auto-levels should be a no-op');
    });
  });

  group('ColorEnhancer', () {
    test('preserves color: output is not grayscale (R channel differs from G)', () async {
      final src = img.Image(width: 4, height: 4);
      for (final px in src) { px.r = 180; px.g = 80; px.b = 60; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const ColorEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      bool allGrayscale = true;
      for (final px in decoded) {
        if ((px.r.toInt() - px.g.toInt()).abs() > 20) {
          allGrayscale = false;
          break;
        }
      }
      expect(allGrayscale, isFalse,
          reason: 'ColorEnhancer must not convert image to grayscale');
    });

    test('returns bytes unchanged when decoding fails (corrupt data)', () async {
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final output = await const ColorEnhancer().enhance(corrupt);
      expect(output, equals(corrupt));
    });

    test('bakes EXIF orientation: landscape_exif6 (200x100, orient=6) becomes portrait (100x200)',
        () async {
      final bytes = Uint8List.fromList(
          await File('test/fixtures/landscape_exif6.jpg').readAsBytes());
      final output = await const ColorEnhancer().enhance(bytes);
      final decoded = img.decodeImage(output)!;
      expect(decoded.width, 100);
      expect(decoded.height, 200);
    });
  });

  group('NoneEnhancer (regression)', () {
    test('returns the exact same bytes object unchanged', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await const NoneEnhancer().enhance(bytes);
      expect(identical(result, bytes), isTrue);
    });
  });
}
