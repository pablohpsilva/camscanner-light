# Shadow-Tolerant Dot Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the automatic crop-corner ("dots") detection find the real document boundary on captures with soft shadows, always returning a scored best-guess instead of falling back to the full frame.

**Architecture:** Inside the existing OpenCV `compute()` isolate, normalize illumination (flat-field: divide the grayscale by a blurred background estimate) before edge detection so shadow-dimmed edges regain contrast; bridge broken Canny edges with a morphological close; relax quad extraction (`approxPolyDP` → else `minAreaRect`) so near-misses still yield a quad; score every candidate and return the best. All scoring/geometry math lives in a pure-Dart file so it is host-testable without `libdartcv`.

**Tech Stack:** Flutter/Dart, `dartcv4` (OpenCV bindings, imported as `package:opencv_dart/opencv_dart.dart as cv`), `image` package (test fixtures), `flutter_test`, `integration_test`.

## Global Constraints

- The detection pipeline `_runPipeline` runs in a `compute()` isolate and **must never throw** — wrap the body in `try { … } catch (_) { return null; } finally { … }`.
- **Every** native resource (`cv.Mat`, `cv.Vec*`, `cv.RotatedRect`, `cv.VecPoint2f`) allocated in the isolate **must be disposed** — either explicitly (then set the variable to `null`) or in the `finally` block. Never double-dispose.
- Inside the isolate, use **only synchronous** `cv.*` calls — never the `*Async` variants.
- Corners are returned **normalized to `[0..1]`** in `[tlDx, tlDy, trDx, trDy, brDx, brDy, blDx, blDy, confidence]` order.
- The `detect()` timeout contract (return `null` on `TimeoutException`, default 5 s) is unchanged.
- `detector_geometry.dart` is **pure Dart** — it must NOT import `opencv_dart` / `dartcv4`. This is what makes it host-testable (`libdartcv` never loads under host `flutter test`).
- Downscale working size stays `_kDetectMaxSide = 1024` (longest side).
- Confidence weighting is exactly `0.5·areaScore + 0.3·angleScore + 0.2·rectScore`.
- All test/build commands run from `apps/mobile/`.

---

## File Structure

- `apps/mobile/lib/features/scan/detector_geometry.dart` **(new)** — pure-Dart point type + corner-role sort + area/angle/rectangularity/confidence scoring. No OpenCV. Host-tested.
- `apps/mobile/lib/features/scan/opencv_edge_detector.dart` **(modify)** — rewrite `_runPipeline` to the new pipeline; call the geometry helpers.
- `apps/mobile/lib/features/scan/capture_review_screen.dart` **(modify)** — three-tier highlight color (green / amber / blue).
- `apps/mobile/test/features/scan/detector_geometry_test.dart` **(new)** — host tests for the geometry helpers.
- `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` **(modify)** — update expectations for the new confidence formula and the always-best-guess behavior.
- `apps/mobile/test/features/scan/capture_review_highlight_test.dart` **(new)** — widget tests for the amber tint tier.
- `apps/mobile/integration_test/f3_shadow_detection_test.dart` **(new)** — on-device: run the real pipeline on a synthetic shadowed-rectangle image and assert the detected quad lands on the rectangle.

---

## Task 1: Pure-Dart geometry & scoring helpers

