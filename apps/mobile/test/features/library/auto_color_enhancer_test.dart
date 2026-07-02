import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/color_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  group('AutoEnhancer', () {
    test('flattens a shadow gradient: shadowed background becomes near-white, '
        'text stays dark, background variance collapses', () async {
      // 120x40 page: horizontal brightness gradient simulates a shadow
      // (left = dark 120, right = lit 240). Two dark "text" blocks: one in the
      // shadowed left, one in the lit right.
      const w = 120, h = 40;
      final src = img.Image(width: w, height: h);
      int bgVal(int x) => 120 + (x * 120 ~/ (w - 1)); // 120..240
      for (final px in src) {
        final v = bgVal(px.x);
        px..r = v..g = v..b = v;
      }
      for (var y = 15; y <= 25; y++) {
        for (var x = 10; x <= 20; x++) { src.getPixel(x, y)..r = 20..g = 20..b = 20; }
        for (var x = 100; x <= 110; x++) { src.getPixel(x, y)..r = 20..g = 20..b = 20; }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);
      final out = img.decodeImage(output)!;

      final bgSamples = [2, 30, 60, 90, 117]
          .map((x) => out.getPixel(x, 5).luminance.toDouble())
          .toList();
      for (final s in bgSamples) {
        expect(s, greaterThan(220),
            reason: 'every background sample (incl. the shadowed left) must be near-white');
      }
      final mean = bgSamples.reduce((a, b) => a + b) / bgSamples.length;
      final variance = bgSamples
              .map((s) => (s - mean) * (s - mean))
              .reduce((a, b) => a + b) /
          bgSamples.length;
      expect(variance, lessThan(100),
          reason: 'shadow gradient removed → background brightness is uniform');

      expect(out.getPixel(15, 20).luminance, lessThan(120),
          reason: 'shadowed-side text must remain dark');
      expect(out.getPixel(105, 20).luminance, lessThan(120),
          reason: 'lit-side text must remain dark');
    });

    test('neutralises a warm shadow cast: warm-tinted paper background '
        'comes out near-neutral white (per-channel flat-field)', () async {
      // 120x40 page lit by a warm light: background is redder than it is blue
      // (r = 210..250, b = 150..210 across the width) — the classic warm cast
      // of a hand/desk shadow. A grayscale flat-field would leave it orange;
      // the per-channel divide must pull every channel to a neutral white.
      const w = 120, h = 40;
      final src = img.Image(width: w, height: h);
      for (final px in src) {
        final t = px.x / (w - 1); // 0..1
        px
          ..r = (210 + 40 * t).round()
          ..g = (185 + 40 * t).round()
          ..b = (150 + 60 * t).round();
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);
      final out = img.decodeImage(output)!;

      for (final x in [10, 60, 110]) {
        final px = out.getPixel(x, 20);
        expect(px.r, greaterThan(230),
            reason: 'background must be near-white after cast removal');
        expect((px.r.toInt() - px.b.toInt()).abs(), lessThan(25),
            reason: 'warm cast neutralised: R and B nearly equal at x=$x');
      }
    });

    test('image smaller than the background proxy does not crash', () async {
      final src = img.Image(width: 8, height: 8);
      for (final px in src) { px..r = 200..g = 180..b = 160; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      expect(img.decodeImage(output), isNotNull,
          reason: 'tiny frames skip the downscale and must still produce valid JPEG');
    });

    test('stretches contrast: max channel value reaches near-255 after enhancement',
        () async {
      // Bright neutral paper with a smooth column gradient (150..230): after
      // flat-field + auto-levels the brightest region reaches near-white.
      final src = img.Image(width: 8, height: 8);
      for (final px in src) {
        final v = 150 + (px.x * 80 ~/ 7);
        px..r = v..g = v..b = v;
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      int maxR = 0;
      for (final px in decoded) {
        if (px.r.toInt() > maxR) maxR = px.r.toInt();
      }
      expect(maxR, greaterThan(220),
          reason: 'Auto should stretch R to near-255 on paper');
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
          reason: 'AutoEnhancer must not convert image to grayscale (flat-field preserves hue)');
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
