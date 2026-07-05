# Tighten the Detection Box Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dual-polarity Otsu page detector return a *tighter* quad by fitting corners with `convexHull` + an ε-sweep `approxPolyDP` instead of falling back to a loose `minAreaRect`, proven by a new ground-truth tightness metric.

**Architecture:** Measure-then-fit. First add a host-side tightness metric (corner error + IoU vs a known page rectangle) to `detect_probe.py` as a red gate. Then replace the quad-construction step in the shared `_segmentGray` core (and mirror it in the probe) with a convex-hull + ascending-ε `approxPolyDP` sweep that takes the smallest ε yielding a 4-point convex quad; `minAreaRect` is retained only as a genuine last resort. A pure-Dart `isConvexQuad` helper replaces the `cv.isContourConvex` call so convexity is unit-testable host-side.

**Tech Stack:** Dart/Flutter, `opencv_dart` (`cv.*`), Python 3 + `opencv-python-headless` + numpy (host reference probe), bash verify harness (`scripts/verify/lib.sh`).

## Global Constraints

- **`libdartcv` never loads under host `flutter test`** — the cv-bound pipeline is gated by the Python host probe (`apps/mobile/tool/detect_probe.py`), which must mirror the Dart algorithm exactly. On-device is the authoritative runtime check.
- **Verify harness: SILENCE IS FAILURE** — every check is an explicit positive marker + exit-code assert (`scripts/verify/lib.sh`); missing tool/marker/empty output = FAIL.
- **Isolate resource discipline** — every `cv.Mat`/`VecPoint`/`RotatedRect` allocated inside the `compute()` isolate MUST be disposed on every path (the existing per-polarity `try/finally` pattern).
- **Shared core** — the fit change lives once in `_segmentGray`; both the still path (`detect`, `_kDetectMaxSide = 1024`) and the live guide (`detectFrame`, `_kLiveDetectMaxSide = 400`) consume it.
- **TDD / SOLID / KISS / DRY** — tests before implementation; pure helpers isolated and unit-tested; no speculative features.
- **Out of scope (deferred):** `MORPH_CLOSE` erode-back/kernel retune, corner-edge gradient snapping (Approach B), live-path tightness thresholds, auto-capture parameter tuning.
- Device this session: **iPhone (iOS 18.7.8), connected.**
- Spec: `docs/superpowers/specs/2026-07-05-tighten-detection-box-design.md`.

---

### Task 1: Pure `isConvexQuad` geometry helper

**Files:**
- Modify: `apps/mobile/lib/features/scan/detector_geometry.dart` (append helper)
- Test: `apps/mobile/test/features/scan/detector_geometry_test.dart`

**Interfaces:**
- Consumes: `Pt = ({double x, double y})` (already defined in `detector_geometry.dart`).
- Produces: `bool isConvexQuad(List<Pt> quad)` — true iff `quad` is a strictly convex quadrilateral (any winding); false for wrong length, collinear/degenerate, or reflex (non-convex) shapes. Consumed by Task 4.

- [ ] **Step 1: Write the failing tests**

Add to `apps/mobile/test/features/scan/detector_geometry_test.dart` (inside the existing top-level `main()`; import already present):

```dart
group('isConvexQuad', () {
  test('accepts an axis-aligned square (CCW and CW windings)', () {
    const ccw = <Pt>[(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10), (x: 0, y: 10)];
    const cw = <Pt>[(x: 0, y: 0), (x: 0, y: 10), (x: 10, y: 10), (x: 10, y: 0)];
    expect(isConvexQuad(ccw), isTrue);
    expect(isConvexQuad(cw), isTrue);
  });

  test('accepts a convex (non-axis-aligned) quad', () {
    const q = <Pt>[(x: 2, y: 0), (x: 12, y: 3), (x: 9, y: 11), (x: 0, y: 8)];
    expect(isConvexQuad(q), isTrue);
  });

  test('rejects a reflex (arrow/dart) quad', () {
    // Third vertex pulled inside → one reflex angle.
    const q = <Pt>[(x: 0, y: 0), (x: 10, y: 0), (x: 5, y: 3), (x: 10, y: 10)];
    expect(isConvexQuad(q), isFalse);
  });

  test('rejects three collinear vertices', () {
    const q = <Pt>[(x: 0, y: 0), (x: 5, y: 0), (x: 10, y: 0), (x: 5, y: 8)];
    expect(isConvexQuad(q), isFalse);
  });

  test('rejects a non-4-point list', () {
    const q = <Pt>[(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10)];
    expect(isConvexQuad(q), isFalse);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart -r expanded`