**Files:**
- Create: `apps/mobile/lib/features/scan/detector_geometry.dart`
- Test: `apps/mobile/test/features/scan/detector_geometry_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart, `dart:math` only).
- Produces (used by Task 2):
  - `typedef Pt = ({double x, double y});`
  - `List<Pt> sortCornerRoles(List<Pt> pts)` → returns `[topLeft, topRight, bottomRight, bottomLeft]`.
  - `double quadArea(List<Pt> quad)` → shoelace polygon area (absolute).
  - `double angleScore(List<Pt> quadTLTRBRBL)` → `[0,1]`, 1.0 for right angles.
  - `double rectangularityScore(double contourArea, double quadArea)` → `[0,1]`.
  - `double detectionConfidence({required double areaScore, required double angleScore, required double rectScore})` → `[0,1]`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/scan/detector_geometry_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/detector_geometry.dart';

void main() {
  group('sortCornerRoles', () {
    test('assigns TL/TR/BR/BL for a shuffled axis-aligned rectangle', () {
      // Rect corners given out of order.
      final pts = <Pt>[
        (x: 100, y: 80),  // BR
        (x: 10, y: 5),    // TL
        (x: 100, y: 5),   // TR
        (x: 10, y: 80),   // BL
      ];
      final r = sortCornerRoles(pts);
      expect(r[0], (x: 10.0, y: 5.0), reason: 'TL = smallest x+y');
      expect(r[1], (x: 100.0, y: 5.0), reason: 'TR = smallest y-x');
      expect(r[2], (x: 100.0, y: 80.0), reason: 'BR = largest x+y');
      expect(r[3], (x: 10.0, y: 80.0), reason: 'BL = largest y-x');
    });

    test('assigns roles for a rotated (perspective) quad', () {
      // A trapezoid tilted right: top edge shorter, shifted.
      final pts = <Pt>[
        (x: 30, y: 10),   // TL
        (x: 90, y: 20),   // TR
        (x: 110, y: 95),  // BR
        (x: 15, y: 85),   // BL
      ];
      final r = sortCornerRoles(pts);
      expect(r[0], (x: 30.0, y: 10.0));
      expect(r[1], (x: 90.0, y: 20.0));
      expect(r[2], (x: 110.0, y: 95.0));
      expect(r[3], (x: 15.0, y: 85.0));
    });
  });

  group('quadArea', () {
    test('computes rectangle area', () {
      final rect = <Pt>[
        (x: 0, y: 0), (x: 100, y: 0), (x: 100, y: 50), (x: 0, y: 50),
      ];
      expect(quadArea(rect), closeTo(5000, 1e-6));
    });
  });

  group('angleScore', () {
    test('1.0 for a perfect rectangle', () {
      final rect = <Pt>[
        (x: 0, y: 0), (x: 100, y: 0), (x: 100, y: 50), (x: 0, y: 50),
      ];
      expect(angleScore(rect), closeTo(1.0, 1e-9));
    });

    test('lower for a skewed quad', () {
      final skew = <Pt>[
        (x: 0, y: 0), (x: 100, y: 0), (x: 130, y: 50), (x: 0, y: 50),
      ];
      expect(angleScore(skew), lessThan(0.95));
      expect(angleScore(skew), greaterThan(0.0));
    });
  });

  group('rectangularityScore', () {
    test('1.0 when contour fills its quad', () {
      expect(rectangularityScore(5000, 5000), closeTo(1.0, 1e-9));
    });
    test('0.5 for a triangle inside its bounding rect', () {
      expect(rectangularityScore(2500, 5000), closeTo(0.5, 1e-9));
    });
    test('clamps to [0,1] and guards zero quad area', () {
      expect(rectangularityScore(9999, 0), 0.0);
      expect(rectangularityScore(6000, 5000), 1.0);
    });
  });

  group('detectionConfidence', () {
    test('applies the 0.5/0.3/0.2 weighting', () {
      final c = detectionConfidence(areaScore: 1.0, angleScore: 1.0, rectScore: 1.0);
      expect(c, closeTo(1.0, 1e-9));
      final c2 = detectionConfidence(areaScore: 0.4, angleScore: 1.0, rectScore: 0.5);
      expect(c2, closeTo(0.5 * 0.4 + 0.3 * 1.0 + 0.2 * 0.5, 1e-9));
    });
    test('clamps to [0,1]', () {
      expect(detectionConfidence(areaScore: 2.0, angleScore: 2.0, rectScore: 2.0), 1.0);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'mobile' … detector_geometry.dart` / "Undefined name 'Pt'" (the source file does not exist yet).

- [ ] **Step 3: Write the implementation**

Create `apps/mobile/lib/features/scan/detector_geometry.dart`:

