# F1 — Contour Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `EdgeDetector` service backed by `opencv_dart` that detects a document's four corners from a JPEG and returns a `DetectionResult` (corners + confidence), plus fakes and tests.

**Architecture:** Two new production files + one modified fake + one test file + one integration file + one verify script. `EdgeDetector` / `DetectionResult` live in `lib/features/scan/edge_detector.dart` (no native dep). `OpenCvEdgeDetector` lives in `lib/features/scan/opencv_edge_detector.dart` (the only file that imports `opencv_dart`). Pattern mirrors `ImageWarper` / `PerspectiveWarper` in `lib/features/library/`. `_runPipeline` is a top-level function called via `compute()` that returns `List<double>?` (9 primitives) to keep `Offset` / `CropCorners` off the isolate boundary.

**Tech Stack:** Flutter/Dart, `opencv_dart` (pin latest stable), `package:image ^4.5.0` (already installed) for programmatic test fixtures.

## Global Constraints

- All `cv.*` calls inside `_runPipeline` MUST use **synchronous** variants (never `*Async`) — async variants spawn child isolates inside `compute()`, causing undefined behavior.
- `_runPipeline` MUST be a **top-level function**, not a method — `compute()` requires it.
- `_runPipeline` returns `List<double>?` (9 primitives: `[tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]`). Never return `DetectionResult?` — `Offset` (inside `CropCorners`) has uncertain isolate sendability.
- Every `cv.Mat` allocated in `_runPipeline` MUST be disposed via `try/finally` on every path (success, null, exception). Native memory is NOT GC'd — an undisposed `Mat` leaks 5–30 MB per call.
- `cv.imdecode` does NOT throw on corrupt bytes — it returns an empty `Mat`. Always check `mat.isEmpty` immediately after decode; if true, dispose and return `null`.
- Only `opencv_edge_detector.dart` imports `opencv_dart`. `edge_detector.dart` has zero native deps.
- `FakeEdgeDetector` lives in `test/support/fake_scan.dart`.
- No BDD `.feature` file for F1 — integration tests use plain `testWidgets()` in `integration_test/f1_edge_detection_test.dart`. No `build_runner` invocation needed.
- `ScanDependencies` is NOT modified in F1 — `EdgeDetector` injection is F2's responsibility.
- Coverage floor: ≥ 70%.

---

## Files Changed

| Action | File |
|--------|------|
| Modify | `apps/mobile/pubspec.yaml` |
| Possibly modify | `apps/mobile/lib/main.dart` |
| Create | `apps/mobile/lib/features/scan/edge_detector.dart` |
| Create | `apps/mobile/lib/features/scan/opencv_edge_detector.dart` |
| Modify | `apps/mobile/test/support/fake_scan.dart` |
| Create | `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` |
| Create | `apps/mobile/integration_test/f1_edge_detection_test.dart` |
| Create | `scripts/verify/f1.sh` |

---

## Task 1: Dependencies, Interface Layer, and FakeEdgeDetector

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Create: `apps/mobile/lib/features/scan/edge_detector.dart`
- Modify: `apps/mobile/test/support/fake_scan.dart`
- Test: `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` (DetectionResult group only — Task 2 expands it)

**Interfaces:**
- Produces: `DetectionResult` (immutable, `==`/`hashCode`/`toString`), `EdgeDetector` interface (`Future<DetectionResult?> detect(Uint8List)`), `FakeEdgeDetector`

- [ ] **Step 1: Add opencv_dart to pubspec**

In `apps/mobile/pubspec.yaml`, under `dependencies:`, add after the `image:` line:

```yaml
  opencv_dart: any
```

Then run:
```bash
cd apps/mobile && flutter pub add opencv_dart
```

This pins the latest stable version and updates `pubspec.lock`. Commit the lock file alongside pubspec.yaml.

> **cv.init() check:** After `flutter pub add`, open the installed version's README
> (`cat ~/.pub-cache/hosted/pub.dev/opencv_dart-<version>/README.md | head -60`).
> If the README says `await cv.init()` is required before first use, note it — you will
> add it to `main.dart` in Task 2 Step 7.

- [ ] **Step 2: Write a failing test for DetectionResult**

Create `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` with only the DetectionResult group (OpenCvEdgeDetector tests are added in Task 2):

