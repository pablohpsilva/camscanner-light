# Shadow-Tolerant Dot Detection — Design

**Date:** 2026-07-02
**Status:** Approved (design)

## Goal

Make the automatic crop-corner ("dots") detection reliably find the real
document boundary on captures with **soft shadows** (a hand/phone shadow, or
uneven lighting that dims one paper edge into the background). Today the
detector returns `null` on these frames, so the dots stay on the full frame
and the user must drag all four from scratch.

## Behavior decisions (locked)

- **Best-guess, always.** When the detector is not confident, it still returns
  its best estimate of the paper quad (not `null`/full-frame). The UI tints
  low-confidence results to signal "please check."
- **Primary scene:** soft shadows / uneven lighting. High-contrast captures
  (dark surface, whole page visible) must not regress.

## Current implementation (baseline)

`apps/mobile/lib/features/scan/opencv_edge_detector.dart` → `_runPipeline`
(runs in a `compute()` isolate, 5 s timeout, never throws):

```
decode → downscale ≤1024 → grayscale → GaussianBlur 5×5 →
Canny(75, 200) → findContours(RETR_EXTERNAL) →
keep contours whose approxPolyDP(ε=2%) is EXACTLY 4 pts, convex, ≥5% area →
pick largest → sort into TL/TR/BR/BL → normalize [0..1] →
confidence = 0.6·areaScore + 0.4·angleScore
```

**Why it fails on soft shadows:**

1. **Fixed Canny 75/200** — a shadow-dimmed paper edge produces weak gradients
   that don't survive, so no edge forms there.
2. **No gap-bridging** — Canny output is fragmented; a partially shadowed edge
   never closes into a loop, so `findContours` yields no enclosing contour.
3. **Requires exactly a 4-point convex `approxPolyDP`** — perspective or a soft
   corner approximates to 5–6 points and is rejected.
4. **Null on miss** — any of the above → `null` → dots stay full-frame.

## Approach

Normalize illumination *before* edge detection (reusing the flat-field concept
proven in the Auto-filter rebuild), robustify the contour → quad extraction so
near-misses still yield a quad, and always return the best-scored candidate.

### New pipeline (`_runPipeline`)

Changes are marked **[NEW]**; unmarked steps are unchanged.

1. **decode** → empty `Mat` guard → `null` (unchanged).
2. **downscale** to ≤ `_kDetectMaxSide` (1024) longest side (unchanged).
3. **grayscale** `COLOR_BGR2GRAY` (unchanged).
4. **[NEW] Illumination normalization (flat-field).**
   - Estimate the background illumination `bg` from a **downscaled proxy** of
     `gray` (resize to ≤ `_kIllumProxySide` = 256 longest side, heavy
     `GaussianBlur`, resize back up to full working size with `INTER_LINEAR`).
     The proxy keeps this cheap enough for the live loop.
   - `normalized = divide(gray, bg, scale=255)` — flattens the low-frequency
     shadow gradient while preserving the high-frequency paper/desk step edge.
   - Result `normalized` (8-bit gray) replaces `gray` downstream.
5. **GaussianBlur 5×5** on `normalized` (unchanged op, new input).
6. **[NEW] Adaptive Canny thresholds.** Compute Otsu's threshold `t` on the
   **blurred** Mat (the Canny input) via
   `cv.threshold(blurred, 0, 255, THRESH_BINARY | THRESH_OTSU)` (use the
   returned value; dispose the thresholded Mat). Set
   `hi = clamp(t, 40, 220)`, `lo = 0.5·hi`. Replaces fixed `Canny(75, 200)`.
7. **[NEW] Morphological close** on the Canny edge map:
   `morphologyEx(edges, MORPH_CLOSE, kernel=3×3 rect, iterations=1)` to bridge
   short gaps into closed loops.
8. **findContours** `RETR_EXTERNAL, CHAIN_APPROX_SIMPLE` (unchanged).
9. **[NEW] Relaxed quad extraction.** Iterate contours; consider any contour
   whose area ≥ `minQuadArea` (5% of working image). For each candidate build a
   4-corner quad by:
   - `approx = approxPolyDP(contour, ε=2%·arcLength, closed=true)`;
   - if `approx.length == 4 && isContourConvex(approx)` → quad = approx points;
   - **else** quad = `boxPoints(minAreaRect(contour))` (4 corners of the
     min-area rotated rectangle enclosing the contour).
   Track the **best** candidate by score (step 10), not merely largest area.
10. **[NEW] Scored selection.** For each candidate quad compute (all in pure
    Dart from extracted points — see *Pure-Dart split*):
    - `areaScore = quadArea / imageArea` clamped [0,1];
    - `angleScore = 1 − meanInteriorAngleErrorFrom90 / 90` clamped [0,1]
      (existing formula);
    - `rectScore = contourArea / quadArea` clamped [0,1] (fill ratio: how
      rectangular the contour is; a true page ≈ 1, a ragged blob ≪ 1);
    - `confidence = 0.5·areaScore + 0.3·angleScore + 0.2·rectScore`.
    Keep the highest-confidence candidate.