```dart
import 'dart:math' as math;

/// A 2-D point in pixel space. Pure-Dart mirror of an OpenCV contour point so
/// the geometry/scoring math is testable without libdartcv (which never loads
/// under host `flutter test`).
typedef Pt = ({double x, double y});

/// Sorts four quad points into canonical corner roles.
/// Returns `[topLeft, topRight, bottomRight, bottomLeft]`.
///  - topLeft     = smallest (x + y)
///  - bottomRight = largest  (x + y)
///  - topRight    = smallest (y - x)
///  - bottomLeft  = largest  (y - x)
List<Pt> sortCornerRoles(List<Pt> pts) {
  assert(pts.length == 4, 'sortCornerRoles expects exactly 4 points');
  final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
  final tl = bySum.first;
  final br = bySum.last;
  final byDiff = [...pts]..sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
  final tr = byDiff.first;
  final bl = byDiff.last;
  return [tl, tr, br, bl];
}

/// Polygon area via the shoelace formula (absolute value).
double quadArea(List<Pt> quad) {
  double s = 0;
  for (int i = 0; i < quad.length; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % quad.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

/// Score in `[0,1]`: how close the four interior angles are to 90°.
/// 1.0 = perfect rectangle; decreases as corners skew.
/// [quad] must be in TL, TR, BR, BL order.
double angleScore(List<Pt> quad) {
  double totalErr = 0;
  for (int i = 0; i < 4; i++) {
    final prev = quad[(i + 3) % 4];
    final curr = quad[i];
    final next = quad[(i + 1) % 4];
    final v1x = prev.x - curr.x, v1y = prev.y - curr.y;
    final v2x = next.x - curr.x, v2y = next.y - curr.y;
    final m1 = math.sqrt(v1x * v1x + v1y * v1y);
    final m2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (m1 < 1e-6 || m2 < 1e-6) continue;
    final cosA = ((v1x * v2x + v1y * v2y) / (m1 * m2)).clamp(-1.0, 1.0);
    totalErr += (math.acos(cosA) * 180 / math.pi - 90).abs();
  }
  return (1.0 - totalErr / (4 * 90)).clamp(0.0, 1.0);
}

/// Score in `[0,1]`: fill ratio of the source contour vs. its enclosing quad.
/// ~1.0 when the contour is itself quadrilateral; low when the quad was
/// synthesized (e.g. `minAreaRect`) around a ragged/non-rectangular blob.
double rectangularityScore(double contourArea, double quadArea) {
  if (quadArea <= 0) return 0.0;
  return (contourArea / quadArea).clamp(0.0, 1.0);
}

/// Weighted detection confidence in `[0,1]`.
double detectionConfidence({
  required double areaScore,
  required double angleScore,
  required double rectScore,
}) =>
    (0.5 * areaScore + 0.3 * angleScore + 0.2 * rectScore).clamp(0.0, 1.0);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart`
Expected: PASS (all groups green).

- [ ] **Step 5: Run the analyzer**

Run: `cd apps/mobile && flutter analyze lib/features/scan/detector_geometry.dart test/features/scan/detector_geometry_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/detector_geometry.dart apps/mobile/test/features/scan/detector_geometry_test.dart
git commit -m "feat(detect): pure-Dart corner-role + scoring helpers for edge detection"
```

---

## Task 2: New illumination-normalized detection pipeline

**Files:**
- Modify: `apps/mobile/lib/features/scan/opencv_edge_detector.dart` (rewrite `_runPipeline`, lines 61-229; add constants near line 70)
- Modify: `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` (update expectations)

**Interfaces:**
- Consumes (from Task 1): `Pt`, `sortCornerRoles`, `quadArea`, `angleScore`, `rectangularityScore`, `detectionConfidence` from `detector_geometry.dart`.
- Produces: unchanged public surface — `_runPipeline(Uint8List) → List<double>?` returning `[tlDx,tlDy,trDx,trDy,brDx,brDy,blDx,blDy,confidence]` or `null`; `OpenCvEdgeDetector.detect()` unchanged.

**Context:** `_runPipeline` is the top-level isolate entry at `opencv_edge_detector.dart:74`. The current body decodes, downscales, grayscales, blurs, runs fixed `Canny(75,200)`, finds external contours, keeps only exactly-4-point convex quads ≥5% area, picks the largest, sorts corners inline, and scores `0.6·area + 0.4·angle`. Replace that body. Keep `detect()`, the `PipelineRunner` typedef, `_computeRunner`, and `_kDetectMaxSide` as they are.

- [ ] **Step 1: Update the confidence-scoring test expectations (failing test)**

The existing OpenCV suite (`opencv_edge_detector_test.dart`) is skipped on host (`skip: opencvAvailable ? null : skipReason`) because `libdartcv` is device-only, but its expectations must still describe the new behavior for on-device runs. Make these edits:

In the **'confidence scoring'** group, any assertion that hard-codes the old `0.6·area + 0.4·angle` value must be relaxed to the new formula's range. Replace exact-value confidence assertions with bounded ones. For the clean full-frame white rectangle fixture, change any `expect(result.confidence, closeTo(<oldvalue>, …))` to:

```dart
// New formula: 0.5·area + 0.3·angle + 0.2·rect. A near-full white rect on
// black scores high on all three.
expect(result!.confidence, greaterThan(0.7));
expect(result.confidence, lessThanOrEqualTo(1.0));
```

In the **'robustness'** group, update the circle/triangle expectations: the pipeline now **always returns a best-guess quad** (via the `minAreaRect` fallback) for any contour ≥5% area, so a large circle or triangle no longer yields `null`. Replace `expect(result, isNull)` for the circle/triangle fixtures with:

```dart
// Best-guess-always: a large blob returns its bounding quad, but low
// rectangularity keeps confidence modest so the UI tints it "please check".
final result = await detector.detect(_circleImage(640, 480));
expect(result, isNotNull);
expect(result!.confidence, lessThan(0.9),
    reason: 'a circle is not a clean rectangle — confidence must not be high');
```

```dart
final result = await detector.detect(_triangleImage(640, 480));
expect(result, isNotNull);
expect(result!.confidence, lessThan(0.85),
    reason: 'a triangle fills only ~half its bounding rect');
```

Keep the assertions that a **uniform** image and a **low-contrast noise** image (no contour ≥5%) still return `null` — those are unchanged. Keep the corrupt-bytes → `null` assertion unchanged.

Run: `cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart`
Expected: The OpenCV groups report as **skipped** on host (`native OpenCV (libdartcv) unavailable on host`); the `DetectionResult` group (which does not need native code) passes. No compile errors. (These behavioral expectations are verified on-device in Task 4 and manual testing.)

- [ ] **Step 2: Add the new constants**

In `apps/mobile/lib/features/scan/opencv_edge_detector.dart`, directly after the existing `_kDetectMaxSide` const (around line 70), add:

```dart
/// Longest side (px) of the proxy used to estimate background illumination.
/// A small proxy makes the heavy blur cheap enough for the live sampling loop.
const int _kIllumProxySide = 256;

/// Gaussian sigma (in proxy pixels) for the illumination estimate. Large
/// relative to the proxy so only the low-frequency light field survives.
const double _kIllumSigma = 12.0;
```

- [ ] **Step 3: Add the import**

At the top of `apps/mobile/lib/features/scan/opencv_edge_detector.dart`, alongside the existing imports, add:

```dart
import 'detector_geometry.dart';
```

- [ ] **Step 4: Rewrite `_runPipeline`**

Replace the entire `_runPipeline` function body (from `List<double>? _runPipeline(Uint8List bytes) {` through its closing `}`) with:

