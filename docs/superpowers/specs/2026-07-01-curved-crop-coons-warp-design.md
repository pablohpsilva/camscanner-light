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
- No new DB migration (reuses the existing `Pages.corners` text column).
- No OCR/PDF changes.

## Core decisions (from brainstorming)

1. **8 points:** 4 role-tagged corners + 4 role-tagged edge midpoints, each a normalized `Offset` in `[0,1]` display frame.
2. **Smooth curved edges:** each edge is a **quadratic Bézier** through `corner → midpoint → corner`.
3. **Midpoint is on the curve:** the dragged dot is the point the Bézier passes through at `t=0.5`, not an abstract control point. Control point derived: `C = 2·M − ½·(P₀+P₂)`. When `M` is the edge center, `C` collapses to the straight-line midpoint → the edge is straight.
4. **Hybrid warp:** homography for straight edges (exact perspective), Coons patch only when an edge is bent.

## Data model — extend `CropCorners`

`lib/features/library/crop_corners.dart`.

Add four normalized edge points to the existing class (keep the name to avoid churn across repository, viewer, warper, overlay):

```
final Offset topLeft, topRight, bottomRight, bottomLeft;   // existing
final Offset topMid, rightMid, bottomMid, leftMid;         // NEW
```

- **Defaults:** each `*Mid` defaults to the **geometric center** of its edge (`topMid = (topLeft+topRight)/2`, etc.). A constructor that omits midpoints (or a `CropCorners.corners(...)` named ctor) fills centered midpoints, so all existing call sites keep compiling and produce straight edges.
- `fullFrame`: corners at the image bounds, midpoints centered → straight, full image. Warp no-op sentinel unchanged.
- **Edge → curve mapping (role order):** `topMid` bends TL↔TR, `rightMid` bends TR↔BR, `bottomMid` bends BR↔BL, `leftMid` bends BL↔TL.
- `isStraight` getter: true when every `*Mid` equals its edge center (within an epsilon). Drives the hybrid warp choice.
- `clamp()`: clamps all 8 points to `[0,1]`.
- `==`/`hashCode`/`toString`: include the 4 midpoints.

### Persistence (backward compatible)

- `toStorage()` → **16** fixed-precision numbers, role order `TL,TR,BR,BL,topMid,rightMid,bottomMid,leftMid`.
- `tryParse(s)`:
  - **16 numbers** → full 8-point shape.
  - **8 numbers** (legacy) → 4 corners + centered midpoints (straight). Preserves every already-saved document.
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
4. Output size: `outW = max(arc-length(top), arc-length(bottom))`, `outH = max(arc-length(left), arc-length(right))`, rounded; guard `< 2px` → `WarpException`.
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
- **Corner drag:** unchanged — moves that corner; adjacent midpoints keep their *absolute* positions unless centered (centered midpoints track the edge center so straight edges stay straight until deliberately bent). Exact tracking rule finalized in the plan; default is "centered midpoints stay centered, bent midpoints stay put."
- **Midpoint drag:** moves only that point → bends its edge. Per-point clamp to `[0,1]`.
- **Edge rendering:** `_QuadPainter` draws each edge via `Path.quadraticBezierTo(control, endCorner)` using the derived control point; the dim-outside mask uses the same curved path so the darkened region hugs the curve.
- `highlightColor`, `enabled`, scaling/letterbox math: unchanged.

## Testing (TDD)

**Host (`flutter test`):**
- `CropCorners`: centered-midpoint defaults; `isStraight`; `toStorage`/`tryParse` round-trip for **both** 8- and 16-number forms; legacy 8→straight; fail-soft cases.
- `CoonsWarper` (pure Dart, runs on host): straight-edge input ≈ homography/identity on a synthetic rect; a known **bowed** fixture unwarps to a straight-edged rectangle (assert edge straightness / corner mapping); degenerate quad → `WarpException`.
- Hybrid dispatch: `fullFrame`→null, straight→perspective path, bent→coons path (inject fakes to assert which runs).
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

- **Corner-drag ↔ midpoint tracking** interaction (does a centered midpoint follow its moving corner?) — resolved to "centered stays centered, bent stays put"; revisit if UX feels off on device.
- **Coons self-fold** at extreme bends — clamp handle range and reject folded patches; acceptable because the repository degrades gracefully (keeps original on warp failure).
- Bilinear-vs-perspective difference is deliberately avoided by the hybrid split.