Expected: FAIL — "The method 'isConvexQuad' isn't defined".

- [ ] **Step 3: Implement `isConvexQuad`**

Append to `apps/mobile/lib/features/scan/detector_geometry.dart`:

```dart
/// True iff [quad] is a strictly convex quadrilateral, for either winding.
/// The signed cross product at every consecutive vertex triple must share one
/// non-zero sign; a near-zero cross means collinear/degenerate → false.
bool isConvexQuad(List<Pt> quad) {
  if (quad.length != 4) return false;
  int sign = 0;
  for (int i = 0; i < 4; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % 4];
    final c = quad[(i + 2) % 4];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (cross.abs() < 1e-9) return false; // collinear → degenerate
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart -r expanded`
Expected: PASS (all `isConvexQuad` tests green; pre-existing geometry tests still green).

- [ ] **Step 5: Analyze**

Run: `cd apps/mobile && flutter analyze lib/features/scan/detector_geometry.dart test/features/scan/detector_geometry_test.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/detector_geometry.dart apps/mobile/test/features/scan/detector_geometry_test.dart
git commit -m "feat(scan): pure isConvexQuad helper for host-testable quad-fit convexity"
```

---

### Task 2: Tightness metric + looseness fixture in the host probe (RED gate)

**Files:**
- Modify: `apps/mobile/tool/detect_probe.py`

**Interfaces:**
- Consumes: existing `detect(img, max_side)`, `_page_on(bg, page)`, `_cases()`.
- Produces: `detect()` now returns `(conf, area_frac, fill, polarity, quad)` where `quad` is the detected 4×2 corner array in working-image pixels (or `None`); helpers `_sort_roles`, `_iou`, `_corner_err`; a new `page-nub-on-dark` fixture with a known page rectangle; tightness asserts in `main()`. Consumed/updated by Task 3.

This task adds the measurement and the fixtures and leaves the tightness asserts **failing** on the current (pre-fix) fitter — that is the red gate.

- [ ] **Step 1: Return the detected quad from `detect()`**

In `apps/mobile/tool/detect_probe.py`, `detect()` currently tracks `best = (conf, area_frac, fill, name)`. Change it to also carry the quad, in working-image pixel coordinates:

- Where the quad is built (the `if len(ap) == 4 ... else boxPoints(...)` block), keep `quad` as computed.
- Change the `best` assignment from `best = (conf, area_frac, fill, name)` to `best = (conf, area_frac, fill, name, quad)`.
- The function still returns `best` (now a 5-tuple) or `None`.

- [ ] **Step 2: Add metric helpers**

Add near the top of `apps/mobile/tool/detect_probe.py` (after the imports / `_quad_area`):