```dart
/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no candidate quad is found or on any error.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat, gray, proxy, bgSmall, bg, normalized, blurred, otsuOut,
      edges, kernel, closed;
  cv.VecVec4i? hierarchy;
  cv.VecVecPoint? contours;
  try {
    // Step 1: Decode. imdecode returns an empty Mat (not an exception) for
    // corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    // Step 2: Downscale large captures so fine texture doesn't spawn spurious
    // edges. Corners are normalized below, so this does not shift the result.
    final longest = math.max(mat.rows, mat.cols);
    if (longest > _kDetectMaxSide) {
      final scale = _kDetectMaxSide / longest;
      final resized = cv.resize(
        mat,
        ((mat.cols * scale).round(), (mat.rows * scale).round()),
        interpolation: cv.INTER_AREA,
      );
      mat.dispose();
      mat = resized;
    }
    final rows = mat.rows;
    final cols = mat.cols;

    // Step 3: Grayscale.
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;

    // Step 4: Illumination normalization (flat-field). Estimate the local
    // background light on a small proxy (downscale → heavy blur → upscale),
    // then divide it out. This flattens a soft-shadow gradient so a
    // shadow-dimmed paper edge regains local contrast.
    final proxyLongest = math.max(rows, cols);
    final pScale =
        proxyLongest > _kIllumProxySide ? _kIllumProxySide / proxyLongest : 1.0;
    final pw = math.max(1, (cols * pScale).round());
    final ph = math.max(1, (rows * pScale).round());
    proxy = cv.resize(gray, (pw, ph), interpolation: cv.INTER_AREA);
    bgSmall = cv.gaussianBlur(proxy, (0, 0), _kIllumSigma);
    proxy.dispose();
    proxy = null;
    bg = cv.resize(bgSmall, (cols, rows), interpolation: cv.INTER_LINEAR);
    bgSmall.dispose();
    bgSmall = null;
    // normalized = saturate(gray * 255 / bg), CV_8U. divide() maps a
    // divide-by-zero to 0, so no guard is needed.
    normalized = cv.divide(gray, bg, scale: 255.0);
    gray.dispose();
    gray = null;
    bg.dispose();
    bg = null;

    // Step 5: Gaussian blur (5×5) on the normalized image.
    blurred = cv.gaussianBlur(normalized, (5, 5), 0);
    normalized.dispose();
    normalized = null;

    // Step 6: Adaptive Canny thresholds from Otsu's value on the blurred Mat.
    final (otsuT, oOut) =
        cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    otsuOut = oOut;
    otsuOut.dispose();
    otsuOut = null;
    final hi = otsuT.clamp(40.0, 220.0);
    final lo = 0.5 * hi;
    edges = cv.canny(blurred, lo, hi);
    blurred.dispose();
    blurred = null;

    // Step 7: Morphological close to bridge short gaps into loops.
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel, iterations: 1);
    edges.dispose();
    edges = null;
    kernel.dispose();
    kernel = null;

    // Step 8: Find external contours.
    final contoursResult = cv.findContours(
      closed,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    contours = contoursResult.$1;
    hierarchy = contoursResult.$2;
    closed.dispose();
    closed = null;
    hierarchy.dispose();
    hierarchy = null;

    // Step 9: Relaxed quad extraction + scored selection. For every contour
    // ≥5% of the image, build a 4-corner quad (approxPolyDP if it yields a
    // convex quad, else the min-area rotated rectangle), score it, and keep
    // the best. Always returns a best-guess when any sizeable contour exists.
    final imageArea = (rows * cols).toDouble();
    final minQuadArea = imageArea * 0.05;
    List<Pt>? bestQuad;
    double bestConfidence = -1;
    for (int i = 0; i < contours.length; i++) {
      // contours[i] returns a reference owned by contours — do NOT dispose it.
      final contour = contours[i];
      final cArea = cv.contourArea(contour);
      if (cArea < minQuadArea) continue;

      List<Pt> quadPts;
      final epsilon = cv.arcLength(contour, true) * 0.02;
      final approx = cv.approxPolyDP(contour, epsilon, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        quadPts = List.generate(
          4,
          (j) => (x: approx[j].x.toDouble(), y: approx[j].y.toDouble()),
        );
        approx.dispose();
      } else {
        approx.dispose();
        final rect = cv.minAreaRect(contour);
        final box = rect.points; // VecPoint2f, 4 corners
        quadPts = List.generate(4, (j) => (x: box[j].x, y: box[j].y));
        box.dispose();
        rect.dispose();
      }

      final roles = sortCornerRoles(quadPts); // [TL, TR, BR, BL]
      final qArea = quadArea(roles);
      if (qArea <= 0) continue;
      final areaScore = (qArea / imageArea).clamp(0.0, 1.0);
      final aScore = angleScore(roles);
      final rScore = rectangularityScore(cArea, qArea);
      final conf = detectionConfidence(
        areaScore: areaScore,
        angleScore: aScore,
        rectScore: rScore,
      );
      if (conf > bestConfidence) {
        bestConfidence = conf;
        bestQuad = roles;
      }
    }

    contours.dispose();
    contours = null;

    if (bestQuad == null) return null;

    // Step 10: Normalize to [0..1] and emit.
    final tl = bestQuad[0], tr = bestQuad[1], br = bestQuad[2], bl = bestQuad[3];
    return [
      tl.x / cols, tl.y / rows,
      tr.x / cols, tr.y / rows,
      br.x / cols, br.y / rows,
      bl.x / cols, bl.y / rows,
      bestConfidence,
    ];
  } catch (_) {
    return null;
  } finally {
    // Dispose every native resource that may still be allocated.
    mat?.dispose();
    gray?.dispose();
    proxy?.dispose();
    bgSmall?.dispose();
    bg?.dispose();
    normalized?.dispose();
    blurred?.dispose();
    otsuOut?.dispose();
    edges?.dispose();
    kernel?.dispose();
    closed?.dispose();
    hierarchy?.dispose();
    contours?.dispose();
  }
}
```

