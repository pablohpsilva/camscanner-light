# Segmentation-Based Dot Detection — Design

**Date:** 2026-07-03
**Status:** Approved (design)

## Goal

Make the automatic crop-corner ("dots") detector find the real document
boundary on **real full-page captures**, where the current flat-field + Canny
pipeline returns `null`. Replace edge-detection-on-a-flat-fielded-image with
**region segmentation**: threshold the page away from its background, take the
largest page-shaped blob, and fit a quad.

## Why (evidence)

On two real captures (an INL language-test page; a lalux insurance doc), the
shipped detector returns `null`. Host replication with cv2 (which reproduces
the on-device `dartcv4` output bit-for-bit — the flat-field close-k=3 largest
contour was 2.9% on both) showed the cause: the flat-field pass flattens not
just interior shadow but the **page/desk boundary** (a locally-uniform desk
normalizes to ~white, same as the page), so the Canny map is dominated by
interior text and background clutter while the page outline nearly vanishes.
Largest closed contour: 3–12% of frame — below the 5% gate → `null`.

A **segmentation** prototype recovered both pages: Otsu-binarize the bright
page vs. darker surroundings → morphological close (fills interior text) →
largest bright contour → `minAreaRect`. Result: sample **73.3% area, fill
0.87**; lalux **67.2%, fill 0.78**; the box hugs the page (verified visually).
Conclusion: for crop-corner detection we want the page-vs-background
**boundary**, not interior uniformity. Flat-field belongs in the Auto *filter*,
not the detector.

## Behavior decisions (locked)

- **Dual polarity.** Handle both a page brighter than its background (page on a
  dark desk) and a page darker than its background (page on a light surface):
  consider both the bright-side and dark-side segmentation and pick the
  better-scoring candidate.
- **Best-guess, tinted.** Return the best surviving candidate with a confidence
  score; the review screen tints green/amber/blue (unchanged). `null` only when
  no candidate survives the guards.
- **Flat-field removed from detection.** It stays in the Auto filter
  (`auto_enhancer.dart`), untouched.

## Pipeline (new `_runPipeline`)

Runs in the existing `compute()` isolate; 5 s timeout, never-throws, full
native-resource dispose discipline — all unchanged.

1. **decode** → empty-Mat guard → `null`.
2. **downscale** to ≤ `_kDetectMaxSide` (1024) longest side.
3. **grayscale** `COLOR_BGR2GRAY`.
4. **Gaussian blur** (`_kSegBlur` = 7, i.e. `(7,7)`) to suppress text/texture so
   the page reads as one region.
5. **Otsu threshold**: `cv.threshold(blurred, 0, 255, THRESH_BINARY|THRESH_OTSU)`
   → `maskBright` (page-brighter mask) + the split value; also compute
   `maskDark` = the inverse (`THRESH_BINARY_INV`, same Otsu value).