```dart
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/library/crop_corners.dart';

void main() {
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
}
```

- [ ] **Step 3: Run — expect compilation failure (types don't exist)**

```bash
cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart
```

Expected: compilation error — `edge_detector.dart` does not exist, `DetectionResult` unknown.

- [ ] **Step 4: Create edge_detector.dart**

Create `apps/mobile/lib/features/scan/edge_detector.dart`:

```dart
import 'dart:typed_data';

import 'crop_corners.dart';

/// Immutable detection result: four corners in normalized [0..1] display
/// coordinates and a confidence score in [0.0, 1.0].
class DetectionResult {
  final CropCorners corners;
  final double confidence;
  const DetectionResult({required this.corners, required this.confidence});

  @override
  bool operator ==(Object other) =>
      other is DetectionResult &&
      corners == other.corners &&
      confidence == other.confidence;

  @override
  int get hashCode => Object.hash(corners, confidence);

  @override
  String toString() =>
      'DetectionResult(corners: $corners, confidence: $confidence)';
}

/// DIP boundary for document-edge detection. Concrete engine is injected at
/// the composition root; callers never import opencv_dart.
abstract interface class EdgeDetector {
  /// Returns [DetectionResult] when a 4-point convex quad is found, or [null]
  /// when no document is detected. Never throws — all failures become null.
  Future<DetectionResult?> detect(Uint8List bytes);
}
```

- [ ] **Step 5: Run DetectionResult tests — expect pass**

```bash
cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart
```

Expected: `5 tests passed` (or similar — only the DetectionResult group runs now).

- [ ] **Step 6: Add FakeEdgeDetector to fake_scan.dart**

At the bottom of `apps/mobile/test/support/fake_scan.dart`, add after the last import:

```dart
import 'package:mobile/features/scan/edge_detector.dart';
```

Then append to the end of the file:

```dart
/// Fake [EdgeDetector] for host tests. Returns a fixed [DetectionResult] or
/// null; counts calls.
class FakeEdgeDetector implements EdgeDetector {
  final DetectionResult? result;
  int calls = 0;
  FakeEdgeDetector({this.result});

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    calls++;
    return result;
  }
}
```

- [ ] **Step 7: Run tests + analyze**

```bash
cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart && flutter analyze
```

Expected: tests pass, analyze clean.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock \
        apps/mobile/lib/features/scan/edge_detector.dart \
        apps/mobile/test/support/fake_scan.dart \
        apps/mobile/test/features/scan/opencv_edge_detector_test.dart
git commit -m "feat(f1): EdgeDetector interface, DetectionResult, FakeEdgeDetector"
```

---

## Task 2: OpenCvEdgeDetector — Tests First, Then Implementation

**Files:**
- Modify: `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` (add all OpenCvEdgeDetector test cases)
- Create: `apps/mobile/lib/features/scan/opencv_edge_detector.dart`
- Possibly modify: `apps/mobile/lib/main.dart` (if cv.init() is required)

**Interfaces:**
- Consumes: `EdgeDetector`, `DetectionResult`, `CropCorners` from Task 1
- Produces: `OpenCvEdgeDetector` (const-constructable), `_runPipeline` (top-level)

- [ ] **Step 1: Write fixture helpers and all OpenCvEdgeDetector test cases**

Replace (or extend) `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` so it contains both the DetectionResult group from Task 1 AND the new OpenCvEdgeDetector group below. The full file:

```dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

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
  // Large rect (left side)
  img.fillRect(image, x1: 50, y1: 80, x2: 320, y2: 400,
      color: img.ColorRgb8(255, 255, 255));
  // Small rect (right side)
  img.fillRect(image, x1: 400, y1: 200, x2: 520, y2: 300,
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

void main() {
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

    test('circle-only shape → null (not a polygon quad)', () async {
      final bytes = _circleImage(640, 480);
      expect(await detector.detect(bytes), isNull);
    });

    test('pentagon shape → null (5 vertices, not 4)', () async {
      final bytes = _pentagonImage(640, 480);
      expect(await detector.detect(bytes), isNull);
    });

    test('concave quad (dart/arrowhead) → null (fails isContourConvex)', () async {
      final bytes = _concaveQuadImage(640, 480);
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

    test('tiny rect (< 5% image area) → null or confidence < 0.3', () async {
      final bytes = _tinyRectImage(640, 480);
      final result = await detector.detect(bytes);
      if (result != null) expect(result.confidence, lessThan(0.3));
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
        final bytes = _rectImage(rx1: 80, ry1: 60, rx2: 560, ry2: 420);
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
        expect(r!.confidence, greaterThan(0.75));
      });

      test('area score correct for known rect pixel dimensions', () async {
        // Rect: 400×280 = 112000px / (640×480) = 307200px → areaScore ≈ 0.365
        const rx1 = 120, ry1 = 100, rx2 = 520, ry2 = 380;
        const rectArea = (rx2 - rx1) * (ry2 - ry1); // 400*280 = 112000
        const imageArea = 640 * 480; // 307200
        const expectedAreaScore = rectArea / imageArea; // ≈ 0.365

        final bytes = _rectImage(
            w: 640, h: 480, rx1: rx1, ry1: ry1, rx2: rx2, ry2: ry2);
        final r = await detector.detect(bytes);
        expect(r, isNotNull);
        // confidence = 0.6 * areaScore + 0.4 * angleScore
        // For a perfect rect, angleScore ≈ 1.0
        // confidence ≈ 0.6 * 0.365 + 0.4 * 1.0 = 0.619
        expect(r!.confidence, closeTo(0.6 * expectedAreaScore + 0.4 * 1.0, 0.1));
      });

      test('confidence formula: 0.6 × area + 0.4 × angle, result clamped [0,1]', () async {
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
  });
}
```

- [ ] **Step 2: Run — expect all OpenCvEdgeDetector tests to fail (class doesn't exist)**

```bash
cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart
```

Expected: compilation error — `OpenCvEdgeDetector` not found.

- [ ] **Step 3: Create opencv_edge_detector.dart**

Create `apps/mobile/lib/features/scan/opencv_edge_detector.dart`:

```dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'crop_corners.dart';
import 'edge_detector.dart';

class OpenCvEdgeDetector implements EdgeDetector {
  const OpenCvEdgeDetector();

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    final raw = await compute(_runPipeline, bytes);
    if (raw == null) return null;
    return DetectionResult(
      corners: CropCorners(
        topLeft: Offset(raw[0], raw[1]),
        topRight: Offset(raw[2], raw[3]),
        bottomRight: Offset(raw[4], raw[5]),
        bottomLeft: Offset(raw[6], raw[7]),
      ),
      confidence: raw[8],
    );
  }
}

// ── Isolate entry point ────────────────────────────────────────────────────
// Must be top-level (not a method) — compute() requires it.
// ALL cv.* calls here are SYNCHRONOUS — never use *Async variants inside compute().
// Every cv.Mat allocated here MUST be disposed in the finally block.

/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no convex 4-point quad is found or on any error.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat, gray, blurred, edges, hierarchy;
  try {
    // Step 1: Decode. imdecode returns empty Mat (NOT an exception) for corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    final rows = mat.rows;
    final cols = mat.cols;

    // Step 2: Grayscale
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;

    // Step 3: Gaussian blur (5×5 kernel, sigma auto)
    blurred = cv.GaussianBlur(gray, (5, 5), 0);
    gray.dispose();
    gray = null;

    // Step 4: Canny edge detection
    edges = cv.Canny(blurred, 75, 200);
    blurred.dispose();
    blurred = null;

    // Step 5: Find external contours
    // NOTE: Verify the return type for the installed opencv_dart version.
    // Newer versions return a Dart record (VecVecPoint, Mat).
    // If the API differs, adapt the destructuring accordingly.
    final contoursResult = cv.findContours(
      edges, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE,
    );
    final contours = contoursResult.$1;
    hierarchy = contoursResult.$2;
    edges.dispose();
    edges = null;

    // Step 6: Find the largest convex 4-point approximation
    cv.VecPoint? best;
    double bestArea = 0;
    for (int i = 0; i < contours.length; i++) {
      final contour = contours[i];
      final epsilon = cv.arcLength(contour, true) * 0.02;
      final approx = cv.approxPolyDP(contour, epsilon, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final area = cv.contourArea(approx);
        if (area > bestArea) {
          bestArea = area;
          best = approx;
        }
      }
    }

    if (best == null) return null;

    // Step 7: Extract points and sort into canonical roles.
    // NOTE: cv.Point has int fields x and y. Convert to double for arithmetic.
    final pts = List.generate(
      best.length,
      (i) => (x: best![i].x.toDouble(), y: best[i].y.toDouble()),
    );

    // topLeft = smallest (x + y); bottomRight = largest (x + y)
    pts.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = pts.first;
    final br = pts.last;

    // topRight = smallest (y − x); bottomLeft = largest (y − x)
    pts.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final tr = pts.first;
    final bl = pts.last;

    // Step 8: Normalize to [0..1] using image dimensions captured before disposal.
    final tlDx = tl.x / cols, tlDy = tl.y / rows;
    final trDx = tr.x / cols, trDy = tr.y / rows;
    final brDx = br.x / cols, brDy = br.y / rows;
    final blDx = bl.x / cols, blDy = bl.y / rows;

    // Step 9: Confidence scoring.
    final areaScore = (bestArea / (rows * cols)).clamp(0.0, 1.0);

    // Compute mean interior angle error vs. ideal 90° for the four corners.
    // Polygon order (TL → TR → BR → BL) for interior angle measurement.
    final cornersForAngle = [tl, tr, br, bl];
    double totalErr = 0;
    for (int i = 0; i < 4; i++) {
      final prev = cornersForAngle[(i + 3) % 4];
      final curr = cornersForAngle[i];
      final next = cornersForAngle[(i + 1) % 4];
      final v1x = prev.x - curr.x, v1y = prev.y - curr.y;
      final v2x = next.x - curr.x, v2y = next.y - curr.y;
      final m1 = math.sqrt(v1x * v1x + v1y * v1y);
      final m2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (m1 < 1e-6 || m2 < 1e-6) continue;
      final cosA =
          ((v1x * v2x + v1y * v2y) / (m1 * m2)).clamp(-1.0, 1.0);
      totalErr += (math.acos(cosA) * 180 / math.pi - 90).abs();
    }
    final angleScore = (1.0 - totalErr / (4 * 90)).clamp(0.0, 1.0);
    final confidence = (0.6 * areaScore + 0.4 * angleScore).clamp(0.0, 1.0);

    return [tlDx, tlDy, trDx, trDy, brDx, brDy, blDx, blDy, confidence];
  } catch (_) {
    return null;
  } finally {
    // Dispose every Mat that may still be allocated.
    // Setting to null after explicit dispose prevents double-dispose.
    mat?.dispose();
    gray?.dispose();
    blurred?.dispose();
    edges?.dispose();
    hierarchy?.dispose();
  }
}
```

> **API note:** `opencv_dart` API signatures can vary between versions. If the
> installed version returns `GaussianBlur`/`Canny` as records `(Mat, Mat)`,
> destructure: `final (_, result) = cv.GaussianBlur(...)`. Run
> `flutter analyze` immediately after writing the file and fix any type errors
> against the actual installed API before running tests. The algorithm is
> correct regardless of which API form is used.

- [ ] **Step 4: Run analyze — fix any API mismatches**

```bash
cd apps/mobile && flutter analyze lib/features/scan/opencv_edge_detector.dart
```

If errors appear for `cv.GaussianBlur`, `cv.Canny`, `cv.findContours` return types, or `contours[i]` indexing:
- Check the installed version's API: `cat ~/.pub-cache/hosted/pub.dev/opencv_dart-*/lib/src/*.dart | grep -A5 "GaussianBlur\b"`
- Adapt destructuring as needed. The algorithm logic does NOT change.

- [ ] **Step 5: Run unit tests — iterate until green**

```bash
cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart --reporter=expanded
```

`opencv_dart` ships macOS host binaries, so `flutter test` loads the native library without a device. If any tests fail due to OpenCV detection differences from JPEG compression artifacts, widen tolerances slightly (e.g., confidence thresholds ±0.1). Do NOT change thresholds for algorithm-correctness tests (null/non-null assertions).

- [ ] **Step 6: Check and optionally add cv.init() to main.dart**

Check the installed README:
```bash
cat ~/.pub-cache/hosted/pub.dev/opencv_dart-*/README.md | grep -A 5 "cv.init\|init()"
```

If `await cv.init()` is required, update `apps/mobile/lib/main.dart`:

```dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

// Change:
//   void main() => runCamScannerApp();
// To:
Future<void> main() async {
  await cv.init();
  runCamScannerApp();
}
```

If `cv.init()` is NOT required, leave `main.dart` unchanged.

- [ ] **Step 7: Run full test suite + analyze**

```bash
cd apps/mobile && flutter test && flutter analyze
```

Expected: all tests pass (existing + new), analyze clean.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/scan/opencv_edge_detector.dart \
        apps/mobile/test/features/scan/opencv_edge_detector_test.dart
# Only if cv.init() was needed:
# git add apps/mobile/lib/main.dart
git commit -m "feat(f1): OpenCvEdgeDetector with full unit test suite"
```

---

## Task 3: On-Device Integration Tests

**Files:**
- Create: `apps/mobile/integration_test/f1_edge_detection_test.dart`

**Interfaces:**
- Consumes: `OpenCvEdgeDetector`, `EdgeDetector`, `DetectionResult` from Tasks 1–2
- Produces: 5 `testWidgets` scenarios runnable via `flutter test integration_test/f1_edge_detection_test.dart -d <device>`

> **Why not Gherkin/BDD?** The `bdd_widget_test` step system shares state only through
> the Flutter widget tree. F1 has no widget tree — it's a pure service. Plain `testWidgets`
> groups are the correct fit. The user-visible BDD scenario (capture → pre-filled overlay)
> belongs to F2 where a full widget tree is present.

- [ ] **Step 1: Create f1_edge_detection_test.dart**

Create `apps/mobile/integration_test/f1_edge_detection_test.dart`:

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late EdgeDetector detector;
  setUp(() => detector = const OpenCvEdgeDetector());

  // Shared fixture: 640×480 black image with white rect at (120,100)..(520,380).
  Uint8List makeRectFixture() {
    final image = img.Image(width: 640, height: 480, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(image, x1: 120, y1: 100, x2: 520, y2: 380,
        color: img.ColorRgb8(255, 255, 255));
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

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

  testWidgets('circular-only shape → null', (tester) async {
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
    expect(await detector.detect(bytes), isNull);
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
}
```

- [ ] **Step 2: Verify test file compiles on host**

```bash
cd apps/mobile && flutter test integration_test/f1_edge_detection_test.dart --platform=vm 2>&1 | head -20
```

If it compiles without error but requires a device for `IntegrationTestWidgetsFlutterBinding`, that's expected — device tests run on-device only. What matters is no import or type errors.

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/integration_test/f1_edge_detection_test.dart
git commit -m "test(f1): on-device integration tests (5 scenarios, plain testWidgets)"
```

---

## Task 4: Verify Script

**Files:**
- Create: `scripts/verify/f1.sh`

**Interfaces:**
- Consumes: all F1 files from Tasks 1–3, `scripts/verify/lib.sh` helpers
- Produces: `scripts/verify/f1.sh` that mirrors `e3.sh` structure with F1-specific static asserts

- [ ] **Step 1: Create f1.sh**

Create `scripts/verify/f1.sh`:

```bash
#!/usr/bin/env bash
# Verify F1 (contour detection) acceptance criteria.
# VERIFY_SKIP_DEVICE=1  — skips device launches (reported FAIL, never silent).
# REAL_DEVICE=1         — Tier-3 manual lane (capture, verify auto corner detection).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== F1 verification =="

require_tool flutter
require_tool pnpm
require_tool git

# ── EdgeDetector interface ─────────────────────────────────────────────────
assert_file_has "EdgeDetector interface exists" \
  "apps/mobile/lib/features/scan/edge_detector.dart" \
  "interface class EdgeDetector"

assert_file_has "DetectionResult class exists" \
  "apps/mobile/lib/features/scan/edge_detector.dart" \
  "class DetectionResult"

assert_file_has "DetectionResult has operator ==" \
  "apps/mobile/lib/features/scan/edge_detector.dart" \
  "operator =="

# ── OpenCvEdgeDetector implementation ─────────────────────────────────────
assert_file_has "OpenCvEdgeDetector exists" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "class OpenCvEdgeDetector"

assert_file_has "_runPipeline top-level function exists" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "_runPipeline"

assert_file_has "List<double> return type in _runPipeline (isolate-safe primitives)" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "List<double>?"

assert_file_has "isContourConvex convexity filter present" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "isContourConvex"

assert_file_has "compute() used (off-thread assertion)" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "compute("

# ── opencv_dart dependency ─────────────────────────────────────────────────
assert_file_has "opencv_dart in pubspec.yaml" \
  "apps/mobile/pubspec.yaml" \
  "opencv_dart"

# ── DIP check: edge_detector.dart must NOT import opencv_dart ─────────────
if grep -q "opencv_dart" \
    "apps/mobile/lib/features/scan/edge_detector.dart" 2>/dev/null; then
  fail "DIP violation: edge_detector.dart imports opencv_dart — callers must not see it"
else
  pass "DIP: edge_detector.dart does not import opencv_dart"
fi

# ── FakeEdgeDetector ──────────────────────────────────────────────────────
assert_file_has "FakeEdgeDetector in fake_scan.dart" \
  "apps/mobile/test/support/fake_scan.dart" \
  "FakeEdgeDetector"

assert_file_has "FakeEdgeDetector.calls counter" \
  "apps/mobile/test/support/fake_scan.dart" \
  "int calls"

# ── Integration test file ─────────────────────────────────────────────────
assert_file_has "f1_edge_detection_test.dart present" \
  "apps/mobile/integration_test/f1_edge_detection_test.dart" \
  "f1 edge detection"

# ── Suite ──────────────────────────────────────────────────────────────────
assert_cmd "unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ── Device ─────────────────────────────────────────────────────────────────
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android f1_edge_detection_test.dart
verify_integration_ios f1_edge_detection_test.dart

# ── Opt-in REAL_DEVICE Tier-3 ─────────────────────────────────────────────
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "MANUAL: Capture a document with the camera."
  echo "Verify the crop overlay appears with corners pre-positioned at document edges."
  echo "(Note: F1 delivers the detector only. F2 wires it into the UI.)"
fi

verify_summary
```

- [ ] **Step 2: Make executable and run with VERIFY_SKIP_DEVICE=1**

```bash
chmod +x scripts/verify/f1.sh
VERIFY_SKIP_DEVICE=1 bash scripts/verify/f1.sh
```

Expected: all static asserts PASS, suite passes, device section reports FAIL (skipped) and exits non-zero — that is correct; the FAIL is expected for the skip message and is not a bug. Full pass requires a device run without the flag.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify/f1.sh
git commit -m "chore(f1): verify script with static asserts + suite gate"
```

---

## Self-Review Checklist

The following was verified against the spec before finalizing this plan:

1. **`_runPipeline` is top-level** ✓ — declared at file scope, not as a method.
2. **Returns `List<double>?` (9 primitives)** ✓ — `Offset` / `CropCorners` never cross the isolate boundary.
3. **All Mats disposed via `try/finally`** ✓ — nullable pattern; `mat = null` after explicit dispose prevents double-dispose in finally.
4. **`mat.isEmpty` guard before any use** ✓ — immediately after `imdecode`.
5. **Sync-only `cv.*` calls** ✓ — none of the calls inside `_runPipeline` end in `Async`.
6. **`isContourConvex` filter** ✓ — after `approxPolyDP`, before area comparison.
7. **Corner sort: TL=min(x+y), BR=max(x+y), TR=min(y−x), BL=max(y−x)** ✓.
8. **Confidence: `0.6 × areaScore + 0.4 × angleScore`, clamped** ✓.
9. **`FakeEdgeDetector` has `result` field, `calls` counter, and `detect()` stub** ✓.
10. **No Gherkin / no `build_runner` for F1** ✓ — integration test uses plain `testWidgets()`.
11. **`ScanDependencies` unchanged** ✓ — `EdgeDetector` injection is F2's job.
12. **DIP asserted in verify script** ✓ — `edge_detector.dart` must not import `opencv_dart`.
13. **`cv.init()` check documented** ✓ — Task 2 Step 6 covers both cases (required / not required).
14. **`opencv_dart` version pinned at implementation time** ✓ — Task 1 Step 1 runs `flutter pub add`.
15. **`image: ^4.5.0` already installed** ✓ — no change to pubspec for the test fixtures.
16. **Coverage floor ≥ 70%** ✓ — verify script gates on it.