- [ ] **Step 5: Run the analyzer**

Run: `cd apps/mobile && flutter analyze lib/features/scan/opencv_edge_detector.dart`
Expected: "No issues found!" (If the analyzer reports `rect.points` or `cv.divide`/`cv.morphologyEx`/`cv.threshold`/`cv.minAreaRect`/`cv.getStructuringElement` as undefined, the symbol is exported under a different name — resolve against `dartcv4` 1.1.8 in `~/.pub-cache/hosted/pub.dev/dartcv4-1.1.8/lib/src/`; do not guess.)

- [ ] **Step 6: Run the host test suite for the scan feature**

Run: `cd apps/mobile && flutter test test/features/scan/`
Expected: PASS — `detector_geometry_test.dart` green; `opencv_edge_detector_test.dart` OpenCV groups **skipped** on host with the `DetectionResult` group green; all other scan tests green. No compile errors.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/scan/opencv_edge_detector.dart apps/mobile/test/features/scan/opencv_edge_detector_test.dart
git commit -m "feat(detect): flat-field + morph-close + relaxed-quad shadow-tolerant pipeline"
```

---

## Task 3: Amber "please check" tint tier

**Files:**
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart:70-71` (the `_highlightColor` getter)
- Test: `apps/mobile/test/features/scan/capture_review_highlight_test.dart` (new)

**Interfaces:**
- Consumes: nothing new. Uses the existing `_detectionConfidence` field and the `CropOverlay`'s `highlightColor` param.
- Produces: three-tier color mapping — `>=0.6 → green`, `>=0.3 → amber`, else `blue`.

**Context:** `_CaptureReviewScreenState` (`capture_review_screen.dart:62`) holds `double? _detectionConfidence` and passes `_highlightColor` into `CropOverlay(highlightColor: …)` at line 140. The current getter is two-tier (green ≥0.5 else blue). Widening it to a third amber tier makes low-confidence best-guesses read as "verify me."

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/scan/capture_review_highlight_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

/// A detector that returns a fixed confidence so we can drive the tint tiers.
class _FakeDetector implements EdgeDetector {
  final double confidence;
  const _FakeDetector(this.confidence);
  @override
  Future<DetectionResult?> detect(Uint8List bytes) async => DetectionResult(
        corners: CropCorners.fullFrame,
        confidence: confidence,
      );
}

Future<Color> _highlightFor(WidgetTester tester, double confidence) async {
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/h.jpg'),
      onRetake: () {},
      onAccept: (_, __) {},
      decodeImageSize: (_) async => const Size(100, 100),
      readBytes: (_) async => Uint8List.fromList(List.filled(64, 1)),
      edgeDetector: _FakeDetector(confidence),
    ),
  ));
  await tester.pumpAndSettle();
  final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
  return overlay.highlightColor;
}

