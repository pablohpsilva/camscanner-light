# Curved Crop + Coons-Patch Unwarp — Design

**Date:** 2026-07-01
**Status:** Approved (pending spec review)
**Relates to:** Feature 03 (Manual crop & perspective), Feature 05 (enhancement pipeline consumes the warp output). Extends the E1/E2/E3 crop+flatten slice.

## Goal

Let the user correct **curved** document edges (book spines, lens barrel distortion, pages that bow) — not just straight-edged perspective skew. The crop overlay gains **4 edge-midpoint handles** (8 total: 4 corners + 4 midpoints). Pulling a midpoint bends that edge into a smooth curve, and the flatten step unwarps the curved region to a flat rectangle.

Straight-edged crops (all midpoints centered) must behave **exactly** as today — same handles feel, same true-perspective flatten, no regression.

## Non-goals

- No change to auto edge-detection (F1/OpenCV still emits 4 corners; midpoints default to centered).
- No mesh beyond a single Coons patch (no arbitrary N-point polygons, no per-pixel manual mesh editing).
- **Not a full book-dewarp.** One quadratic per edge + a bilinear Coons interior corrects the *boundary* shape and gentle bowing. It does NOT straighten text bowing in the *interior* of a strongly curled page — that needs a dense mesh or cylindrical page model (a separate, larger feature). This slice targets edge/perspective correction and mild curl.
- No new DB migration (reuses the existing `Pages.corners` text column).
- No OCR/PDF changes.

## Core decisions (from brainstorming)

1. **8 points:** 4 role-tagged corners + 4 role-tagged edge midpoints, each a normalized `Offset` in `[0,1]` display frame.
2. **Smooth curved edges:** each edge is a **quadratic Bézier** through `corner → midpoint → corner`.
3. **Midpoint is on the curve:** the dragged dot is the point the Bézier passes through at `t=0.5`, not an abstract control point. With the deviation model (below), the midpoint is `M = center + dev` and the control point is `C = center + 2·dev`. When `dev = 0`, `C = center` → the edge is straight.
4. **Hybrid warp:** homography for straight edges (exact perspective), Coons patch only when an edge is bent.

## Data model — extend `CropCorners`

`lib/features/library/crop_corners.dart`.

Add four **edge-midpoint deviations** to the existing class (keep the name to avoid churn across repository, viewer, warper, overlay). A deviation is how far the edge's midpoint is pulled off the straight-line center, as a normalized `Offset`:

```
final Offset topLeft, topRight, bottomRight, bottomLeft;              // existing
final Offset topMidDev, rightMidDev, bottomMidDev, leftMidDev;        // NEW, default Offset.zero
```

**Why deviation, not an absolute midpoint** (this is a deliberate correction to an earlier draft):

- `Offset.zero` **is** a valid `const` default; a centered *absolute* midpoint `(topLeft+topRight)/2` is **not** (it depends on other params). So every existing `const CropCorners(topLeft:…, bottomLeft:…)` call site — the OpenCV detector and the overlay's `emitNew` — keeps compiling **unchanged**.
- **Corner-drag tracking is automatic:** the actual midpoint is a getter `topMid => center(topLeft,topRight) + topMidDev`. Move a corner → the edge center moves → the midpoint follows. No stateful "is it centered" bookkeeping.
- `isStraight` ⟺ all four deviations are `Offset.zero` (within an epsilon).
- Bézier control point for an edge: `C = center + 2·dev` (so the curve passes through `center + dev` at `t=0.5`; `dev = 0` ⇒ `C = center` ⇒ straight line).

Other members:
- **Midpoint getters:** `topMid, rightMid, bottomMid, leftMid` = edge center + corresponding deviation.
- `fullFrame`: corners at the image bounds, all deviations zero → straight, full image. Warp no-op sentinel unchanged.
- **Edge → curve mapping (role order):** `topMidDev` bends TL↔TR, `rightMidDev` bends TR↔BR, `bottomMidDev` bends BR↔BL, `leftMidDev` bends BL↔TL.
- `clamp()`: clamps the 4 corners to `[0,1]`; clamp resolved midpoints too (guard extreme deviations).
- `==`/`hashCode`/`toString`: include the 4 deviations.

### Persistence (backward compatible)

- `toStorage()` → **16** fixed-precision numbers: 4 corners then 4 deviations, role order `TL,TR,BR,BL, topDev,rightDev,bottomDev,leftDev`.
- `tryParse(s)`:
  - **16 numbers** → corners + deviations.
  - **8 numbers** (legacy) → 4 corners + **zero** deviations (straight). Preserves every already-saved document.
  - any other count / non-finite → `null` (fail-soft, unchanged contract).

## Warp engine — hybrid facade

Interface `ImageWarper` is unchanged: `Future<Uint8List?> warp(Uint8List bytes, CropCorners corners)`. Runs in a `compute()` isolate and inherits the existing timeout guard behavior.

**Dispatch** (a thin `ImageWarper` that composes the two, or a branch inside the concrete warper):
- `corners == fullFrame` → return `null` (no-op, as today).
- `corners.isStraight` → **`PerspectiveWarper`** (existing homography). Exact perspective; zero behavior change for the common path.
- otherwise → **`CoonsWarper`** (new).

### `CoonsWarper`

Pure-Dart (`image` package), same isolate/dispose discipline as `PerspectiveWarper`.