6. **For each polarity mask** in `[maskBright, maskDark]`:
   a. **morphological close** with a rect kernel of side
      `kseg = max(3, round(cols / _kSegKernelDivisor))` (`_kSegKernelDivisor` =
      30; odd-ized), iterations 1 — fills interior text holes into a solid page
      blob.
   b. **findContours** `RETR_EXTERNAL, CHAIN_APPROX_SIMPLE`.
   c. For the **largest** contour with area ≥ `imageArea * 0.05`:
      - build a quad: `approxPolyDP(contour, 0.02·arcLength, true)`; if it is a
        4-point convex polygon → use those 4 points (true perspective fit); else
        `boxPoints(minAreaRect(contour))`.
      - **guards** (reject → skip this candidate):
        - `area > imageArea * _kMaxAreaFrac` (0.92) — "everything" (a blank
          scene, or the background polarity's frame-filling blob);
        - `fill = area / quadArea < _kMinFill` (0.55) — not rectangular
          (clutter, or a frame-minus-page background blob).
      - (Note: a legitimate page can fill most of the frame and touch all four
        borders, so border-touching is NOT a reject criterion — the area cap and
        fill floor already reject the background/blank blobs, and scoring by fill
        favors the page over an irregular background region.)
      - score with `detectionConfidence(areaScore, angleScore, rectScore)` where
        `rectScore = fill` (existing helper), `angleScore` from `sortCornerRoles`
        + `angleScore` (existing).
7. Pick the **highest-confidence** surviving candidate across both polarities.
   Sort its corners with `sortCornerRoles`, normalize to [0..1], return
   `[tl.., tr.., br.., bl.., confidence]`. Return `null` if none survive.

**Native-resource discipline:** every `Mat`/`Vec`/`RotatedRect`/`VecPoint2f`
(gray, blurred, maskBright, maskDark, per-polarity `closed`/`kernel`/`contours`/
`hierarchy`, per-candidate `approx`/`rect`/`box`) disposed exactly once —
explicit-then-null or in `finally`. All `cv.*` calls synchronous.

### Guard helper (pure Dart, in `detector_geometry.dart`)

- `bool isPlausiblePage({required double areaFrac, required double fill,
  double minAreaFrac = 0.05, double maxAreaFrac = 0.92, double minFill = 0.55})`
  — the combined accept predicate (`minAreaFrac ≤ areaFrac ≤ maxAreaFrac && fill
  ≥ minFill`), unit-testable without OpenCV.

Reuse existing `sortCornerRoles`, `quadArea`, `angleScore`,
`rectangularityScore`, `detectionConfidence`.

## Data flow & UI

Unchanged. `detect()` returns `DetectionResult(corners, confidence)`;
`capture_review_screen` auto-fills `_corners` and tints
green ≥0.6 / amber ≥0.3 / blue by confidence. Live-preview sampling unchanged.

## Error handling

Unchanged contract: `_runPipeline` returns `null` on decode failure / no
surviving candidate / any exception; `detect()` returns `null` on timeout. UI
treats `null` as full-frame, blue.

## Testing & verification

**Host cv2 harness (fast loop, committed):** a Python replica of the pipeline
(`apps/mobile/tool/detect_probe.py`) run against **synthetic-but-realistic
fixtures** committed to the repo:
- bright page (soft-shadowed) on a dark desk → box hugs page, non-null;
- page on a *light* surface (dark-polarity path) → box hugs page, non-null;
- blank / uniform, pure-noise, and clutter-only (no page) → `null`.
The user's real photos are **NOT committed** (personal documents); they are used
only for the local on-device eyeball.

**Dart host tests** (`detector_geometry_test.dart`): `isPlausiblePage` truth
table (fill above/below the floor; area below the min, in range, and above the
full-frame cap).

**On-device** (`integration_test/f4_segmentation_test.dart`, real libdartcv):
synthetic bright-on-dark and dark-on-light page fixtures → non-null quad within
tolerance; blank/noise → `null`. Plus a **manual real-capture eyeball**: run
`detect()` on the user's actual gallery captures, draw the quad, pull the
annotated image, confirm it hugs the page.

**Retire/adjust:** the flat-field-specific expectations in `f3` and in
`opencv_edge_detector_test.dart` (Otsu-adaptive-Canny, minAreaRect-from-Canny)
are replaced to describe the segmentation behavior; the always-best-guess
shape-test semantics (circle/pentagon → non-null) still hold and stay.

## Out of scope

- Hough-line edge completion / ML document segmentation (a heavier future
  option if Otsu segmentation proves insufficient on some captures).
- Manual-drag UX, and warping/cropping to the quad (this positions the dots
  only).
- A page whose brightness is genuinely indistinguishable from its background on
  *both* polarities (e.g. white page on a white desk) remains a hard limit.

## Files

- **Modify:** `apps/mobile/lib/features/scan/opencv_edge_detector.dart`
  (replace `_runPipeline`; drop the flat-field/adaptive-Canny steps).
- **Modify:** `apps/mobile/lib/features/scan/detector_geometry.dart`
  (add `isPlausiblePage`).
- **Create:** `apps/mobile/tool/detect_probe.py` + synthetic fixtures under
  `apps/mobile/tool/fixtures/`.
- **Modify:** `apps/mobile/test/features/scan/detector_geometry_test.dart`.
- **Modify:** `apps/mobile/test/features/scan/opencv_edge_detector_test.dart`
  (segmentation expectations).
- **Create:** `apps/mobile/integration_test/f4_segmentation_test.dart`.
- **Modify:** `apps/mobile/integration_test/f3_shadow_detection_test.dart`
  (align with segmentation, or fold into f4).
