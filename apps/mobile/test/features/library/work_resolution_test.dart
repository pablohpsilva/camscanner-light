import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/work_resolution.dart';

void main() {
  group('computeWorkResolution', () {
    test('no downscale when longer side is below cap', () {
      final r = computeWorkResolution(3000, 2000, 3500);
      expect(r.scale, 1.0);
      expect(r.targetW, 3000);
      expect(r.targetH, 2000);
    });

    test('no downscale when longer side equals cap (edge: long == cap)', () {
      final r = computeWorkResolution(3500, 1000, 3500);
      expect(r.scale, 1.0);
      expect(r.targetW, 3500);
      expect(r.targetH, 1000);
    });

    test('proportional downscale for a landscape source over cap', () {
      final r = computeWorkResolution(7000, 3500, 3500);
      expect(r.scale, 0.5);
      expect(r.targetW, 3500);
      expect(r.targetH, 1750);
    });

    test('proportional downscale for a portrait source over cap', () {
      final r = computeWorkResolution(3500, 7000, 3500);
      expect(r.scale, 0.5);
      expect(r.targetW, 1750);
      expect(r.targetH, 3500);
    });

    test('both dims clamped to >= 2 for an extreme aspect ratio', () {
      // short side would round to 0 without the clamp.
      final r = computeWorkResolution(10000, 3, 100);
      expect(r.targetW, greaterThanOrEqualTo(2));
      expect(r.targetH, greaterThanOrEqualTo(2));
      expect(r.targetH, 2);
    });

    test('over-cap long side is scaled exactly to cap (monotonic property)', () {
      final a = computeWorkResolution(9000, 6000, 3000);
      final b = computeWorkResolution(12000, 8000, 3000);
      // Long side always lands on the cap when over it, regardless of source.
      expect(a.targetW, 3000);
      expect(b.targetW, 3000);
      // Larger-but-same-cap source never yields a larger long-side target.
      expect(b.targetW, lessThanOrEqualTo(a.targetW));
    });
  });
}