11. Sort the winning quad's points into canonical TL/TR/BR/BL roles (existing
    sum/diff sort), normalize to [0..1], return
    `[tlDx,tlDy,trDx,trDy,brDx,brDy,blDx,blDy,confidence]`.
    Return `null` **only** when no contour ≥ `minQuadArea` exists.

**Native-resource discipline unchanged:** every `Mat`/`Vec` allocated in the
isolate is disposed in `finally`; new intermediates (`bg`, `proxy`,
`normalized`, `otsuOut`, `closed`, per-candidate `approx`/`minAreaRect`
outputs) follow the same dispose-and-null pattern. All `cv.*` calls stay
**synchronous** (never `*Async` inside `compute`).

### Pure-Dart split (for host-testability)

`libdartcv` does not load under host `flutter test`, so the scoring/geometry
math must be callable without any `cv.*`. Extract into a new file
`apps/mobile/lib/features/scan/detector_geometry.dart` as pure functions
operating on plain point records `({double x, double y})`:

- `List<({double x, double y})> sortCornerRoles(List<...> pts)` → returns
  `[tl, tr, br, bl]` (the existing sum/diff sort).
- `double angleScore(List<...> quadTLTRBRBL)` → mean-interior-angle score.
- `double rectangularityScore(double contourArea, double quadArea)`.
- `double detectionConfidence({required double areaScore, required double
  angleScore, required double rectScore})`.

`_runPipeline` calls these after extracting points from the native quad. The
OpenCV-dependent steps (normalize, Canny, contours, `minAreaRect`) stay in
`opencv_edge_detector.dart` and are verified on-device only.

### UI change (small)

`apps/mobile/lib/features/scan/capture_review_screen.dart` — replace the
two-tier highlight with three tiers so low-confidence best-guesses read as
"verify me":

```dart
Color get _highlightColor {
  final c = _detectionConfidence ?? -1;
  if (c >= 0.6) return Colors.green;   // confident
  if (c >= 0.3) return Colors.amber;   // best-guess, please check
  return Colors.blue;                  // fallback / full-frame
}
```

Live-preview's `confidence >= 0.5` gate in `camera_screen.dart` is unchanged
(a low-confidence live frame simply doesn't draw the green quad).

## Data flow

Unchanged. `detect()` still returns `DetectionResult(corners, confidence)`;
`capture_review_screen` still auto-fills `_corners` on any non-null result and
locks out detection on first user touch. The only behavioral shift is that the
detector now returns a non-null best-guess far more often, and the tint has an
amber tier.

## Error handling

Unchanged contract: `_runPipeline` returns `null` on decode failure / no
candidate / any exception; `detect()` returns `null` on timeout. The UI treats
`null` as "keep full-frame, blue tint."

## Testing & verification

**Host tests** (`test/features/scan/detector_geometry_test.dart`, run for
real — no `cv.*`):
- `sortCornerRoles` assigns TL/TR/BR/BL correctly for a rotated/perspective
  quad and for an axis-aligned rect.
- `rectangularityScore` = 1.0 for a perfect rectangle contour, < 0.5 for a
  half-filled quad, clamped to [0,1] on degenerate input.
- `detectionConfidence` weighting: verify the 0.5/0.3/0.2 blend and clamping.
- `angleScore` = 1.0 for a 90°-corner quad, lower for a skewed one.

**Existing OpenCV tests** (`test/features/scan/opencv_edge_detector_test.dart`)
— update expectations that assumed fixed thresholds / exactly-4-point
rejection; these remain environmental (skipped/failing without libdartcv) but
must not reference removed internals.

**On-device (the real gate):**
- A debug integration harness
  (`integration_test/f3_shadow_detection_test.dart`) loads a bundled real
  shadowed capture, runs `OpenCvEdgeDetector().detect()`, draws the returned
  quad over the image (using the `image` package), and writes the annotated
  JPEG to app-visible storage. Pull via `adb`, eyeball that the quad hugs the
  paper.
- Manual: build release, capture a real shadowed page on device RZCY51D0T1K,
  confirm the dots land on the paper (green/amber), not the full frame.

**Perf guard:** confirm the live 800 ms sampling loop stays smooth on-device
with normalization added (proxy keeps it cheap). Only if measurably sluggish,
add a `fast` flag to skip normalization on the live path; do **not** add it
speculatively (YAGNI).

## Out of scope

- Hough-line / multi-strategy detection (Approach B) — reserved for the
  cluttered-desk scene, which was explicitly deprioritized.
- Manual dragging UX (magnifier, snapping) — the dots' hit targets and drag
  behavior are unchanged.
- Auto-crop *application* (actually warping/cropping to the quad) — this design
  only positions the dots.

## Files

- **Modify:** `apps/mobile/lib/features/scan/opencv_edge_detector.dart`
- **Create:** `apps/mobile/lib/features/scan/detector_geometry.dart`
- **Modify:** `apps/mobile/lib/features/scan/capture_review_screen.dart`
- **Create:** `apps/mobile/test/features/scan/detector_geometry_test.dart`
- **Modify:** `apps/mobile/test/features/scan/opencv_edge_detector_test.dart`
- **Create:** `apps/mobile/integration_test/f3_shadow_detection_test.dart`
- **Add fixture:** a real shadowed capture as a bundled test asset.
