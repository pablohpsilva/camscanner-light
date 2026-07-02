import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

/// A dark "desk" with a mid-gray "page" rectangle, lit by a soft shadow: the
/// page brightness ramps from bright (left) to dimmed (right), so its right
/// edge nearly matches the surrounding desk — the exact case that defeats a
/// fixed-threshold Canny.
Uint8List _shadowedPage({
  int w = 800,
  int h = 600,
  int rx1 = 140,
  int ry1 = 110,
  int rx2 = 660,
  int ry2 = 490,
}) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(40, 40, 40)); // dark desk
  for (int y = ry1; y <= ry2; y++) {
    for (int x = rx1; x <= rx2; x++) {
      final t = (x - rx1) / (rx2 - rx1); // 0 (left) → 1 (right)
      final v = (210 - 150 * t).round().clamp(0, 255); // 210 → 60
      image.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('f3: shadow-tolerant detection (on-device, real libdartcv)', () {
    const detector = OpenCvEdgeDetector();

    test('localizes a soft-shadowed page rectangle', () async {
      final result = await detector.detect(_shadowedPage());
      expect(result, isNotNull,
          reason: 'flat-field normalization must recover the dimmed edge');

      final c = result!.corners;
      // Expected normalized rect bounds: x in [140/800, 660/800] = [0.175, 0.825],
      // y in [110/600, 490/600] = [0.183, 0.817]. Allow 8% tolerance for
      // downscale + Canny + morphology drift.
      const tol = 0.08;
      expect(c.topLeft.dx, closeTo(0.175, tol));
      expect(c.topLeft.dy, closeTo(0.183, tol));
      expect(c.topRight.dx, closeTo(0.825, tol),
          reason: 'the shadow-dimmed right edge must still be found');
      expect(c.bottomRight.dy, closeTo(0.817, tol));
      expect(c.bottomLeft.dx, closeTo(0.175, tol));
    });

    test('high-contrast page is not regressed', () async {
      // Same layout, uniform bright page — the easy case must stay accurate.
      final image = img.Image(width: 800, height: 600, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(40, 40, 40));
      img.fillRect(image,
          x1: 140, y1: 110, x2: 660, y2: 490,
          color: img.ColorRgb8(230, 230, 230));
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));

      final result = await detector.detect(bytes);
      expect(result, isNotNull);
      expect(result!.confidence, greaterThan(0.7),
          reason: 'a clean rectangle should score high');
      const tol = 0.06;
      expect(result.corners.topLeft.dx, closeTo(0.175, tol));
      expect(result.corners.bottomRight.dx, closeTo(0.825, tol));
    });
  });
}
