# Segmentation-Based Dot Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat-field + Canny crop-corner detector (which erases the page boundary on real captures) with dual-polarity Otsu region segmentation, so the auto "dots" land on the real document.

**Architecture:** Inside the existing OpenCV `compute()` isolate, blur → Otsu-threshold into a bright mask and its inverse (dark mask) → for each polarity, morphological-close the interior text into a solid page blob, take the largest contour, fit a quad (`approxPolyDP` else `minAreaRect`), guard against blank/clutter blobs, and keep the highest-confidence survivor. Flat-field is removed from detection (it stays in the Auto filter). Scoring/geometry reuse `detector_geometry.dart`.

**Tech Stack:** Flutter/Dart, `dartcv4` (OpenCV, imported as `package:opencv_dart/opencv_dart.dart as cv`), `image` package (fixtures), `flutter_test`, `integration_test`, Python `cv2` (host reference probe).

## Global Constraints

- `_runPipeline` runs in a `compute()` isolate and MUST NEVER throw — keep `try { … } catch (_) { return null; } finally { … }`.
- EVERY native resource (`cv.Mat`, `cv.Vec*`, `cv.RotatedRect`, `cv.VecPoint2f`) disposed exactly once — explicit-then-null, or in a `finally`. Per-polarity handles are disposed in an inner `finally`; loop-local `approx`/`rect`/`box` are disposed in both branches (they are out of scope for any `finally`).
- Only synchronous `cv.*` calls in the isolate — never `*Async`.
- Corners returned normalized `[0..1]` as `[tlDx,tlDy,trDx,trDy,brDx,brDy,blDx,blDy,confidence]`.
- `detect()`, `PipelineRunner`, `_computeRunner`, `_kDetectMaxSide` (1024), and the 5 s timeout contract are UNCHANGED.
- Confidence comes from `detectionConfidence` (0.5·area + 0.3·angle + 0.2·rect) — never reimplemented inline. Corner roles come from `sortCornerRoles`.
- `detector_geometry.dart` stays pure Dart (no `opencv_dart`/`dartcv4` import).
- Flat-field normalization is REMOVED from the detector; do not touch `auto_enhancer.dart`.
- Segmentation constants (exact): blur kernel `_kSegBlur = 7`; close-kernel divisor `_kSegKernelDivisor = 30`; guard `minAreaFrac = 0.05`, `maxAreaFrac = 0.92`, `minFill = 0.55`; contour area gate `imageArea * 0.05`.
- All Dart test/build commands run from `apps/mobile/`.

---

## File Structure

- `apps/mobile/lib/features/scan/detector_geometry.dart` **(modify)** — add pure-Dart `isPlausiblePage` guard. Keeps existing helpers.
- `apps/mobile/lib/features/scan/opencv_edge_detector.dart` **(modify)** — replace `_runPipeline` with the segmentation pipeline; drop the flat-field constants/steps.
- `apps/mobile/test/features/scan/detector_geometry_test.dart` **(modify)** — `isPlausiblePage` truth table.
- `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` **(modify)** — segmentation-consistent expectations.
- `apps/mobile/tool/detect_probe.py` **(create)** — committed Python `cv2` reference: generates synthetic fixtures in-code and asserts the segmentation result. Fast host validation of the algorithm + constants (libdartcv can't run on host).
- `apps/mobile/integration_test/f4_segmentation_test.dart` **(create)** — on-device dual-polarity + negative fixtures.
- `apps/mobile/integration_test/f3_shadow_detection_test.dart` **(modify)** — align the one shadowed-page assertion with segmentation (page stays brighter than desk → bright polarity).

---

## Task 1: `isPlausiblePage` guard helper

**Files:**
- Modify: `apps/mobile/lib/features/scan/detector_geometry.dart` (append after `detectionConfidence`)
- Test: `apps/mobile/test/features/scan/detector_geometry_test.dart` (append a group)

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Task 2): `bool isPlausiblePage({required double areaFrac, required double fill, double minAreaFrac = 0.05, double maxAreaFrac = 0.92, double minFill = 0.55})`.

- [ ] **Step 1: Write the failing test** — append this group inside `main()` in `apps/mobile/test/features/scan/detector_geometry_test.dart`:

```dart
  group('isPlausiblePage', () {
    test('accepts a mid-frame, well-filled quad', () {
      expect(isPlausiblePage(areaFrac: 0.40, fill: 0.85), isTrue);
      expect(isPlausiblePage(areaFrac: 0.84, fill: 0.78), isTrue);
    });
    test('rejects a near-full-frame blob (blank scene / background)', () {
      expect(isPlausiblePage(areaFrac: 0.97, fill: 0.99), isFalse);
    });
    test('rejects a too-small blob', () {
      expect(isPlausiblePage(areaFrac: 0.03, fill: 0.99), isFalse);
    });
    test('rejects a low-fill blob (clutter / non-rectangular)', () {
      expect(isPlausiblePage(areaFrac: 0.40, fill: 0.50), isFalse);
    });
    test('honors the boundary values (>= and <=)', () {
      expect(isPlausiblePage(areaFrac: 0.05, fill: 0.55), isTrue);
      expect(isPlausiblePage(areaFrac: 0.92, fill: 0.55), isTrue);
      expect(isPlausiblePage(areaFrac: 0.049, fill: 0.99), isFalse);
      expect(isPlausiblePage(areaFrac: 0.40, fill: 0.549), isFalse);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart`
Expected: FAIL — "The method 'isPlausiblePage' isn't defined".

- [ ] **Step 3: Implement** — append to `apps/mobile/lib/features/scan/detector_geometry.dart`:

```dart

/// Accept predicate for a candidate page quad. Rejects the near-full-frame
/// blob of a blank scene (or the background polarity), a too-small blob, and a
/// low-fill (non-rectangular) clutter blob. A legitimate page can fill most of
/// the frame and touch all borders, so border-touching is deliberately NOT a
/// criterion — the area cap and fill floor already exclude the background/blank
/// blobs.
bool isPlausiblePage({
  required double areaFrac,
  required double fill,
  double minAreaFrac = 0.05,
  double maxAreaFrac = 0.92,
  double minFill = 0.55,
}) =>
    areaFrac >= minAreaFrac && areaFrac <= maxAreaFrac && fill >= minFill;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Analyze**

Run: `cd apps/mobile && flutter analyze lib/features/scan/detector_geometry.dart test/features/scan/detector_geometry_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/detector_geometry.dart apps/mobile/test/features/scan/detector_geometry_test.dart
git commit -m "feat(detect): isPlausiblePage guard (area bounds + fill floor)"
```

---

## Task 2: Segmentation `_runPipeline`

**Files:**
- Modify: `apps/mobile/lib/features/scan/opencv_edge_detector.dart` (replace `_runPipeline` and the constants block; add `import`s if needed)
- Modify: `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` (segmentation expectations)

**Interfaces:**
- Consumes (Task 1 + existing): `isPlausiblePage`, `sortCornerRoles`, `quadArea`, `angleScore`, `rectangularityScore`, `detectionConfidence` from `detector_geometry.dart`.
- Produces: unchanged public surface — `_runPipeline(Uint8List) → List<double>?`.

**Reference:** this Dart faithfully mirrors the validated cv2 prototype (Task 3 commits that prototype). Do not deviate from the algorithm.

- [ ] **Step 1: Update the OpenCV unit-test expectations (device-only group, skipped on host)**

`opencv_edge_detector_test.dart`'s `OpenCvEdgeDetector` group is skipped on host (no libdartcv) but must describe segmentation behavior for device runs. Make these changes:

- **Uniform / low-contrast noise / corrupt / empty** → still `null` (unchanged: uniform's all-white mask fills the frame → area>0.92 guard → null; noise → contours <5% → null).
- **White rect on black** (`_rectImage`) → still non-null; keep `confidence` assertions but relax any exact value to `greaterThan(0.6)` and `lessThanOrEqualTo(1.0)` (a clean rect scores high on all three terms).
- **Circle** (`_circleImage`) → non-null best-guess (blob fill ≈ π/4 ≈ 0.79 ≥ 0.55): keep `isNotNull` + `confidence` `lessThan(0.9)`.
- **Pentagon** (`_pentagonImage`) → non-null (regular-pentagon fill ≈ 0.69 ≥ 0.55): keep `isNotNull` + `confidence` `lessThan(0.9)`.
- **Triangle** (`_triangleImage`) → now `null` (fill ≈ 0.5 < 0.55 guard). Replace its body with:

```dart
    test('triangle shape → null (fill below the page guard)', () async {
      // A triangle fills only ~half its bounding rect (fill ≈ 0.5), below the
      // 0.55 page-plausibility floor, so segmentation rejects it.
      final result = await detector.detect(_triangleImage(640, 480));
      expect(result, isNull);
    });
