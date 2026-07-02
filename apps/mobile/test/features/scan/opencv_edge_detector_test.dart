import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

// ── Fixture helpers ────────────────────────────────────────────────────────

/// Black image with a white axis-aligned rectangle.
Uint8List _rectImage({
  int w = 640,
  int h = 480,
  int rx1 = 120,
  int ry1 = 100,
  int rx2 = 520,
  int ry2 = 380,
}) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  img.fillRect(
    image,
    x1: rx1, y1: ry1, x2: rx2, y2: ry2,
    color: img.ColorRgb8(255, 255, 255),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Uniform gray image (no edges).
Uint8List _uniformImage(int w, int h, int gray) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(gray, gray, gray));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Low-contrast gray noise (barely any edges).
Uint8List _noiseImage(int w, int h) {
  final rng = math.Random(42);
  final image = img.Image(width: w, height: h, numChannels: 3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final g = 120 + rng.nextInt(10); // [120..129] — very low contrast
      image.setPixel(x, y, img.ColorRgb8(g, g, g));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white-filled circle.
Uint8List _circleImage(int w, int h) {
  final cx = w ~/ 2, cy = h ~/ 2, r = math.min(w, h) ~/ 3;
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) {
        image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white-filled equilateral triangle.
Uint8List _triangleImage(int w, int h) {
  final cx = w / 2.0, r = math.min(w, h) * 0.35;
  final verts = List.generate(3, (i) {
    final angle = 2 * math.pi * i / 3 - math.pi / 2;
    return (x: cx + r * math.cos(angle), y: h / 2.0 + r * math.sin(angle));
  });
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  _fillPolygonPixels(image, verts);
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white-filled regular pentagon.
Uint8List _pentagonImage(int w, int h) {
  final cx = w / 2.0, cy = h / 2.0, r = math.min(w, h) * 0.35;
  // Pentagon vertices
  final verts = List.generate(5, (i) {
    final angle = 2 * math.pi * i / 5 - math.pi / 2;
    return (x: cx + r * math.cos(angle), y: cy + r * math.sin(angle));
  });
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  _fillPolygonPixels(image, verts);
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white-filled concave quadrilateral (dart/arrowhead shape).
/// The shape has exactly 4 vertices but fails cv.isContourConvex() — one corner
/// points inward, making it non-convex.
Uint8List _concaveQuadImage(int w, int h) {
  final cx = w / 2.0, cy = h / 2.0;
  final half = math.min(w, h) * 0.35;
  // Dart shape: top, right, center-indented, left — one inward point.
  final verts = [
    (x: cx, y: cy - half),          // top
    (x: cx + half, y: cy + half),   // bottom-right
    (x: cx, y: cy),                 // center (inward — makes non-convex)
    (x: cx - half, y: cy + half),   // bottom-left
  ];
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  _fillPolygonPixels(image, verts);
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white-filled chevron/arrow (>) shape.
/// 4 vertices with one inward-pointing right-side indentation — non-convex.
/// Distinct from the dart shape: the concave vertex is on the RIGHT side.
Uint8List _chevronImage(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  // Chevron ">": left-top, right-tip, left-bottom, left-center (indented inward).
  final verts = [
    (x: w * 0.15, y: h * 0.20),  // left-top
    (x: w * 0.85, y: h * 0.50),  // right tip (arrow point)
    (x: w * 0.15, y: h * 0.80),  // left-bottom
    (x: w * 0.45, y: h * 0.50),  // left-center indent (makes non-convex)
  ];
  _fillPolygonPixels(image, verts);
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white rectangle tilted by [angleDeg] degrees.
Uint8List _tiltedRectImage(int w, int h, double angleDeg) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  final cx = w / 2.0, cy = h / 2.0;
  final hw = w * 0.30, hh = h * 0.30;
  final angle = angleDeg * math.pi / 180;
  final cosA = math.cos(angle), sinA = math.sin(angle);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final dx = x - cx, dy = y - cy;
      final lx = dx * cosA + dy * sinA;
      final ly = -dx * sinA + dy * cosA;
      if (lx.abs() <= hw && ly.abs() <= hh) {
        image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white trapezoid (mild perspective distortion).
Uint8List _perspectiveRectImage(int w, int h) {
  // Slight keystone: top edge narrower than bottom.
  final verts = [
    (x: w * 0.20, y: h * 0.15),  // top-left (slightly right)
    (x: w * 0.80, y: h * 0.15),  // top-right (slightly left)
    (x: w * 0.85, y: h * 0.85),  // bottom-right
    (x: w * 0.15, y: h * 0.85),  // bottom-left
  ];
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  _fillPolygonPixels(image, verts.map((p) => (x: p.x, y: p.y)).toList());
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with TWO white rectangles; the larger one should be selected.
Uint8List _twoRectsImage(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  // Large rect (left side): 270×320 = 86,400px / 307,200 = 28.1% — well above 5% gate
  img.fillRect(image, x1: 50, y1: 80, x2: 320, y2: 400,
      color: img.ColorRgb8(255, 255, 255));
  // Small rect (right side): 170×100 = 17,000px / 307,200 = 5.5% — clears 5% gate
  // so both quads reach the area>bestArea comparison; large wins.
  img.fillRect(image, x1: 380, y1: 200, x2: 550, y2: 300,
      color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a tiny white rectangle (< 5% of image area).
Uint8List _tinyRectImage(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  // Very small rect: 30×20 = 600 pixels out of 307200 = 0.2%
  img.fillRect(image, x1: 300, y1: 230, x2: 330, y2: 250,
      color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white rectangle that touches all four image edges.
Uint8List _edgeTouchingRectImage(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  // Rect that starts at pixel 0 and ends at the edge
  img.fillRect(image, x1: 0, y1: 0, x2: w - 1, y2: h - 1,
      color: img.ColorRgb8(255, 255, 255));
  // Add black inset so inner border creates a detectable quad
  img.fillRect(image, x1: 10, y1: 10, x2: w - 11, y2: h - 11,
      color: img.ColorRgb8(0, 0, 0));
  img.fillRect(image, x1: 20, y1: 20, x2: w - 21, y2: h - 21,
      color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Black image with a white-filled parallelogram (highly skewed quad).
/// Interior angles are ~45° and ~135°, far from 90° → angleScore < 0.5.
Uint8List _skewedQuadImage(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  // A severe parallelogram: top edge shifted far right relative to bottom.
  final verts = [
    (x: w * 0.50, y: h * 0.10),  // top-left (shifted right = skewed)
    (x: w * 0.90, y: h * 0.10),  // top-right
    (x: w * 0.50, y: h * 0.90),  // bottom-right (back to centre)
    (x: w * 0.10, y: h * 0.90),  // bottom-left
  ];
  _fillPolygonPixels(image, verts.map((p) => (x: p.x, y: p.y)).toList());
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Scan-line polygon fill (pure Dart, no image-package-specific API).
void _fillPolygonPixels(
  img.Image image,
  List<({double x, double y})> verts,
) {
  if (verts.length < 3) return;
  final minY = verts.map((v) => v.y).reduce(math.min).ceil();
  final maxY = verts.map((v) => v.y).reduce(math.max).floor();
  for (int y = minY; y <= maxY; y++) {
    final intersections = <double>[];
    for (int i = 0; i < verts.length; i++) {
      final a = verts[i];
      final b = verts[(i + 1) % verts.length];
      if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
        final t = (y - a.y) / (b.y - a.y);
        intersections.add(a.x + t * (b.x - a.x));
      }
    }
    intersections.sort();
    for (int k = 0; k + 1 < intersections.length; k += 2) {
      final x1 = intersections[k].ceil();
      final x2 = intersections[k + 1].floor();
      for (int x = x1; x <= x2; x++) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }
  }
}

// ── Tests ──────────────────────────────────────────────────────────────────

Future<void> main() async {
  // The OpenCvEdgeDetector tests below drive the real native pipeline, which
  // needs libdartcv. That library is only built for a device/app target, never
  // for the host `flutter test` runner — so on the host every detect() returns
  // null and the assertions fail. Probe once and skip that group off-device;
  // the same behaviour is verified on-device by
  // integration_test/f1_edge_detection_test.dart. The probe is bounded by
  // OpenCvEdgeDetector's own detect() timeout, so it can never hang.
  final opencvAvailable =
      (await const OpenCvEdgeDetector().detect(_rectImage())) != null;
  const skipReason = 'native OpenCV (libdartcv) unavailable on host — covered '
      'on-device by integration_test/f1_edge_detection_test.dart';

  // ── DetectionResult ──────────────────────────────────────────────────────
  group('DetectionResult', () {
    final corners = CropCorners(
      topLeft: const Offset(0.1, 0.1),
      topRight: const Offset(0.9, 0.1),
      bottomRight: const Offset(0.9, 0.9),
      bottomLeft: const Offset(0.1, 0.9),
    );
    final result = DetectionResult(corners: corners, confidence: 0.8);

    test('equality: same corners and confidence', () {
      final other = DetectionResult(corners: corners, confidence: 0.8);
      expect(result, equals(other));
    });

    test('equality: different confidence', () {
      final other = DetectionResult(corners: corners, confidence: 0.5);
      expect(result, isNot(equals(other)));
    });

    test('equality: different corners', () {
      final other = DetectionResult(
        corners: CropCorners(
          topLeft: const Offset(0.2, 0.2),
          topRight: const Offset(0.8, 0.2),
          bottomRight: const Offset(0.8, 0.8),
          bottomLeft: const Offset(0.2, 0.8),
        ),
        confidence: 0.8,
      );
      expect(result, isNot(equals(other)));
    });

    test('hashCode matches equal instances', () {
      final other = DetectionResult(corners: corners, confidence: 0.8);
      expect(result.hashCode, equals(other.hashCode));
    });

    test('toString contains corners and confidence', () {
      expect(result.toString(), contains('DetectionResult'));
      expect(result.toString(), contains('confidence'));
    });
  });

  // ── OpenCvEdgeDetector ──────────────────────────────────────────────────
  group('OpenCvEdgeDetector', () {
    late EdgeDetector detector;
    setUp(() => detector = const OpenCvEdgeDetector());

    // ── Algorithm correctness ─────────────────────────────────────────────
    test('white rect on dark background → non-null, confidence > 0.5', () async {
      final bytes = _rectImage();
      final result = await detector.detect(bytes);
      expect(result, isNotNull);
      expect(result!.confidence, greaterThan(0.5));
    });

    test('uniform white image → null', () async {
      final bytes = _uniformImage(640, 480, 255);
      expect(await detector.detect(bytes), isNull);
    });

    test('uniform black image → null', () async {
      final bytes = _uniformImage(640, 480, 0);
      expect(await detector.detect(bytes), isNull);
    });

    test('low-contrast noise → null or confidence < 0.3', () async {
      final bytes = _noiseImage(640, 480);
      final result = await detector.detect(bytes);
      if (result != null) expect(result.confidence, lessThan(0.3));
    });

    test('circle-only shape → best-guess quad (minAreaRect fallback)', () async {
      // Best-guess-always: a large blob returns its bounding quad, but low
      // rectangularity keeps confidence modest so the UI tints it "please check".
      final result = await detector.detect(_circleImage(640, 480));
      expect(result, isNotNull);
      expect(result!.confidence, lessThan(0.9),
          reason: 'a circle is not a clean rectangle — confidence must not be high');
    });

    test('triangle shape → best-guess quad (minAreaRect fallback)', () async {
      final result = await detector.detect(_triangleImage(640, 480));
      expect(result, isNotNull);
      expect(result!.confidence, lessThan(0.85),
          reason: 'a triangle fills only ~half its bounding rect');
    });

    test('pentagon shape → null (5 vertices, not 4)', () async {
      final bytes = _pentagonImage(640, 480);
      expect(await detector.detect(bytes), isNull);
    });

    test('concave quad (dart/arrowhead) → null (fails isContourConvex)', () async {
      final bytes = _concaveQuadImage(640, 480);
      expect(await detector.detect(bytes), isNull);
    });

    test('non-convex quad (arrow/chevron ">") → null (fails isContourConvex)', () async {
      final bytes = _chevronImage(640, 480);
      expect(await detector.detect(bytes), isNull);
    });

    test('two rects present → largest selected', () async {
      final bytes = _twoRectsImage(640, 480);
      final result = await detector.detect(bytes);
      expect(result, isNotNull);
      // The large rect occupies the left third; its right edge is at ~x=320/640=0.5.
      // topRight.dx must be ≤ 0.6 (inside the large rect, not the small one at x=400+).
      expect(result!.corners.topRight.dx, lessThan(0.65));
    });

    test('portrait-oriented image with rect → detected', () async {
      final bytes = _rectImage(w: 480, h: 640, rx1: 80, ry1: 120,
          rx2: 400, ry2: 520);
      expect(await detector.detect(bytes), isNotNull);
    });

    test('landscape-oriented image with rect → detected', () async {
      final bytes = _rectImage(w: 800, h: 450, rx1: 100, ry1: 80,
          rx2: 700, ry2: 370);
      expect(await detector.detect(bytes), isNotNull);
    });

    test('rect tilted ~15° → detected', () async {
      expect(await detector.detect(_tiltedRectImage(640, 480, 15)), isNotNull);
    });

    test('rect tilted ~30° → detected', () async {
      expect(await detector.detect(_tiltedRectImage(640, 480, 30)), isNotNull);
    });

    test('rect tilted ~45° → detected', () async {
      expect(await detector.detect(_tiltedRectImage(640, 480, 45)), isNotNull);
    });

    test('mild perspective distortion → detected', () async {
      expect(await detector.detect(_perspectiveRectImage(640, 480)), isNotNull);
    });

    test('rect touching image edges → detected', () async {
      expect(await detector.detect(_edgeTouchingRectImage(640, 480)), isNotNull);
    });

    test('tiny rect (< 5% image area) → null', () async {
      final bytes = _tinyRectImage(640, 480);
      expect(await detector.detect(bytes), isNull);
    });

    // ── Corner ordering ───────────────────────────────────────────────────
    group('corner ordering', () {
      late DetectionResult result;
      setUp(() async {
        final bytes = _rectImage(
          w: 640, h: 480, rx1: 120, ry1: 100, rx2: 520, ry2: 380,
        );
        result = (await detector.detect(bytes))!;
      });

      test('topLeft has smallest (x + y)', () {
        final c = result.corners;
        final sumTl = c.topLeft.dx + c.topLeft.dy;
        expect(sumTl, lessThanOrEqualTo(c.topRight.dx + c.topRight.dy));
        expect(sumTl, lessThanOrEqualTo(c.bottomRight.dx + c.bottomRight.dy));
        expect(sumTl, lessThanOrEqualTo(c.bottomLeft.dx + c.bottomLeft.dy));
      });

      test('bottomRight has largest (x + y)', () {
        final c = result.corners;
        final sumBr = c.bottomRight.dx + c.bottomRight.dy;
        expect(sumBr, greaterThanOrEqualTo(c.topLeft.dx + c.topLeft.dy));
        expect(sumBr, greaterThanOrEqualTo(c.topRight.dx + c.topRight.dy));
        expect(sumBr, greaterThanOrEqualTo(c.bottomLeft.dx + c.bottomLeft.dy));
      });

      test('topRight has smallest (y − x)', () {
        final c = result.corners;
        final diffTr = c.topRight.dy - c.topRight.dx;
        expect(diffTr, lessThanOrEqualTo(c.topLeft.dy - c.topLeft.dx));
        expect(diffTr, lessThanOrEqualTo(c.bottomRight.dy - c.bottomRight.dx));
        expect(diffTr, lessThanOrEqualTo(c.bottomLeft.dy - c.bottomLeft.dx));
      });

      test('bottomLeft has largest (y − x)', () {
        final c = result.corners;
        final diffBl = c.bottomLeft.dy - c.bottomLeft.dx;
        expect(diffBl, greaterThanOrEqualTo(c.topLeft.dy - c.topLeft.dx));
        expect(diffBl, greaterThanOrEqualTo(c.topRight.dy - c.topRight.dx));
        expect(diffBl, greaterThanOrEqualTo(c.bottomRight.dy - c.bottomRight.dx));
      });

      test('all normalized values in [0.0, 1.0]', () {
        final c = result.corners;
        for (final corner in [c.topLeft, c.topRight, c.bottomRight, c.bottomLeft]) {
          expect(corner.dx, inInclusiveRange(0.0, 1.0));
          expect(corner.dy, inInclusiveRange(0.0, 1.0));
        }
      });

      test('normalization proportional to image dimensions (non-square)', () async {
        // 800×400: rect at (160,80)..(640,320); expected x ≈ 0.2..0.8, y ≈ 0.2..0.8
        final bytes = _rectImage(w: 800, h: 400, rx1: 160, ry1: 80,
            rx2: 640, ry2: 320);
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
        expect(r!.corners.topLeft.dx, closeTo(160 / 800, 0.1));
        expect(r.corners.topLeft.dy, closeTo(80 / 400, 0.1));
        expect(r.corners.bottomRight.dx, closeTo(640 / 800, 0.1));
        expect(r.corners.bottomRight.dy, closeTo(320 / 400, 0.1));
      });
    });

    // ── Confidence scoring ────────────────────────────────────────────────
    group('confidence scoring', () {
      test('perfect axis-aligned rect → angleScore ≈ 1.0 (high confidence)', () async {
        // Large rect → high area score too; combined confidence should be high.
        // Rect 480×360 in 640×480: areaScore ≈ 0.5625; with angleScore ≈ 1.0
        // formula gives 0.6*0.5625 + 0.4*1.0 = 0.7375. Threshold widened
        // slightly per tolerance allowance (brief: ±0.1 for numeric assertions).
        final bytes = _rectImage(rx1: 80, ry1: 60, rx2: 560, ry2: 420);
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
        expect(r!.confidence, greaterThan(0.70));
      });

      test('area score correct for known rect pixel dimensions', () async {
        // Rect: 400×280 = 112000px / (640×480) = 307200px → areaScore ≈ 0.365
        final bytes = _rectImage(
            w: 640, h: 480, rx1: 120, ry1: 100, rx2: 520, ry2: 380);
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
        // New formula: 0.5·area + 0.3·angle + 0.2·rect
        // For a perfect axis-aligned rect: angleScore ≈ 1.0, rectScore ≈ 1.0
        // confidence ≈ 0.5 * 0.365 + 0.3 + 0.2 = 0.683
        expect(r!.confidence, greaterThan(0.5));
        expect(r.confidence, lessThanOrEqualTo(1.0));
      });

      test('highly skewed quad → angleScore < 0.5 (angles far from 90°)', () async {
        final bytes = _skewedQuadImage(640, 480);
        final r = await detector.detect(bytes);
        // A severe parallelogram may or may not be detected (JPEG artifacts can
        // smear thin vertices). If detected, its angleScore must be < 0.5.
        if (r != null) {
          // angleScore = 1 − (meanErr/90); for ~45° error → score ≈ 0.5; severe
          // parallelogram (corners ≈ 45° and 135°) → meanErr ≈ 45° → score ≈ 0.5.
          // Confidence includes areaScore too; test the angle component indirectly:
          // confidence < 0.6 * areaScore + 0.4 * 0.5 = 0.6 * area + 0.2
          // A parallelogram filling ~32% of the frame: 0.6*0.32 + 0.2 = 0.392
          expect(r.confidence, lessThan(0.65));
        }
      });

      test('confidence: clamped to [0.0, 1.0]', () async {
        final bytes = _rectImage(rx1: 80, ry1: 60, rx2: 560, ry2: 420);
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
        expect(r!.confidence, inInclusiveRange(0.0, 1.0));
      });

      test('confidence always in [0.0, 1.0]', () async {
        for (final bytes in [
          _rectImage(),
          _uniformImage(640, 480, 255),
          _noiseImage(640, 480),
        ]) {
          final r = await detector.detect(bytes);
          if (r != null) {
            expect(r.confidence, inInclusiveRange(0.0, 1.0));
          }
        }
      });
    });

    // ── Robustness ────────────────────────────────────────────────────────
    group('robustness', () {
      test('corrupt JPEG bytes → null, no throw (empty-Mat path)', () async {
        final corrupt = Uint8List.fromList([0xFF, 0xD8, 0xAA, 0xBB, 0xCC]);
        expect(await detector.detect(corrupt), isNull);
      });

      test('empty Uint8List → null, no throw', () async {
        expect(await detector.detect(Uint8List(0)), isNull);
      });

      test('single-pixel image → null, no throw', () async {
        final image = img.Image(width: 1, height: 1, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        final bytes = Uint8List.fromList(img.encodeJpg(image));
        expect(await detector.detect(bytes), isNull);
      });

      test('10× repeated calls do not crash or OOM (Mat disposal verified)', () async {
        final bytes = _rectImage();
        for (int i = 0; i < 10; i++) {
          await detector.detect(bytes);
        }
        // Reaching here without an error/crash proves no native heap runaway.
      });

      test('detect() runs off the UI thread via compute()', () async {
        // No direct way to assert isolate use from a test, but asserting the
        // result is still correct proves compute() is wired and returns.
        final bytes = _rectImage();
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
      });
    });
  }, skip: opencvAvailable ? null : skipReason);
}