```python
def _sort_roles(q):
    """[TL, TR, BR, BL] — mirrors sortCornerRoles in detector_geometry.dart."""
    q = np.asarray(q, dtype=float).reshape(-1, 2)
    s = q[:, 0] + q[:, 1]
    d = q[:, 1] - q[:, 0]
    return np.array([q[np.argmin(s)], q[np.argmin(d)],
                     q[np.argmax(s)], q[np.argmax(d)]])


def _fill_mask(poly, shape):
    m = np.zeros(shape[:2], dtype=np.uint8)
    cv2.fillPoly(m, [np.asarray(poly, dtype=np.int32).reshape(-1, 2)], 255)
    return m


def _iou(det, truth, shape):
    md, mt = _fill_mask(det, shape), _fill_mask(truth, shape)
    inter = int(np.count_nonzero((md > 0) & (mt > 0)))
    union = int(np.count_nonzero((md > 0) | (mt > 0)))
    return inter / union if union else 0.0


def _corner_err_frac(det, truth, diag):
    """Mean per-corner Euclidean error as a fraction of the image diagonal."""
    d, t = _sort_roles(det), _sort_roles(truth)
    return float(np.mean(np.linalg.norm(d - t, axis=1))) / diag
```

- [ ] **Step 3: Add a looseness fixture with a known page rectangle**

Add this fixture builder next to `_page_on`:

```python
# True page rectangle shared by every known-page fixture (800x600 image, no
# downscale at max_side=1024). Corners: TL, TR, BR, BL.
PAGE_RECT = np.array([[150, 110], [650, 110], [650, 490], [150, 490]], float)


def _page_nub(bg, page):
    """Page + bright nubs straddling the border — simulates text/close-bridge
    bleed that pushes approxPolyDP off 4 points, so the pre-fix fitter falls
    back to a loose minAreaRect that swallows the nubs."""
    img = np.full((600, 800, 3), bg, np.uint8)
    cv2.rectangle(img, (150, 110), (650, 490), (page, page, page), -1)
    cv2.rectangle(img, (300, 92), (360, 130), (page, page, page), -1)   # top +18
    cv2.rectangle(img, (632, 250), (672, 310), (page, page, page), -1)  # right +22
    return img
```

Register it in `_cases()` by adding to the returned list:

```python
        ("page-nub-on-dark", _page_nub(55, 225), "bright"),
```

- [ ] **Step 4: Add the tightness block to `main()`**

`detect()` now returns a 5-tuple; update the two existing unpackings in `main()` that read `r[3]` (polarity) — they keep working (index 3 is still `polarity`). The 400px parity check compares `r[3]`/`r400[3]`; unchanged.

Add, inside the `for name, img, expect_polarity in _cases()` loop, after the existing polarity/parity checks:

```python
        # Tightness gate: for known-page fixtures, the detected quad must hug
        # the true page rectangle. diag of the 800x600 working image = 1000.
        TIGHT = {"page-on-dark", "page-on-light", "soft-shadow-on-dark",
                 "page-nub-on-dark"}
        T_IOU, T_ERR = 0.95, 0.015  # IoU floor, corner-error ceiling (frac diag)
        if name in TIGHT and r is not None:
            quad = r[4]
            iou = _iou(quad, PAGE_RECT, img.shape)
            err = _corner_err_frac(quad, PAGE_RECT, 1000.0)
            tight_ok = iou >= T_IOU and err <= T_ERR
            print(f"[{'PASS' if tight_ok else 'FAIL'}] {name:22s} "
                  f"tightness IoU={iou:.3f} (>= {T_IOU}) "
                  f"cornerErr={err*100:.2f}% (<= {T_ERR*100:.1f}%)")
            if not tight_ok:
                failures += 1
```

- [ ] **Step 5: Run the probe — confirm RED and record numbers**

Run: `python3 apps/mobile/tool/detect_probe.py; echo "exit=$?"`
Expected: **non-zero exit**, with tightness FAIL lines on the loose fixtures (at minimum `page-nub-on-dark`; likely `soft-shadow-on-dark` too). **Record the printed IoU/cornerErr numbers** for every TIGHT fixture in `.superpowers/sdd/` (the report) — these are the pre-fix baseline.