```

- **Concave dart** (`_concaveQuadImage`) and **chevron** (`_chevronImage`) → now `null` (low fill). Replace each `expect(result, isNotNull)` (and any confidence line) with `expect(await detector.detect(<fixture>(640,480)), isNull)` and update the test names to `'… → null (fill below the page guard)'`.
- **Corner-ordering** and **normalization-range** tests on `_rectImage` → unchanged (a rect still yields an ordered, in-range quad).
- **tilted / perspective / edge-touching rect** tests → unchanged (`isNotNull`; a bright rect on dark still segments).

Run: `cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_test.dart`
Expected: the `OpenCvEdgeDetector` group reports **skipped** on host; the `DetectionResult` group passes; **no compile errors**.

- [ ] **Step 2: Replace the constants block**

In `apps/mobile/lib/features/scan/opencv_edge_detector.dart`, DELETE the flat-field constants `_kIllumProxySide` and `_kIllumSigma`. Keep `_kDetectMaxSide`. Immediately after `_kDetectMaxSide`'s declaration, add:

```dart
/// Gaussian blur kernel side (odd) applied before Otsu, to suppress text and
/// texture so the whole page reads as one region.
const int _kSegBlur = 7;

/// The morphological-close kernel side is `round(cols / _kSegKernelDivisor)`
/// (odd-ized). Large enough to bridge interior text into a solid page blob,
/// proportional to the working-image width.
const int _kSegKernelDivisor = 30;
```

- [ ] **Step 3: Replace `_runPipeline`**

Replace the entire `_runPipeline` function (from `List<double>? _runPipeline(Uint8List bytes) {` through its closing `}`) with:

```dart
/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no plausible page quad is found or on any error.
///
/// Dual-polarity Otsu region segmentation: threshold the blurred grayscale into
/// a bright mask (page brighter than background) and its inverse (page darker),
/// close interior text into a solid blob, take the largest contour, fit a quad,
/// guard against blank/clutter blobs, and keep the highest-confidence survivor.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat, gray, blurred, maskBright, maskDark;
  try {
    // Step 1: Decode. imdecode returns an empty Mat for corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    // Step 2: Downscale large captures (coordinate-safe: corners normalized).
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
    final imageArea = (rows * cols).toDouble();

    // Step 3: Grayscale.
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;

    // Step 4: Blur so text/texture doesn't fragment the page region.
    blurred = cv.gaussianBlur(gray, (_kSegBlur, _kSegBlur), 0);
    gray.dispose();
    gray = null;

    // Step 5: Otsu → bright mask (page-brighter) + the inverse dark mask
    // (page-darker), so both polarities are considered.
    final (otsuT, mb) =
        cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    maskBright = mb;
    final (_, md) = cv.threshold(blurred, otsuT, 255, cv.THRESH_BINARY_INV);
    maskDark = md;
    blurred.dispose();
    blurred = null;

    // Close-kernel side proportional to width, odd.
    var kseg = math.max(3, (cols / _kSegKernelDivisor).round());
    if (kseg.isEven) kseg += 1;

    List<Pt>? bestQuad;
    double bestConfidence = -1;

    // Step 6: For each polarity, close → largest contour → quad → guard → score.
    // Iterate the non-null locals `mb`/`md` (maskBright/maskDark hold the same
    // handles for disposal in `finally`).
    for (final mask in [mb, md]) {
      cv.Mat? kernel, closed;
      cv.VecVec4i? hierarchy;
      cv.VecVecPoint? contours;
      try {
        kernel = cv.getStructuringElement(cv.MORPH_RECT, (kseg, kseg));
        closed = cv.morphologyEx(mask, cv.MORPH_CLOSE, kernel, iterations: 1);

        final contoursResult = cv.findContours(
          closed,
          cv.RETR_EXTERNAL,
          cv.CHAIN_APPROX_SIMPLE,
        );
        contours = contoursResult.$1;
        hierarchy = contoursResult.$2;

        // Largest contour with area ≥ 5% of the image.
        int bestIdx = -1;
        double bestContourArea = 0;
        for (int i = 0; i < contours.length; i++) {
          final a = cv.contourArea(contours[i]);
          if (a >= imageArea * 0.05 && a > bestContourArea) {
            bestContourArea = a;
            bestIdx = i;
          }
        }
        if (bestIdx < 0) continue;
        final contour = contours[bestIdx]; // owned by contours — do not dispose

        // Build a quad: approxPolyDP if 4-pt convex (perspective fit), else
        // the min-area rotated rectangle.
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
        final areaFrac = qArea / imageArea;
        final fill = rectangularityScore(bestContourArea, qArea);
        if (!isPlausiblePage(areaFrac: areaFrac, fill: fill)) continue;

        final conf = detectionConfidence(
          areaScore: areaFrac.clamp(0.0, 1.0),
          angleScore: angleScore(roles),
          rectScore: fill,
        );
        if (conf > bestConfidence) {
          bestConfidence = conf;
          bestQuad = roles;
        }
      } finally {
        kernel?.dispose();
        closed?.dispose();
        hierarchy?.dispose();
        contours?.dispose();
      }
    }

    if (bestQuad == null) return null;

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
    mat?.dispose();
    gray?.dispose();
    blurred?.dispose();
    maskBright?.dispose();
    maskDark?.dispose();
  }
}
```

- [ ] **Step 4: Analyze**

Run: `cd apps/mobile && flutter analyze lib/features/scan/opencv_edge_detector.dart`
Expected: "No issues found!" (If any `cv.*` symbol is undefined — `cv.THRESH_BINARY_INV`, `cv.morphologyEx`, `cv.getStructuringElement`, `cv.minAreaRect`, `rect.points`, `rect.size` — resolve against `~/.pub-cache/hosted/pub.dev/dartcv4-1.1.8/lib/src/`; do not guess. `THRESH_BINARY_INV` is a top-level `const int`.)

- [ ] **Step 5: Run the scan host suite**

Run: `cd apps/mobile && flutter test test/features/scan/`
Expected: PASS — `detector_geometry_test.dart` green; the `OpenCvEdgeDetector` group **skipped**; all other scan tests green; no compile errors.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/opencv_edge_detector.dart apps/mobile/test/features/scan/opencv_edge_detector_test.dart
git commit -m "feat(detect): dual-polarity Otsu segmentation pipeline (replaces flat-field/Canny)"
```

