import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Shared fixture: 640×480 black image with white rect at (120,100)..(520,380).
  Uint8List makeRectFixture() {
    final image = img.Image(width: 640, height: 480, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(image, x1: 120, y1: 100, x2: 520, y2: 380,
        color: img.ColorRgb8(255, 255, 255));
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  group('F1 edge detection — on-device', () {
    late EdgeDetector detector;
    setUp(() => detector = const OpenCvEdgeDetector());

    testWidgets('white rect on dark background → non-null, confidence > 0.5',
        (tester) async {
      final result = await detector.detect(makeRectFixture());
      expect(result, isNotNull);
      expect(result!.confidence, greaterThan(0.5));
    });

    testWidgets('uniform white image → null', (tester) async {
      final image = img.Image(width: 640, height: 480, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final bytes = Uint8List.fromList(img.encodeJpg(image));
      expect(await detector.detect(bytes), isNull);
    });

    testWidgets('circular-only shape → best-guess quad (minAreaRect fallback)',
        (tester) async {
      // Best-guess-always: a large circle (~26% of frame, above the 5% floor)
      // isn't a clean 4-point quad, so the pipeline returns its min-area
      // bounding rectangle. Non-null, but a circle fills only ~π/4 of that
      // rect, so confidence stays modest (the UI tints it amber/"please check").
      const cx = 320, cy = 240, r = 160;
      final image = img.Image(width: 640, height: 480, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));
      for (int y = 0; y < 480; y++) {
        for (int x = 0; x < 640; x++) {
          if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
            image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
          }
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      final result = await detector.detect(bytes);
      expect(result, isNotNull);
      expect(result!.confidence, lessThan(0.9),
          reason: 'a circle is not a clean rectangle — confidence must not be high');
    });

    testWidgets('corrupt bytes → null, no throw', (tester) async {
      final corrupt = Uint8List.fromList([0xFF, 0xD8, 0xAA, 0xBB]);
      expect(await detector.detect(corrupt), isNull);
    });

    testWidgets('corner ordering canonical for axis-aligned rect', (tester) async {
      final result = await detector.detect(makeRectFixture());
      expect(result, isNotNull);
      final c = result!.corners;

      // topLeft smallest (x+y)
      final sumTl = c.topLeft.dx + c.topLeft.dy;
      expect(sumTl, lessThanOrEqualTo(c.topRight.dx + c.topRight.dy));
      expect(sumTl, lessThanOrEqualTo(c.bottomRight.dx + c.bottomRight.dy));
      expect(sumTl, lessThanOrEqualTo(c.bottomLeft.dx + c.bottomLeft.dy));

      // bottomRight largest (x+y)
      final sumBr = c.bottomRight.dx + c.bottomRight.dy;
      expect(sumBr, greaterThanOrEqualTo(c.topLeft.dx + c.topLeft.dy));
      expect(sumBr, greaterThanOrEqualTo(c.topRight.dx + c.topRight.dy));
      expect(sumBr, greaterThanOrEqualTo(c.bottomLeft.dx + c.bottomLeft.dy));

      // all corners in [0,1]
      for (final corner in [c.topLeft, c.topRight, c.bottomRight, c.bottomLeft]) {
        expect(corner.dx, inInclusiveRange(0.0, 1.0));
        expect(corner.dy, inInclusiveRange(0.0, 1.0));
      }
    });

    testWidgets('large image (4000×3000) → detected in < 2 s', (tester) async {
      final image = img.Image(width: 4000, height: 3000, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));
      img.fillRect(image, x1: 400, y1: 300, x2: 3600, y2: 2700,
          color: img.ColorRgb8(255, 255, 255));
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));

      final start = DateTime.now();
      final result = await detector.detect(bytes);
      final elapsed = DateTime.now().difference(start).inMilliseconds;

      expect(result, isNotNull, reason: 'large white rect must be detected');
      expect(elapsed, lessThan(2000),
          reason: 'detection must complete in < 2 s; took ${elapsed}ms');
    });
  });
}