1. Decode + `bakeOrientation` (identical to `PerspectiveWarper` — corners are normalized against the baked frame).
2. Denormalize the 8 points to source pixels.
3. Build 4 boundary curves as quadratic Béziers `C_top(u), C_bottom(u), C_left(v), C_right(v)` (`u,v ∈ [0,1]`), each with its derived control point.
4. Output size: `outW = max(arc-length(top), arc-length(bottom))`, `outH = max(arc-length(left), arc-length(right))`, rounded; guard `< 2px` → `WarpException`; **cap** each dimension at a max (e.g. the source's larger dimension × a small factor) so an extreme bend can't produce a huge/OOM output.
5. For each output pixel `(u,v)` (normalized), evaluate the **Coons patch**:
   `S(u,v) = (1−v)·C_top(u) + v·C_bottom(u) + (1−u)·C_left(v) + u·C_right(v) − bilinear(corners)`
   where `bilinear(corners)` is the standard 4-corner bilinear blend. This inverse-maps output→source.
6. Sample source with `getPixelInterpolate(..., linear)`; write to output.
7. Encode JPEG (quality 92, matching `PerspectiveWarper`).
8. Validity: reject degenerate/self-folding patches (e.g. non-finite or out-of-image samples beyond a tolerance) → `WarpException`; the repository already treats a thrown warp as "flat stays null, save proceeds."

**Perf:** ~O(1) per output pixel (a handful of Bézier + blend flops), same order as homography; budget stays within the existing <2s device target for large images.

## Overlay UI — `CropOverlay`

`lib/features/scan/widgets/crop_overlay.dart`.

- Render **8 handles**: 4 corner (as today) + 4 midpoint. Midpoints visually distinct (e.g. smaller / hollow) so they read as "edge" vs "corner." Keyed `crop-handle-{tl,tr,br,bl,top,right,bottom,left}`, each `Semantics`-labeled.
- **Hit-testing:** with 8 handles the ~44px touch targets can overlap on small crops. Corners take priority (hit-test corners before midpoints); optionally suppress a midpoint handle when it would overlap a corner.
- **Corner drag:** unchanged — moves that corner. Because midpoints are stored as *deviations from the edge center*, a straight edge stays straight and a bent edge keeps its bend automatically as the corner moves (the getter re-centers). No special tracking code.
- **Midpoint drag:** updates only that edge's deviation → bends its edge. Clamp the resolved midpoint to `[0,1]`.
- **Edge rendering:** `_QuadPainter` draws each edge via `Path.quadraticBezierTo(control, endCorner)` using the derived control point; the dim-outside mask uses the same curved path so the darkened region hugs the curve.
- `highlightColor`, `enabled`, scaling/letterbox math: unchanged.

## Testing (TDD)

**Host (`flutter test`):**
- `CropCorners`: centered-midpoint defaults; `isStraight`; `toStorage`/`tryParse` round-trip for **both** 8- and 16-number forms; legacy 8→straight; fail-soft cases.
- `CoonsWarper` (pure Dart, runs on host): on an **axis-aligned** rect with zero deviations it is the identity (note: Coons-with-straight-edges is *bilinear*, which equals homography only without perspective — so do **not** assert equivalence to the homography warp under skew); a known **bowed** fixture unwarps so a curved boundary maps to a straight-edged rectangle (assert output edge straightness / corner mapping); output-size cap respected; degenerate/folded patch → `WarpException`.
- Hybrid dispatch (the routing, not the math): `fullFrame`→null, `isStraight`→perspective/homography path, any deviation→coons path (inject fakes to assert which runs).
- `CropOverlay` widget: 8 handles present by key; dragging a midpoint emits a `CropCorners` with the bent midpoint; corner drag unchanged; disabled state.

**Device (`flutter test integration_test -d <device>`):**
- Extend edge-detection/warp integration: capture→bend an edge→flatten produces non-null flat bytes; large curved fixture completes < 2s.

## Backward compatibility summary

- Existing saved docs (8-number corners) parse as straight → identical rendering + flatten.
- Existing call sites constructing `CropCorners(topLeft:…, bottomLeft:…)` compile via centered-midpoint defaults.
- Straight-edge flatten still uses the proven homography — no perspective regression.

## Phased implementation

1. **Model + persistence** — extend `CropCorners`, 16/8 parse, `isStraight`, defaults. Tests first.
2. **Warp** — `CoonsWarper` + hybrid facade. Pure-math tests first.
3. **Overlay** — 8 handles, Bézier edges, curved mask. Widget tests first.
4. **Wire + device verify** — review screen + edit-crop screen pass 8-point shapes end to end; on-device integration check.

## Risks / open notes

- **Corner-drag ↔ midpoint tracking** — resolved structurally by the deviation model: midpoints are `center + dev`, so they follow moving corners automatically; no special case.
- **Coons self-fold** at extreme bends — clamp handle range and reject folded/non-finite patches; acceptable because the repository degrades gracefully (keeps original on warp failure).
- **Interior curvature** — Coons corrects the boundary, not strong interior page curl (see Non-goals). Set expectations; a mesh/cylindrical dewarp is a later feature.
- Bilinear-vs-perspective difference is deliberately avoided by the hybrid split (homography for straight, Coons only for bent).
- **8-handle overlap** on small crops — mitigated by corner-priority hit-testing.