---

## Task 3: Committed cv2 reference probe

**Files:**
- Create: `apps/mobile/tool/detect_probe.py`

**Interfaces:**
- Consumes: nothing (standalone Python).
- Produces: a runnable host validation of the segmentation algorithm + constants (`python3 apps/mobile/tool/detect_probe.py`, exit 0 on success).

**Why:** libdartcv can't load under host `flutter test`, so this cv2 mirror is the only fast host check of the actual CV behavior. It generates synthetic fixtures in code (no binary/personal images committed) and asserts the same behavior the on-device `f4` test verifies. Keep the constants identical to Task 2 (`_kSegBlur=7`, `cols/30` kernel, guards 0.05/0.92/0.55).

- [ ] **Step 1: Create the probe**

Create `apps/mobile/tool/detect_probe.py`:

```python
#!/usr/bin/env python3
"""Host reference for the dual-polarity Otsu segmentation dot detector.

Mirrors _runPipeline in lib/features/scan/opencv_edge_detector.dart. libdartcv
can't run under host `flutter test`, so this cv2 replica is the fast host check
of the algorithm + constants. Run: `python3 apps/mobile/tool/detect_probe.py`.
Requires: pip install --break-system-packages opencv-python-headless numpy
"""
import sys
import cv2
import numpy as np

DETECT_MAX_SIDE = 1024
SEG_BLUR = 7
SEG_KERNEL_DIVISOR = 30
MIN_AREA_FRAC, MAX_AREA_FRAC, MIN_FILL = 0.05, 0.92, 0.55


def _quad_area(q):
    x, y = q[:, 0], q[:, 1]
    return abs(sum(x[i] * y[(i + 1) % 4] - x[(i + 1) % 4] * y[i]
                   for i in range(4))) / 2


def detect(img):
    """Return (confidence, areaFrac, fill, polarity) or None."""
    h0, w0 = img.shape[:2]
    longest = max(h0, w0)
    if longest > DETECT_MAX_SIDE:
        s = DETECT_MAX_SIDE / longest
        img = cv2.resize(img, (round(w0 * s), round(h0 * s)),
                         interpolation=cv2.INTER_AREA)
    rows, cols = img.shape[:2]
    area = rows * cols
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (SEG_BLUR, SEG_BLUR), 0)
    ot, mb = cv2.threshold(blurred, 0, 255,
                           cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    _, md = cv2.threshold(blurred, ot, 255, cv2.THRESH_BINARY_INV)
    kseg = max(3, round(cols / SEG_KERNEL_DIVISOR))
    if kseg % 2 == 0:
        kseg += 1
    ker = cv2.getStructuringElement(cv2.MORPH_RECT, (kseg, kseg))
    best = None
    for name, mask in (("bright", mb), ("dark", md)):
        closed = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, ker)
        cnts, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL,
                                   cv2.CHAIN_APPROX_SIMPLE)
        cnts = [c for c in cnts if cv2.contourArea(c) >= area * 0.05]
        if not cnts:
            continue
        c = max(cnts, key=cv2.contourArea)
        carea = cv2.contourArea(c)
        peri = cv2.arcLength(c, True)
        ap = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(ap) == 4 and cv2.isContourConvex(ap):
            quad = ap.reshape(-1, 2).astype(float)
        else:
            quad = cv2.boxPoints(cv2.minAreaRect(c)).astype(float)
        qarea = _quad_area(quad)
        if qarea <= 0:
            continue
        area_frac = qarea / area
        fill = min(carea / qarea, 1.0)
        if not (MIN_AREA_FRAC <= area_frac <= MAX_AREA_FRAC and fill >= MIN_FILL):
            continue
        conf = 0.5 * min(area_frac, 1.0) + 0.3 * 1.0 + 0.2 * fill
        if best is None or conf > best[0]:
            best = (conf, area_frac, fill, name)
    return best


def _page_on(bg, page):
    img = np.full((600, 800, 3), bg, np.uint8)
    cv2.rectangle(img, (150, 110), (650, 490), (page, page, page), -1)
    return img


def _shape(kind):
    """White shape on black — mirrors the opencv_edge_detector_test fixtures."""
    import math
    img = np.zeros((480, 640, 3), np.uint8)
    if kind == "circle":
        cv2.circle(img, (320, 240), 160, (255, 255, 255), -1)
    elif kind == "triangle":
        cv2.fillPoly(img, [np.array([[320, 80], [120, 400], [520, 400]])],
                     (255, 255, 255))
    elif kind == "pentagon":
        c, r = (320, 240), 170
        p = np.array([[c[0] + r * math.cos(2 * math.pi * i / 5 - math.pi / 2),
                       c[1] + r * math.sin(2 * math.pi * i / 5 - math.pi / 2)]
                      for i in range(5)], np.int32)
        cv2.fillPoly(img, [p], (255, 255, 255))
    elif kind == "concave":
        cv2.fillPoly(img, [np.array([[320, 100], [500, 400], [320, 300],
                                     [140, 400]], np.int32)], (255, 255, 255))
    return img


def _cases():
    blank = np.full((600, 800, 3), 200, np.uint8)
    noise = np.random.RandomState(1).randint(100, 130, (600, 800, 3), np.uint8)
    clutter = np.full((600, 800, 3), 50, np.uint8)
    rs = np.random.RandomState(2)
    for _ in range(40):
        x, y = rs.randint(0, 700), rs.randint(0, 500)
        cv2.rectangle(clutter, (x, y),
                      (x + rs.randint(10, 60), y + rs.randint(10, 60)),
                      (int(rs.randint(0, 255)),) * 3, -1)
    # page brighter than desk, with a soft horizontal shadow across the page
    shadow = np.full((600, 800, 3), 55, np.uint8)
    for x in range(150, 651):
        v = int(235 - 85 * (x - 150) / 500)
        cv2.line(shadow, (x, 110), (x, 490), (v, v, v), 1)
    return [
        ("blank", blank, None),
        ("noise", noise, None),
        ("clutter", clutter, None),
        ("page-on-dark", _page_on(55, 225), "bright"),
        ("page-on-light", _page_on(235, 180), "dark"),
        ("soft-shadow-on-dark", shadow, "bright"),
        # Shape fixtures mirror opencv_edge_detector_test: a shape whose fill is
        # below 0.55 is rejected (triangle, concave dart); circle/pentagon pass.
        ("shape-circle", _shape("circle"), "bright"),
        ("shape-pentagon", _shape("pentagon"), "bright"),
        ("shape-triangle", _shape("triangle"), None),
        ("shape-concave", _shape("concave"), None),
    ]


def main():
    failures = 0
    for name, img, expect_polarity in _cases():
        r = detect(img)
        if expect_polarity is None:
            ok = r is None
            got = "NULL" if r is None else f"quad({r[3]} conf={r[0]:.2f})"
        else:
            ok = r is not None and r[3] == expect_polarity and 0.30 <= r[0] <= 1.0
            got = "NULL" if r is None else f"{r[3]} conf={r[0]:.2f} area={r[1]*100:.0f}% fill={r[2]:.2f}"
        print(f"[{'PASS' if ok else 'FAIL'}] {name:22s} expect={expect_polarity or 'NULL'} got={got}")
        if not ok:
            failures += 1
    print(f"\n{failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the probe**

Run: `python3 apps/mobile/tool/detect_probe.py`
Expected: every line `[PASS]`, final `0 failure(s)`, exit 0. (If cv2 is missing: `python3 -m pip install --break-system-packages --quiet opencv-python-headless numpy`.)

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/tool/detect_probe.py
git commit -m "test(detect): committed cv2 host reference probe for segmentation"
```