Honesty rule: a tightness assert that is already green pre-fix proves nothing. If **no** TIGHT fixture fails, the fixtures aren't exercising the loose path — deepen the `_page_nub` protrusions (e.g. top `(300,82)-(360,130)`, right `(642,250)-(692,310)`) until the pre-fix probe fails, and re-record. Do **not** relax `T_IOU`/`T_ERR` to force red.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/tool/detect_probe.py
git commit -m "test(scan): host-probe tightness metric + nub fixture (red gate for loose box)"
```

---

### Task 3: Fit fix in the probe — turn the tightness gate GREEN

**Files:**
- Modify: `apps/mobile/tool/detect_probe.py`

**Interfaces:**
- Consumes: `detect()` and metric block from Task 2.
- Produces: the convexHull + ε-sweep quad fitter (Python mirror of Task 4's Dart) and `_is_convex_quad`. Proves the algorithm host-side before it is ported to Dart.

- [ ] **Step 1: Add the Python convexity mirror**

Add near the metric helpers in `apps/mobile/tool/detect_probe.py`:

```python
def _is_convex_quad(q):
    """Mirror of isConvexQuad in detector_geometry.dart."""
    q = np.asarray(q, dtype=float).reshape(-1, 2)
    if q.shape[0] != 4:
        return False
    sign = 0
    for i in range(4):
        a, b, c = q[i], q[(i + 1) % 4], q[(i + 2) % 4]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cross) < 1e-9:
            return False
        s = 1 if cross > 0 else -1
        if sign == 0:
            sign = s
        elif s != sign:
            return False
    return True
```

- [ ] **Step 2: Replace the quad construction in `detect()`**

In `detect()`, replace the current block:

```python
        peri = cv2.arcLength(c, True)
        ap = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(ap) == 4 and cv2.isContourConvex(ap):
            quad = ap.reshape(-1, 2).astype(float)
        else:
            quad = cv2.boxPoints(cv2.minAreaRect(c)).astype(float)
```

with:

```python
        # Tight fit: convex hull drops interior jaggedness, then the smallest
        # epsilon that yields a 4-point convex quad wins; minAreaRect only if
        # none does (it bounds every protrusion → loose).
        hull = cv2.convexHull(c)
        peri = cv2.arcLength(hull, True)
        quad = None
        for frac in (0.01, 0.02, 0.03, 0.04, 0.05):
            ap = cv2.approxPolyDP(hull, frac * peri, True)
            if len(ap) == 4:
                cand = ap.reshape(-1, 2).astype(float)
                if _is_convex_quad(cand):
                    quad = cand
                    break
        if quad is None:
            quad = cv2.boxPoints(cv2.minAreaRect(c)).astype(float)
```

- [ ] **Step 3: Run the probe — confirm GREEN**

Run: `python3 apps/mobile/tool/detect_probe.py; echo "exit=$?"`
Expected: **exit 0**; every TIGHT fixture now prints `PASS ... tightness IoU=... cornerErr=...`, and all pre-existing null/polarity/400px-parity checks stay PASS. **Record the post-fix IoU/cornerErr numbers** next to the Task 2 baseline in the report.

If `page-nub-on-dark` still fails the ceiling, widen the sweep upper bound (append `0.06, 0.07` to the `frac` tuple — the nub depth relative to hull perimeter sets the ε needed) and re-run. Apply the same widening to Task 4's Dart `_kSegEpsFracs` to keep parity.

- [ ] **Step 4: Add the explicit success marker**

At the end of `main()`, replace:

```python
    print(f"\n{failures} failure(s)")
    sys.exit(1 if failures else 0)
```

with:

```python
    if failures:
        print(f"\n{failures} failure(s)")
        sys.exit(1)
    print("\nALL PROBE CHECKS PASS")
    sys.exit(0)
```

(This gives `scripts/verify/f4.sh` an unambiguous positive marker — `"0 failure(s)"` is a substring of `"10 failure(s)"`.)

- [ ] **Step 5: Re-run to confirm the marker**

Run: `python3 apps/mobile/tool/detect_probe.py | tail -1`
Expected: `ALL PROBE CHECKS PASS`

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/tool/detect_probe.py
git commit -m "feat(scan): convexHull+epsilon-sweep quad fit in host probe — tightness gate green"
```