void main() {
  testWidgets('confidence >= 0.6 tints green', (tester) async {
    expect(await _highlightFor(tester, 0.8), Colors.green);
  });

  testWidgets('0.3 <= confidence < 0.6 tints amber (please check)',
      (tester) async {
    expect(await _highlightFor(tester, 0.45), Colors.amber);
  });

  testWidgets('confidence < 0.3 tints blue (fallback)', (tester) async {
    expect(await _highlightFor(tester, 0.1), Colors.blue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_highlight_test.dart`
Expected: FAIL — the amber case returns `Colors.green` (0.45 ≥ 0.5 under the old two-tier getter), so `expect(..., Colors.amber)` fails.

- [ ] **Step 3: Update `_highlightColor`**

In `apps/mobile/lib/features/scan/capture_review_screen.dart`, replace the getter at lines 70-71:

```dart
  Color get _highlightColor =>
      (_detectionConfidence ?? -1) >= 0.5 ? Colors.green : Colors.blue;
```

with:

```dart
  // Three tiers: confident (green), best-guess-please-check (amber), and
  // fallback/full-frame (blue). Low-confidence detections still snap the dots
  // to a best guess, so amber tells the user to verify rather than trust.
  Color get _highlightColor {
    final c = _detectionConfidence ?? -1;
    if (c >= 0.6) return Colors.green;
    if (c >= 0.3) return Colors.amber;
    return Colors.blue;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_highlight_test.dart`
Expected: PASS (green / amber / blue all correct).

- [ ] **Step 5: Run the full capture-review test group (regression)**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_g4_test.dart test/features/scan/capture_review_highlight_test.dart`
Expected: PASS — no existing review-screen test regressed.

- [ ] **Step 6: Run the analyzer**

Run: `cd apps/mobile && flutter analyze lib/features/scan/capture_review_screen.dart test/features/scan/capture_review_highlight_test.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/scan/capture_review_screen.dart apps/mobile/test/features/scan/capture_review_highlight_test.dart
git commit -m "feat(review): amber 'please check' tint for low-confidence best-guess dots"
```

---

## Task 4: On-device shadow-detection verification harness

**Files:**
- Create: `apps/mobile/integration_test/f3_shadow_detection_test.dart`

**Interfaces:**
- Consumes: `OpenCvEdgeDetector` (real native pipeline), `image` package for fixture synthesis.
- Produces: an on-device integration test asserting the pipeline localizes a shadowed rectangle.

**Context:** `libdartcv` only loads on a device/emulator, so this is the real gate for Task 2's pipeline. Rather than commit a personal photo, synthesize a deterministic "paper on desk under a soft shadow" fixture: a mid-gray page rectangle on a dark surface, with a horizontal brightness gradient across the page (bright on one side, dimmed on the other) simulating a shadow. The pipeline must still localize the rectangle's four corners. This mirrors the existing on-device pattern in `integration_test/f1_edge_detection_test.dart`.

- [ ] **Step 1: Write the integration test**

Create `apps/mobile/integration_test/f3_shadow_detection_test.dart`:

```dart
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
```

- [ ] **Step 2: Verify a device/emulator is connected**

Run: `flutter devices`
Expected: at least one Android device listed (e.g. `RZCY51D0T1K`). If none, start an emulator or connect the device — this test cannot run on the host (`libdartcv` won't load).

- [ ] **Step 3: Run the integration test on-device**

Run: `cd apps/mobile && flutter test integration_test/f3_shadow_detection_test.dart -d RZCY51D0T1K`
(Substitute the actual device id from Step 2.)
Expected: PASS — both tests green. If the shadowed-page test fails on the right-edge corner, the flat-field parameters (`_kIllumSigma`, `_kIllumProxySide`) or the Canny floor (`hi.clamp(40, …)`) need tuning; iterate on Task 2's constants and re-run (this is the systematic-debugging loop, grounded in real native output).

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/integration_test/f3_shadow_detection_test.dart
git commit -m "test(detect): on-device shadow-tolerant detection harness (f3)"
```

- [ ] **Step 5: Manual on-device eyeball (real capture)**

Build and install the app, capture a real piece of paper on a desk with a hand/phone shadow across it, and open the review screen.

```bash
cd apps/mobile && flutter build apk --release
adb -s RZCY51D0T1K install -r build/app/outputs/flutter-apk/app-release.apk
adb -s RZCY51D0T1K shell monkey -p com.camscannerlight.mobile -c android.intent.category.LAUNCHER 1
```

Verify by observation (drive taps via `uiautomator dump` for exact bounds, then `adb exec-out screencap -p > shot.png` — do NOT eyeball tap coordinates):
- After capture, the crop dots hug the paper's edges (not the full frame), tinted green or amber.
- The shadow-dimmed edge is still tracked.
- Confirm the live 800 ms preview loop stays smooth (no visible stutter from the added normalization). If it stutters badly, note it — only then consider a `fast` path that skips normalization on the live loop (do not add speculatively).

Record the outcome (pass/fail + a screenshot) in the task report. This manual eyeball is a required part of the task, not optional.

---

## Notes for the executor

- **Deviation from the spec's verification section:** the spec described bundling a real shadowed capture and drawing the detected quad for an adb-pulled eyeball. This plan instead uses a *synthetic* shadowed-rectangle fixture for the automated on-device assertion (deterministic, no committed personal photo) plus a *manual* real-capture eyeball (Task 4 Step 5). Same coverage, cleaner and privacy-safe.
- **Perf `fast` flag is intentionally not planned** (YAGNI) — add it only if Step 5 shows real live-preview stutter.
- If `flutter test test/features/scan/` reports the OpenCV groups as *failing* rather than *skipped* on host, the `opencvAvailable` probe changed; the geometry + DetectionResult groups must still pass — that's the host gate.