---

## Task 4: On-device verification + f3 reconcile

**Files:**
- Create: `apps/mobile/integration_test/f4_segmentation_test.dart`
- Modify: `apps/mobile/integration_test/f3_shadow_detection_test.dart`

**Interfaces:**
- Consumes: `OpenCvEdgeDetector` (real native pipeline), `image` package.
- Produces: on-device assertions that segmentation localizes both polarities and rejects negatives.

**Context:** libdartcv only loads on device, so this is the authoritative gate for Task 2's Dart. Mirrors the pattern in `f1_edge_detection_test.dart`.

- [ ] **Step 1: Create the on-device test**

Create `apps/mobile/integration_test/f4_segmentation_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

/// A `page` rectangle (uniform gray `page`) on a `desk` background.
Uint8List _pageOn({required int desk, required int page}) {
  final image = img.Image(width: 800, height: 600, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(desk, desk, desk));
  img.fillRect(image, x1: 150, y1: 110, x2: 650, y2: 490,
      color: img.ColorRgb8(page, page, page));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Uniform image — no page.
Uint8List _uniform(int v) {
  final image = img.Image(width: 800, height: 600, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(v, v, v));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('f4: segmentation detection (on-device, real libdartcv)', () {
    const detector = OpenCvEdgeDetector();
    // Expected page bounds normalized: x [150/800,650/800]=[0.188,0.813],
    // y [110/600,490/600]=[0.183,0.817]. Tolerance covers blur + close drift.
    const tol = 0.08;

    void expectHugsPage(dynamic result, String reason) {
      expect(result, isNotNull, reason: reason);
      final c = result!.corners;
      expect(c.topLeft.dx, closeTo(0.188, tol));
      expect(c.topLeft.dy, closeTo(0.183, tol));
      expect(c.bottomRight.dx, closeTo(0.813, tol));
      expect(c.bottomRight.dy, closeTo(0.817, tol));
    }

    test('page brighter than desk → bright-polarity quad', () async {
      expectHugsPage(await detector.detect(_pageOn(desk: 55, page: 225)),
          'bright page on a dark desk must segment');
    });

    test('page darker than desk → dark-polarity quad', () async {
      expectHugsPage(await detector.detect(_pageOn(desk: 235, page: 150)),
          'darker page on a light desk must segment via the inverse mask');
    });

    test('uniform frame → null (no page)', () async {
      expect(await detector.detect(_uniform(200)), isNull);
    });
  });
}
```