---

### Task 4: Port the fit fix to the Dart `_segmentGray` core

**Files:**
- Modify: `apps/mobile/lib/features/scan/opencv_edge_detector.dart` (add `_kSegEpsFracs` constant near `_kSegKernelDivisor`; replace the quad-construction block inside the per-polarity loop of `_segmentGray`, currently ~lines 244–261)

**Interfaces:**
- Consumes: `isConvexQuad(List<Pt>)` (Task 1), `cv.convexHull`, `cv.arcLength`, `cv.approxPolyDP`, `cv.minAreaRect` (`opencv_dart`).
- Produces: no signature change — `_segmentGray` still returns the flat 9-element result; only the quad it fits is tighter. Both `detect()` and `detectFrame()` inherit the change.

libdartcv cannot load under host `flutter test`, so this port is verified by (a) `flutter analyze`, (b) the algorithm already proven in Task 3's probe, and (c) on-device in Task 6.

- [ ] **Step 1: Add the ε-sweep constant**

In `apps/mobile/lib/features/scan/opencv_edge_detector.dart`, after the `_kSegKernelDivisor` declaration:

```dart
/// Ascending fractions of the hull perimeter for the quad-fit ε sweep. The
/// smallest fraction yielding a 4-point convex quad wins; larger fractions
/// simplify away small edge protrusions/nubs. Mirrors detect_probe.py.
const List<double> _kSegEpsFracs = [0.01, 0.02, 0.03, 0.04, 0.05];
```

(If Task 3 widened the sweep, use the identical widened list here.)

- [ ] **Step 2: Replace the quad-construction block**

Inside `_segmentGray`'s per-polarity loop, replace the current block:

```dart
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
```

with:

```dart
        // Tight quad fit: the convex hull drops interior/text jaggedness, then
        // an ascending ε sweep takes the smallest simplification that yields a
        // 4-point convex quad sitting on the true page edges. minAreaRect is the
        // last resort only when no ε gives a clean quad (it bounds every
        // protrusion, so it reads slightly loose). Mirrors detect_probe.py.
        List<Pt>? quadPts;
        final hull = cv.convexHull(contour);
        final peri = cv.arcLength(hull, true);
        for (final frac in _kSegEpsFracs) {
          final approx = cv.approxPolyDP(hull, peri * frac, true);
          if (approx.length == 4) {
            final cand = List<Pt>.generate(
              4,
              (j) => (x: approx[j].x.toDouble(), y: approx[j].y.toDouble()),
            );
            approx.dispose();
            if (isConvexQuad(cand)) {
              quadPts = cand;
              break;
            }
          } else {
            approx.dispose();
          }
        }
        hull.dispose();
        if (quadPts == null) {
          final rect = cv.minAreaRect(contour);
          final box = rect.points; // VecPoint2f, 4 corners
          quadPts = List.generate(4, (j) => (x: box[j].x, y: box[j].y));
          box.dispose();
          rect.dispose();
        }
```

Downstream (`sortCornerRoles(quadPts)` …) is unchanged. Note `quadPts` is now `List<Pt>?` until assigned, then guaranteed non-null before use; keep the existing `final roles = sortCornerRoles(quadPts);` — since the fallback guarantees assignment, add `!` if the analyzer requires: `sortCornerRoles(quadPts!)`. Confirm with the analyzer in Step 4 and add `!` only if flagged.

- [ ] **Step 3: Confirm no stale `cv.isContourConvex` / disposal leak**

Run: `grep -n "isContourConvex" apps/mobile/lib/features/scan/opencv_edge_detector.dart`
Expected: no matches (the pure `isConvexQuad` replaced it).
Visually confirm every `approx` is disposed on both branches and `hull` is disposed exactly once before the fallback.

