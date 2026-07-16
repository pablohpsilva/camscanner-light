import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart'
    show kAutoWhiteClip, kAutoBlackAnchor;
import 'package:mobile/features/library/white_point_lut.dart';

/// Builds a 256-bin histogram: [bin] -> count, others 0.
List<int> histAt(int bin, int count) {
  final h = List<int>.filled(256, 0);
  h[bin] = count;
  return h;
}

void main() {
  group('whitePointLut3Table', () {
    test('identity when hi collapses to <= 0 (continue path)', () {
      // Put ALL mass at bin 0 for every channel. Walking hi down from 255,
      // cum stays 0 until hi hits 0 (hc[0]=n), so hi decrements to 0 →
      // `if (hi <= 0) continue;` leaves the identity ramp untouched.
      const n = 1000;
      final histograms = [histAt(0, n), histAt(0, n), histAt(0, n)];

      final lut = whitePointLut3Table(histograms);

      expect(lut.length, 256 * 3);
      for (var v = 0; v < 256; v++) {
        for (var ch = 0; ch < 3; ch++) {
          expect(lut[v * 3 + ch], v, reason: 'lut[$v*3+$ch] must be identity');
        }
      }
    });

    test('stretch case: all mass at bin 200 on channel B (index 0)', () {
      const ch = 0;
      const n = 1000;
      final histograms = [histAt(200, n), histAt(0, n), histAt(0, n)];

      final lut = whitePointLut3Table(histograms);

      // Derive from the exact algorithm.
      // clip = ceil(n*kAutoWhiteClip).clamp(1,n); mass sits only at bin 200,
      // so hi walks 255..201 (all zero, cum stays 0) then stops at 200
      // (cum + n >= clip). hi = 200.
      const hi = 200;
      final anchor = (hi * kAutoBlackAnchor).round(); // (200*0.55)=110
      final span = hi - anchor; // 90

      for (var v = 0; v <= anchor; v++) {
        expect(
          lut[v * 3 + ch],
          v,
          reason: 'v<=anchor untouched identity at v=$v',
        );
      }
      for (var v = anchor + 1; v < 256; v++) {
        final expected = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
        expect(lut[v * 3 + ch], expected, reason: 'stretched at v=$v');
      }
      // Sanity: constants are what we assumed.
      expect(kAutoBlackAnchor, 0.55);
      expect(kAutoWhiteClip, 0.01);
    });

    test(
      'channel independence: stretch on R (index 2) leaves B/G identity',
      () {
        const n = 1000;
        // Only channel R (index 2) has stretchable mass at bin 200.
        // Channels B/G have all mass at bin 0 → they hit the continue path.
        final histograms = [histAt(0, n), histAt(0, n), histAt(200, n)];

        final lut = whitePointLut3Table(histograms);

        // B (0) and G (1) stay identity everywhere.
        for (var v = 0; v < 256; v++) {
          expect(lut[v * 3 + 0], v, reason: 'B identity at v=$v');
          expect(lut[v * 3 + 1], v, reason: 'G identity at v=$v');
        }

        // R (2) is stretched per the algorithm.
        const hi = 200;
        final anchor = (hi * kAutoBlackAnchor).round();
        final span = hi - anchor;
        for (var v = 0; v <= anchor; v++) {
          expect(lut[v * 3 + 2], v, reason: 'R identity v<=anchor at v=$v');
        }
        for (var v = anchor + 1; v < 256; v++) {
          final expected = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
          expect(lut[v * 3 + 2], expected, reason: 'R stretched at v=$v');
        }
      },
    );
  });
}
