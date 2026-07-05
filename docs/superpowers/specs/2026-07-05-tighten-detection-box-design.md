# Tighten the detection box — measure-then-fit

**Date:** 2026-07-05
**Status:** Approved (brainstormed)
**Feature bucket:** 04 Auto edge detection (segmentation dot detection close-out)

## Problem

The dual-polarity Otsu segmentation detector (merged `7652c67`) returns a
**slightly loose bounding box** around the page — a "usable best-guess" whose
edges sit outside the true page boundary. This was left as tracked future work.

Root cause, from `_segmentGray` in
`apps/mobile/lib/features/scan/opencv_edge_detector.dart`:

1. The quad is built as `approxPolyDP(contour, ε = 0.02·perimeter)` **only when
   that yields exactly 4 convex points**, otherwise it falls back to
   `minAreaRect`. `minAreaRect` is the *bounding* rotated rectangle of the whole
   blob, so any protrusion or shadow/halo the Otsu mask swept in pushes the box
   outward. This fallback is the dominant looseness source.
2. Secondary: `MORPH_CLOSE` (kernel `cols / 30`) can bulge the blob boundary
   outward as it bridges interior text.

Crucially, **looseness has never been quantified**: the host reference probe
(`apps/mobile/tool/detect_probe.py`) only asserts null/non-null outcomes and
polarity selection — it never measures how far the detected quad sits from the
true page edge.

## Approach — measure-then-fit

Two moves, in order:

1. **Make looseness measurable** (host probe): add a ground-truth tightness
   metric so "loose" has a number and we get a real red→green gate.
2. **Fix the dominant fitting cause**: replace the single
   `approxPolyDP`-or-`minAreaRect` step with a convex-hull + ε-sweep quad fit
   that finds the tight 4-corner quad in the common case, relegating
   `minAreaRect` to a genuine last resort.

The `MORPH_CLOSE` erode-back is **explicitly out of scope** — a reserve lever
applied only if the tightness metric shows residual outward bias *after* the fit
fix. YAGNI until the numbers ask for it.

## Design

### Component 1 — Tightness metric (`apps/mobile/tool/detect_probe.py`)

`detect()` currently returns `(confidence, areaFrac, fill, polarity)`. Extend it
to also return the detected quad's 4 corners (in the working-image pixel space it
already computes).

For the fixtures with a **known page rectangle** — `page-on-dark`,
`page-on-light`, `soft-shadow-on-dark` (page drawn at `(150,110)-(650,490)`) —
compute, after resolving the same downscale the pipeline applies:

- **Mean corner error**: match the detected quad's 4 corners to the 4 true rect
  corners by role (TL/TR/BR/BL via the existing sort), mean Euclidean distance
  in px, also reported as % of the image diagonal.
- **Quad↔rect IoU**: intersection-over-union of the detected quad polygon and the
  true page rectangle.

Add asserts for these three fixtures: `IoU ≥ T_iou` and
`mean_corner_error ≤ T_err`. **Threshold-setting protocol:** first run the
*current* (pre-fix) probe and record its numbers; choose `T_iou` / `T_err` so the
current code **fails** and the post-fix code **passes** — a genuine red→green
gate, not a rubber stamp. Record the before/after numbers in the plan's report.

All existing cases (`blank`, `noise`, `clutter`, the shape fixtures) keep their
null/non-null + polarity asserts unchanged and stay green (10/10 → still green
plus the new tightness asserts).

### Component 2 — The fit fix (`_segmentGray`)

Replace the current quad construction (lines ~245–261) with:

1. `hull = cv.convexHull(contour)` — removes interior jaggedness left by bridged
   text so the polygon approximation sees a clean outer shape.
2. **ε sweep**: for ε in a small ascending set expressed as fractions of the hull
   perimeter (e.g. `[0.01, 0.02, 0.03, 0.04, 0.05]`), compute
   `approxPolyDP(hull, ε·perimeter, true)`; take the **smallest ε** that yields
   exactly 4 points that are convex — those are the quad corners.
3. If no ε in the sweep yields a 4-point convex quad, fall back to
   `minAreaRect(contour)` exactly as today (unchanged last-resort behavior).