- [ ] **Step 4: Analyze**

Run: `cd apps/mobile && flutter analyze lib/features/scan/opencv_edge_detector.dart`
Expected: "No issues found!" (add `quadPts!` at the `sortCornerRoles` call if the analyzer reports a nullable use).

- [ ] **Step 5: Run the host-runnable scan tests (no libdartcv path)**

Run: `cd apps/mobile && flutter test test/features/scan/opencv_edge_detector_detectframe_test.dart test/features/scan/opencv_edge_detector_timeout_test.dart test/features/scan/detector_geometry_test.dart -r expanded`
Expected: PASS (these use injected runners / pure math and don't load libdartcv). If `opencv_edge_detector_test.dart` is run and fails, confirm it's the known environmental libdartcv-load failure, not a logic regression (see memory `opencv-host-test-and-detect-timeout`).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/opencv_edge_detector.dart
git commit -m "feat(scan): tighten detection quad via convexHull+epsilon-sweep fit (shared core)"
```

---

### Task 5: `scripts/verify/f4.sh` — encode the gate

**Files:**
- Create: `scripts/verify/f4.sh`

**Interfaces:**
- Consumes: `scripts/verify/lib.sh` (`require_tool`, `assert_cmd`, `assert_file_has`, `verify_summary`).
- Produces: the F4 verify script (none existed for the segmentation detector) — the progression gate for this work.

- [ ] **Step 1: Write the verify script**

Create `scripts/verify/f4.sh`:

```bash
#!/usr/bin/env bash
# Verify F4 (segmentation dot detection) — detector present + host probe green,
# including the box-tightness gate. Run: bash scripts/verify/f4.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== F4 verification =="

require_tool python3
require_tool flutter
require_tool git

# ---- Source presence (static asserts) ----
assert_file_has "detector uses convexHull quad fit" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" "cv.convexHull(contour)"
assert_file_has "detector uses epsilon sweep constant" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" "_kSegEpsFracs"
assert_file_has "detector no longer calls cv.isContourConvex" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" "isConvexQuad"
assert_file_has "pure isConvexQuad helper exists" \
  "apps/mobile/lib/features/scan/detector_geometry.dart" "bool isConvexQuad("
assert_file_has "probe computes tightness IoU" \
  "apps/mobile/tool/detect_probe.py" "tightness IoU="

# ---- Pure geometry unit tests ----
assert_cmd "isConvexQuad unit tests pass" "All tests passed" \
  bash -c "cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart 2>&1"

# ---- Host probe: algorithm + tightness gate (authoritative host check) ----
assert_cmd "detector host probe (incl. tightness) passes" "ALL PROBE CHECKS PASS" \
  python3 apps/mobile/tool/detect_probe.py

verify_summary
```

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x scripts/verify/f4.sh && bash scripts/verify/f4.sh; echo "exit=$?"`
Expected: `GATE: PASS`, exit 0, with the probe marker line matched.

- [ ] **Step 3: Negative control — prove the gate bites**

Run: `git stash push -- apps/mobile/tool/detect_probe.py && bash scripts/verify/f4.sh; echo "exit=$?"; git stash pop`

Wait — this reverts the probe entirely, which also removes the tightness block. Instead, prove the *tightness* gate specifically: temporarily revert only the fit block. Do this manually:
- In `apps/mobile/tool/detect_probe.py`, temporarily change the ε-sweep `frac` tuple to `(0.02,)` only and re-add `minAreaRect` bias is not needed — simpler: temporarily hardcode `quad = cv2.boxPoints(cv2.minAreaRect(c)).astype(float)` (the loose path).
- Run `bash scripts/verify/f4.sh` → expect `GATE: FAIL` with tightness FAIL lines and exit 1.
- Revert the temporary edit; re-run → `GATE: PASS`.

Record both outcomes in the report (the gate fails loose, passes tight).

- [ ] **Step 4: Commit**

```bash
git add scripts/verify/f4.sh
git commit -m "test(scan): scripts/verify/f4.sh — detector presence + host probe tightness gate"
```

---

### Task 6: On-device verification (iPhone) + close-out record

**Files:**
- Create: `.superpowers/sdd/tighten-box-report.md` (progress ledger for this branch)

**Interfaces:**
- Consumes: the merged fit fix.
- Produces: on-device evidence + recorded before/after numbers; the authoritative runtime confirmation.

- [ ] **Step 1: Build & run on the connected iPhone**

Run: `cd apps/mobile && flutter run -d 00008120-0016355C21E8201E`
(Confirm the device id with `flutter devices` first; use the iPhone's id.)

- [ ] **Step 2: Eyeball the box on a real page**

Point the camera at a real document on a contrasting surface. Confirm the detection overlay quad hugs the page edges **noticeably tighter** than the pre-fix build (edges sit on the paper boundary, not outside it). Capture a screenshot.

- [ ] **Step 3: Record the outcome**

Create `.superpowers/sdd/tighten-box-report.md` with: the Task 2 pre-fix vs Task 3 post-fix IoU/cornerErr numbers per fixture; the Task 5 negative-control result; the on-device screenshot path + a one-line verdict (tighter / not). If on-device shows the box is still loose in a way the metric didn't catch, that points at Otsu over-extension → note it as the trigger to escalate to Approach B (deferred), do **not** silently claim done.

- [ ] **Step 4: Update the memory index**

Update the memory file for dot detection (`.../memory/dots-detection-shadow-tolerant-limit.md`) to record that the loose-box tightening shipped (convexHull+ε-sweep fit; host tightness gate `scripts/verify/f4.sh`), so the "box is slightly loose (tightening open)" note is closed or downgraded to any residual Approach-B item.

- [ ] **Step 5: Commit**

```bash
git add .superpowers/sdd/tighten-box-report.md
git commit -m "docs(scan): tighten-box report — host + on-device (iPhone) evidence"
```

- [ ] **Step 6: Full-suite sanity + branch review**

Run: `cd apps/mobile && flutter test` and `bash scripts/verify/f4.sh`
Expected: suite green (modulo the known environmental libdartcv-load skips/failures), `GATE: PASS`.
Then request a whole-branch review (`master..feat/tighten-detection-box`) before invoking `superpowers:finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:**
- Tightness metric (corner error + IoU vs known rect) → Task 2. ✓
- Thresholds set so pre-fix fails / post-fix passes; numbers recorded → Task 2 Step 5 (red) + Task 3 Step 3 (green) + Task 6 report. ✓
- `convexHull` + ε-sweep quad fit, `minAreaRect` last resort → Task 3 (probe) + Task 4 (Dart). ✓
- Pre-existing probe cases unchanged → Task 2/3 keep null/polarity/parity asserts. ✓
- Isolate disposal preserved → Task 4 Step 3. ✓
- Pure ε-sweep/convexity helper unit-tested → Task 1 (`isConvexQuad`). ✓
- `scripts/verify/f4.sh` created with explicit marker + negative control → Task 5. ✓
- On-device iPhone tighter-box confirmation → Task 6. ✓
- Deferred items (erode-back, Approach B, live thresholds, auto-capture tuning) → Global Constraints + Task 6 escalation note. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; the one empirical value (tightness thresholds `T_IOU=0.95`, `T_ERR=0.015`) is concrete with an explicit honesty rule for adjusting the *fixture* (not the threshold) if pre-fix isn't red. ✓

**Type consistency:** `isConvexQuad(List<Pt>)` defined in Task 1, consumed in Task 4; `_kSegEpsFracs` defined + consumed in Task 4, mirrored `frac` tuple in Task 3; `detect()` 5-tuple `(conf, area_frac, fill, polarity, quad)` defined in Task 2, consumed in Task 2/3 metric + Task 3 fit. ✓
