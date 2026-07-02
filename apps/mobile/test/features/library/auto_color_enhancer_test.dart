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
      // Dark text blocks (value 20) at left (x10-20) and right (x100-110), y15-25.
      for (var y = 15; y <= 25; y++) {
        for (var x = 10; x <= 20; x++) { src.getPixel(x, y)..r = 20..g = 20..b = 20; }
        for (var x = 100; x <= 110; x++) { src.getPixel(x, y)..r = 20..g = 20..b = 20; }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);
      final out = img.decodeImage(output)!;

      // Background samples at y=5 (no text) across the frame.
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

      // Text stays dark relative to its now-white background.
      expect(out.getPixel(15, 20).luminance, lessThan(120),
          reason: 'shadowed-side text must remain dark');
      expect(out.getPixel(105, 20).luminance, lessThan(120),
          reason: 'lit-side text must remain dark');
    });

    test('image smaller than the background proxy does not crash', () async {
      final src = img.Image(width: 8, height: 8);
      for (final px in src) { px..r = 200..g = 180..b = 160; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      expect(img.decodeImage(output), isNotNull,
          reason: 'tiny frames skip the downscale and must still produce valid JPEG');
    });

    test('preserves a large dark region (embedded photo) instead of blowing it '
        'out, while still flattening the surrounding shadowed paper', () async {
      const w = 200, h = 200;
      final src = img.Image(width: w, height: h);
      // Paper with a left-to-right shadow gradient: dark-left 150 .. lit-right 245.
      int bgVal(int x) => 150 + (x * 95 ~/ (w - 1));
      for (final px in src) {
        final v = bgVal(px.x);
        px..r = v..g = v..b = v;
      }
      // Large solid-dark block (an embedded photo), luminance ~40, 80x80 px.
      for (var y = 60; y < 140; y++) {
        for (var x = 60; x < 140; x++) {
          src.getPixel(x, y)..r = 40..g = 40..b = 40;
        }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);
      final out = img.decodeImage(output)!;

      // Block interior must stay dark — NOT blown out to white.
      expect(out.getPixel(100, 100).luminance, lessThan(100),
          reason: 'large dark region (photo) must be preserved, not whitened');
      // Surrounding paper (incl. the shadowed left edge) still flattens to white.
      expect(out.getPixel(10, 100).luminance, greaterThan(220),
          reason: 'shadowed paper around the photo must still be flattened');
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

  group('correctionWeight', () {
    test('is 0 for dark content at or below the paper floor', () {
      expect(correctionWeight(40), 0.0);
      expect(correctionWeight(95), 0.0);
    });
    test('is 1 for paper at or above floor + band', () {
      expect(correctionWeight(120), 1.0);
      expect(correctionWeight(240), 1.0);
    });
    test('ramps linearly across the transition band', () {
      // floor 95, band 25 → (107-95)/25 = 0.48
      expect(correctionWeight(107), closeTo(0.48, 0.02));
      expect(correctionWeight(95 + 25), 1.0);
    });
  });

  group('localStdDev', () {
    test('is 0 on a uniform region', () {
      final im = img.Image(width: 5, height: 5);
      for (final px in im) { px..r = 120..g = 120..b = 120; }
      expect(localStdDev(im, 2, 2), lessThan(0.5));
    });
    test('is high on a varied region', () {
      final im = img.Image(width: 5, height: 5);
      var i = 0;
      for (final px in im) { final v = (i++ % 2 == 0) ? 20 : 220; px..r = v..g = v..b = v; }
      expect(localStdDev(im, 2, 2), greaterThan(50));
    });
  });

  group('fillHoles', () {
    test('fills a background hole fully enclosed by foreground', () {
      // 7x7: foreground ring (255) with a single-pixel background hole at centre.
      final m = img.Image(width: 7, height: 7);
      for (final px in m) { px..r = 0..g = 0..b = 0; }
      for (var y = 2; y <= 4; y++) {
        for (var x = 2; x <= 4; x++) { m.getPixel(x, y)..r = 255..g = 255..b = 255; }
      }
      m.getPixel(3, 3)..r = 0..g = 0..b = 0; // the enclosed hole

      final filled = fillHoles(m);

      expect(filled.getPixel(3, 3).r, 255, reason: 'enclosed hole becomes foreground');
      expect(filled.getPixel(0, 0).r, 0, reason: 'border background stays background');
    });
  });

  group('buildCorrectionMask', () {
    test('colorful patch on neutral paper is detected as photo (alpha ~0)', () {
      final proxy = img.Image(width: 30, height: 30);
      for (final px in proxy) { px..r = 235..g = 233..b = 230; } // neutral paper
      for (var y = 8; y < 22; y++) {
        for (var x = 8; x < 22; x++) { proxy.getPixel(x, y)..r = 200..g = 40..b = 40; } // saturated red
      }
      final mask = buildCorrectionMask(proxy);
      expect(mask.getPixel(15, 15).r, lessThan(80), reason: 'colorful region → preserved');
      expect(mask.getPixel(1, 1).r, greaterThan(200), reason: 'paper → full correction');
    });

    test('sparse thin dark strokes (text) are NOT detected as photo (bias)', () {
      final proxy = img.Image(width: 30, height: 30);
      for (final px in proxy) { px..r = 232..g = 232..b = 232; } // bright neutral paper
      // isolated single-pixel dark "strokes" scattered — thin, sparse.
      for (final p in [[5,5],[9,5],[13,5],[5,9],[9,9],[20,20],[24,20]]) {
        proxy.getPixel(p[0], p[1])..r = 35..g = 35..b = 35;
      }
      final mask = buildCorrectionMask(proxy);
      // After opening, isolated speckles are erased → paper weight everywhere.
      expect(mask.getPixel(9, 5).r, greaterThan(180),
          reason: 'thin text must remain paper so it still gets de-shadowed');
      expect(mask.getPixel(1, 1).r, greaterThan(200));
    });

    test('bright patch enclosed by a dark photo body is absorbed (alpha ~0)', () {
      final proxy = img.Image(width: 30, height: 30);
      for (final px in proxy) { px..r = 235..g = 235..b = 235; }
      for (var y = 6; y < 24; y++) {
        for (var x = 6; x < 24; x++) { proxy.getPixel(x, y)..r = 40..g = 40..b = 40; } // dark body
      }
      for (var y = 12; y < 18; y++) {
        for (var x = 12; x < 18; x++) { proxy.getPixel(x, y)..r = 200..g = 200..b = 200; } // bright hole
      }
      final mask = buildCorrectionMask(proxy);
      expect(mask.getPixel(15, 15).r, lessThan(80),
          reason: 'bright area enclosed by the photo must be preserved too');
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
