# Native OpenCV Page Pipeline — Design

**Status:** Approved (design), pending spec review
**Date:** 2026-07-03
**Sub-project:** 1 of 2 (native pipeline). Sub-project 2 (background/non-blocking
processing) is a separate later spec.

## Problem

Saving one cropped page takes ~5 s on the target device (Samsung SM A166B,
RZCY51D0T1K). Profiling proved the entire cost is the pure-Dart
`package:image` warp + Auto-filter running on the full ~19 MP capture, with
JPEG decode (~2 s) as an unbreakable floor (pure Dart cannot decode at reduced
scale). A device spike of the same pipeline on the already-shipped `dartcv`
(OpenCV) binding measured **247 ms @ 12 MP, 323 ms @ 27 MP, 472 ms @ 50 MP** —
a ~15× win, because native `imdecode` (libjpeg-turbo) is 55–200 ms and
`warpPerspective` is SIMD/multi-threaded. This spec ports the page-processing
pipeline to native OpenCV, keeping the pure-Dart pipeline as a fallback.

## Goal

Replace the CPU-heavy warp + enhance in the save path with a native OpenCV
pipeline that is byte-for-byte quality-equivalent to today's output, falling
back to the existing pure-Dart pipeline on any native failure. Target: cropped
Auto save drops from ~5 s to <1 s per page.

## Non-goals

- Background / non-blocking processing (separate sub-project 2).
- Changing the camera capture resolution, the detector, the crop UI, the filter
  set, or any stored-file layout / DB schema.
- Changing the ~3500 px flat-output cap (already shipped) — the native warp
  applies the same cap.

## Global constraints

- **Quality parity:** native output must match the current Dart output — mean
  abs pixel diff well under ~1/255 for Auto (JPEG-recompression noise aside),
  visually identical for Color/Grayscale. This is a gate.
- **Never lose a page:** every save produces a stored, correctly-processed page,
  via fallback if native fails.
- **No UI/public-API change:** the UI keeps passing an `ImageEnhancer`; the
  repository maps it to an `EnhancerMode` internally.
- **Flat long side capped at `kDefaultFlatMaxDimension` (3500).**
- **Native runs in a `compute()` isolate with a timeout guard** (mirrors
  `OpenCvEdgeDetector`, 5 s) — a wedged native isolate cannot be killed from
  Dart, so the timeout is the recovery mechanism.
- **Strict Mat dispose discipline** in `finally` (two-tier, as in
  `opencv_edge_detector.dart`).
- Package: dartcv via `package:opencv_dart/opencv_dart.dart as cv` (already a
  dependency).

## Architecture

### The `PageProcessor` seam

```dart
abstract interface class PageProcessor {
  /// Full processed JPEG for one page: decode → (warp if cropped) →
  /// filter(mode) → encode. Returns null when there is nothing to do
  /// (mode == none && corners == fullFrame), so the caller stores the
  /// scrubbed bytes verbatim. Never throws.
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode);
}
```

Implementations:

1. **`NativePageProcessor`** — dartcv pipeline in a `compute()` isolate with a
   timeout guard. Returns null on any failure (corrupt decode, op error,
   timeout) so the fallback engages.
2. **`DartPageProcessor`** — thin wrapper over the existing shipped logic: the
   fused `warpAndEnhance` for cropped pages and the `ImageEnhancer` cores for
   full-frame. No behavior change; this is the current pipeline behind the new
   interface.
3. **`FallbackPageProcessor`** — `{primary: NativePageProcessor,
   fallback: DartPageProcessor}`. Calls primary; if it returns null *due to
   failure* (not the legitimate none+fullFrame null), runs fallback. Production
   injects this.

The legitimate "nothing to do" null (none + full frame) must be distinguished
from a failure null so the fallback is not pointlessly invoked and so the caller
still gets the correct passthrough behavior. `FallbackPageProcessor` resolves
this by short-circuiting that case itself: if `mode == none && corners ==
fullFrame`, return null immediately without calling either engine.

### Repository integration

`DriftDocumentRepository` gains a `PageProcessor` dependency (default in
production DI: `FallbackPageProcessor`). Both heavy call sites route through it:

- **Full-frame enhance** (currently `enhancer.enhance(scrubbed)` for the stored
  original when `isFullFrame`): replaced by
  `_processor.process(scrubbed, fullFrame, mode)`. Null → store scrubbed
  verbatim.
- **Cropped flat** (`_enhancedFlat`, currently the fused `warpAndEnhance` +
  two-step fallback): replaced by `_processor.process(scrubbed, corners, mode)`.
  On null (native+dart both failed) → keep the existing final fallback (store
  the scrubbed/warped-unenhanced base) so a page is never lost.