- [ ] **Step 2: Reconcile `f3_shadow_detection_test.dart`**

`f3`'s shadowed-page fixture (page 235→150 on desk 60) stays valid under segmentation (page brighter than desk → bright polarity). Only its inline comments reference "flat-field normalization". Update the two `reason:` strings that say "flat-field" to "segmentation":

Replace `reason: 'flat-field normalization must recover the dimmed edge'` with `reason: 'segmentation must recover the shadowed page (page stays brighter than desk)'`, and replace `reason: 'the shadow-dimmed right edge must still be found'` with `reason: 'the shadowed (dimmer) right side must still fall inside the page blob'`. Leave the fixtures and assertions unchanged.

- [ ] **Step 3: Analyze both integration files**

Run: `cd apps/mobile && flutter analyze integration_test/f4_segmentation_test.dart integration_test/f3_shadow_detection_test.dart`
Expected: "No issues found!"

- [ ] **Step 4: Run f4 + f3 + f1 on-device**

Run: `cd apps/mobile && flutter test integration_test/f4_segmentation_test.dart integration_test/f3_shadow_detection_test.dart integration_test/f1_edge_detection_test.dart -d RZCY51D0T1K`
Expected: all PASS. (If a page test misses on the far corner, the segmentation constants `_kSegKernelDivisor` / `minFill` need tuning — iterate against `tool/detect_probe.py` first, then re-run. `f1`'s shape expectations may also shift under segmentation: triangle/concave/chevron → null, circle/pentagon → non-null — align them the same way as the `opencv_edge_detector_test.dart` shapes if `f1` asserts them.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/integration_test/f4_segmentation_test.dart apps/mobile/integration_test/f3_shadow_detection_test.dart
git commit -m "test(detect): on-device f4 segmentation (dual-polarity + negative); f3 wording"
```

- [ ] **Step 6: Manual real-capture eyeball (controller/user)**

Run `detect()` on the user's actual gallery captures and confirm the quad hugs the page:
- Pull a capture: `adb -s RZCY51D0T1K shell ls -t /sdcard/DCIM/Camera/` then `adb -s RZCY51D0T1K pull /sdcard/DCIM/Camera/<newest>.jpg`.
- Bundle it as a temporary asset (add to `pubspec.yaml` `assets:`, NOT committed — personal photo), run a throwaway integration test that `detect()`s it, draws the quad with `img.drawLine`, writes the annotated JPEG, and pull it for a visual check.
- Remove the temporary asset + fixture + scratch test afterward (`git checkout -- pubspec.yaml`).

Record the outcome (pass/fail + annotated screenshot) in the task report. This manual eyeball on a real capture is required — synthetic on-device tests are necessary but not sufficient (they gave false confidence before).

- [ ] **Step 7: Live-preview smoothness check (controller/user)**

`detect()` runs off the UI thread in a `compute()` isolate on an 800 ms timer with an `_isSampling` guard (`camera_screen.dart:79-89`), so a slower pipeline degrades gracefully to a less-frequent live quad rather than janking the preview. Still confirm on-device: build/install a debug or release build, point the camera at a document, and verify (a) the live green quad appears over the page and (b) the preview stays smooth (no visible stutter) as the pipeline runs both polarities. If the preview noticeably stutters on the budget phone, note it — a mitigation (e.g. a lighter single-polarity fast-path on the live loop only) can be added, but do NOT add it speculatively (YAGNI). Record the observation in the report.

---

## Notes for the executor

- **Privacy:** do NOT commit the user's real photos. Committed fixtures are synthetic (Tasks 3 & 4). Real captures are local-only for the Task 4 Step 6 eyeball.
- **Constants live in two places on purpose** (Dart `_runPipeline` and `tool/detect_probe.py`) — keep them identical. If you tune one, tune both.
- The `f1`/`opencv_edge_detector_test.dart` shape expectations shift under segmentation (triangle/concave/chevron → null via the fill floor; circle/pentagon → non-null). Update wherever asserted.