Everything downstream is unchanged: `sortCornerRoles` → `quadArea` →
`rectangularityScore` → `isPlausiblePage` guard → `detectionConfidence`
→ highest-confidence survivor across polarities. Native-resource ownership and
disposal rules in the isolate are preserved (hull is a `cv.Mat`/`VecPoint`
allocated and disposed within the per-polarity `try/finally`, same as `approx`
today).

`detect_probe.py` mirrors this exact logic (convex hull + identical ε sweep +
identical fallback) so the host reference stays faithful to the Dart.

### Component 3 — Scope, shared core, and what is gated

- The change lives in the **shared `_segmentGray` core**, so both paths benefit:
  the still path (`detect`, `_kDetectMaxSide = 1024` — its corners feed the actual
  crop) and the live guide (`detectFrame`, `_kLiveDetectMaxSide = 400`).
- **Tightness is gated on the still path**, whose corners are the ones that
  actually crop the page. The live overlay is a guide only and is not held to the
  tightness thresholds.

## Deliverable (user-testable)

1. **Host:** `python3 apps/mobile/tool/detect_probe.py` prints per-fixture
   tightness numbers (IoU + mean corner error) for the page fixtures and exits 0
   with all asserts (including the new tightness asserts) passing. Running it
   against the pre-fix code shows the tightness asserts **failing** (demonstrating
   the gate is real).
2. **Verify script:** `scripts/verify/f4.sh` exits 0, printing the probe's
   success marker; run from a clean state and confirmed by an independent
   verifier subagent. (The F4 segmentation detector shipped without a verify
   script — this work creates it, encoding both the existing probe outcomes and
   the new tightness asserts.)
3. **On-device (iPhone, connected):** capture a real page; the live/still overlay
   box visibly hugs the page edge tighter than the pre-fix build (side-by-side or
   before/after screenshot).

## Acceptance criteria

- [ ] `detect_probe.py` returns the detected quad corners and computes mean corner
      error (px + % diagonal) and quad↔rect IoU for the three known-page fixtures.
      *(probe self-check)*
- [ ] Tightness asserts are set so the **pre-fix** pipeline FAILS them and the
      **post-fix** pipeline PASSES; before/after numbers recorded in the report.
      *(probe run, both revisions)*
- [ ] `_segmentGray` builds the quad via `convexHull` + ε-sweep `approxPolyDP`,
      taking the smallest ε giving a 4-point convex quad; `minAreaRect` only when
      the sweep finds none. *(host probe tightness asserts; code review)*
- [ ] All pre-existing probe cases (blank/noise/clutter/shapes) keep their
      null/non-null + polarity outcomes — no regression. *(probe run)*
- [ ] Native-resource disposal in the isolate is preserved (no leaked
      `Mat`/`VecPoint` on any path). *(code review; existing isolate discipline)*
- [ ] If an ε-sweep corner-selection helper can be isolated free of `cv.*` types,
      it has a `detector_geometry`-style Dart unit test. *(unit)*
- [ ] `scripts/verify/f4.sh` is created (none existed for the F4 detector),
      encodes the probe as an assert (exact command + success marker, exit-code
      checked, silence = FAIL), and exits 0 under an independent verifier.
      *(verify harness)*
- [ ] On the connected iPhone, the detected box hugs a real page edge visibly
      tighter than the pre-fix build. *(on-device, corroborating screenshot)*

## Non-goals / deferred

- **`MORPH_CLOSE` erode-back / kernel retune** — reserve lever, applied only if
  the tightness metric shows residual outward bias after the fit fix.
- **Corner/edge gradient snapping** (the heavier "Approach B") — escalate to it
  only if the metric shows Otsu over-extension, not fitting, is the bottleneck.
- **Live-path tightness thresholds** — the live overlay stays a guide.
- Auto-capture parameter tuning (`requiredStableFrames` / `maxCornerDelta` /
  `minConfidence`) — the *other* on-device gap, sequenced after this per the
  session decision (box first, then tune).

## Testing notes

- `libdartcv` cannot load under host `flutter test` (established environmental
  limitation), so the cv-bound pipeline is gated by the host probe — the
  project's standing practice for this detector. On-device is the authoritative
  runtime check.
- The connected device this session is an **iPhone (iOS 18.7.8)**; iOS/OpenCV
  parity with Android was previously established. Re-confirm on Android
  (RZCY51D0T1K) opportunistically when connected.