`enhancerModeOf(ImageEnhancer?)` (already exists in `warp_enhancer.dart`) maps
the injected enhancer to a mode. The existing `_warper` field, the
Perspective/Coons warpers, and the Dart enhancer classes remain — they are the
Dart fallback path inside `DartPageProcessor`.

The repository's other, non-critical warp call sites (`updateCrop` at ~L450,
`replacePage` at ~L656) are out of scope for this spec; they keep using the
existing (now buffer-fast) Dart warpers. They can adopt `PageProcessor` in a
later change if desired.

## Native filter mapping (quality parity)

Each Dart step of the Auto flat-field has an exact OpenCV equivalent:

| Dart step | Native OpenCV | Parity |
|---|---|---|
| proxy downscale (512 long side, average) | `cv.resize(INTER_AREA)` | exact intent |
| per-channel max-filter radius 7 | `cv.dilate`, 15×15 `MORPH_RECT` kernel | exact (2·7+1 = 15) |
| gaussian blur radius 12 | `cv.gaussianBlur`, sigma matched to radius | matched |
| upscale to full (bilinear) | `cv.resize(INTER_LINEAR)` | exact intent |
| flatten `px·min(255/bg, 6.0)` | `cv.divide(px, cv.max(bg, 255/6), scale: 255)` | **exact** — flooring bg at 255/6 ≈ 42.5 is algebraically the gain cap |
| white-point stretch (1% clip, 0.55 black anchor, linear) | per-channel `cv.calcHist` → build LUT with the same integer formula → `cv.LUT` | exact |

Constants (`_kProxyLongSide`, `_kDilateRadius`, `_kBlurRadius`, `_kWhiteClip`,
`_kBlackAnchor`, `_kMaxGain`) are reused verbatim from `auto_enhancer.dart` so
the two pipelines stay in lockstep.

- **Warp:** src quad (corners × image size) → dst rect (capped ≤3500) via
  `cv.getPerspectiveTransform2f` + `cv.warpPerspective(INTER_LINEAR)`. Native
  handles **straight crops only** (`corners.isStraight`). A **bent crop**
  (`!corners.isStraight`) needs the Coons bent-edge warp, which
  `warpPerspective` cannot reproduce, so `NativePageProcessor` returns null for
  bent crops and the **Dart Coons fallback** runs (still fast — buffer-based).
  This keeps scope tight and removes any Coons parity risk. Full-frame (no warp)
  and straight crops — the overwhelming majority — take the native path.
- **Color:** `adjustColor(contrast: 1.1, brightness: 1.05)` → a matched
  contrast/brightness LUT applied with `cv.LUT`; verified visually.
- **Grayscale:** `cv.cvtColor(COLOR_BGR2GRAY)` (standard luma), re-expanded to
  3-channel for a normal JPEG; visually equivalent to `img.grayscale`.
- **Encode:** `cv.imencode('.jpg', mat, params:[IMWRITE_JPEG_QUALITY, q])`,
  q = 95 for Auto, 92 otherwise (matches current).

## Failure handling

Ordered ladder — the first that succeeds wins; a page is never lost:

1. `imdecode` returns empty (corrupt bytes) → native returns null → Dart
   fallback runs.
2. Any native op throws / fails → caught, Mats disposed in `finally`, native
   returns null → Dart fallback runs.
3. Native wedges → `compute(...).timeout(5 s)` fires → treated as null → Dart
   fallback runs.
4. Dart fallback itself fails → existing repository behavior: store the
   scrubbed original (full-frame) or the warped/un-enhanced base (cropped).

All boundaries never throw to the caller; failures degrade to a slower-but-
correct result.

## Testing strategy

- **Host (`flutter test`):**
  - `FallbackPageProcessor` orchestration with a fake native processor forced to
    return null / throw / delay-past-timeout → assert the Dart fallback runs and
    the none+fullFrame short-circuit returns null without invoking either engine.
  - `DartPageProcessor` produces the same bytes as the current path (guards the
    fallback).
  - Existing geometry / enhancer-core / warper host tests stay green.
  - libdartcv cannot load on host, so `NativePageProcessor` internals are not
    unit-tested here (same constraint as `OpenCvEdgeDetector`).
- **Device (`integration_test`, RZCY51D0T1K):**
  - Timing: cropped Auto save < ~1 s at ≥12 MP.
  - Output long side ≤ 3500; valid decodable JPEG.
  - **Parity:** native vs Dart Auto output — mean abs pixel diff under threshold;
    Color/Grayscale sane.
  - Failure → fallback path exercised (feed corrupt bytes to native, assert a
    valid page still results via fallback).
  - On-device eyeball on a real capture (established dev loop).

## Rollout / verification

Build + install release on RZCY51D0T1K; capture a real page, crop, save; confirm
sub-second spinner and unchanged visual quality. Keep the Dart pipeline in place
permanently as the fallback.
