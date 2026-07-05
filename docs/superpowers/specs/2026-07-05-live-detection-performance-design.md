# Live Document Detection — Performance (Feature B)

**Date:** 2026-07-05
**Status:** Design approved, pending implementation plan
**Feature group:** Auto-crop (B → A → C). This spec covers **B only**: making live
detection fast enough for a smooth overlay and, downstream, confident auto-capture (A).

## Problem

The live document-edge overlay is laggy. The current live path has four
performance sinks:

1. **700ms throttle** (`_kMinSampleGapMs` in `PluginCameraPreviewController`) caps
   the overlay at ~1.4 fps — a band-aid for a slow pipeline.
2. **Camera streams at `ResolutionPreset.ultraHigh` (~2160p / ~8 MP)**. Each frame
   is ~12 MB (YUV420) or ~33 MB (BGRA8888).
3. **`compute()` copies the entire full-resolution frame across the isolate
   boundary on every frame.**
4. **Full-resolution color conversion before downscale**: the isolate converts the
   whole 8 MP frame YUV/BGRA → BGR → GRAY, *then* resizes to 1024px. For YUV the
   Y-plane is already luminance, so the color work is pure waste.

## Goal & non-goals

**Goal:** Smooth live overlay (~5-8 fps) by cutting per-frame copy and CPU.
Low-risk — keep `compute()`-per-frame; no long-lived isolate worker.

**Non-goals (YAGNI):**
- Long-lived isolate worker / near-real-time (~15-30 fps) rework — explicitly not chosen.
- Box tightness / detection *accuracy* improvements — a separate concern, not this
  feature's failure mode.
- Camera-level stream-vs-still resolution split — needs platform-channel work, not low-risk.
- Auto-capture (feature A) — its own spec.

**Success criteria:**
- Live overlay visibly smoother on-device (~5-8 fps), verified by a debug timing log
  around `detectFrame` on RZCY51D0T1K.
- Still-capture detection (`detect(bytes)` at 1024px) unchanged — Accept-time crop
  accuracy is not affected.
- Detector's synthetic-probe outcomes (null/non-null + polarity) unchanged at the new
  coarse live working size.

## Approach: "shrink at the source", reduction internal to `detectFrame`

Reduce each camera frame to a tiny single-channel grayscale buffer **on the main
isolate, inside `detectFrame`, before the `compute()` hop**. The live segmentation
then skips color conversion and full-resolution resize, and the cross-isolate copy
drops from 8-33 MB to ~160 KB.

```
detectFrame(CameraFrame frame)
  → reduceToGray(frame, maxSide: kLiveDetectMaxSide)   // main isolate, ~sub-ms
  → compute(_segmentGrayFrame, grayFrame)              // ~160 KB crosses the boundary
  → _segmentGray(CV_8UC1 Mat)                           // blur → dual-Otsu → close → contour → quad → score
```

Live is a **guide only** — the overlay shows "a page is here"; the precise corners
still come from the full-resolution `detect(bytes)` at Accept time. So a coarser live
working size is acceptable (confirmed with product owner).

### Why reduction is internal to `detectFrame` (not at the `startSampling` seam)

Perf is identical whether the reduction runs inside `PluginCameraPreviewController`
or inside `detectFrame` — both are on the main isolate, both before `compute()`.
Placing it *inside `detectFrame`* keeps every public seam unchanged:
`detectFrame(CameraFrame)`, `startSampling(void Function(CameraFrame))`, and
`camera_screen._onFrame(CameraFrame)` all keep their signatures, so both test fakes,
all F3/BDD tests, and the detector's existing frame tests need no migration.
`reduceToGray` is still a **public top-level pure function** in its own file, so it is
directly host-testable — we keep the host-coverage win without any forced churn.

## Components

### New

1. **`lib/features/scan/gray_frame.dart` — `GrayFrame`**
   Immutable value type: `{int width, int height, Uint8List bytes}` — tightly-packed
   8-bit single channel (`width * height` bytes, no row padding). Small (~400px
   longest side). `compute()`-transferable (ints + `Uint8List`).

2. **`lib/features/scan/frame_reducer.dart` — `reduceToGray(CameraFrame, {int maxSide})`**
   Pure Dart, no OpenCV — **host-testable**.
   - Decimation factor `k = max(1, ((longest + maxSide - 1) ~/ maxSide))` (ceil), same
     factor on both axes to preserve aspect ratio (normalized corners map back correctly).
   - Output dims: `outW = (width + k - 1) ~/ k`, `outH = (height + k - 1) ~/ k` (nearest-
     neighbor decimation, sampling column/row `i*k`).
   - **YUV420:** read plane 0 (Y = luminance). Honor `bytesPerRow` for row addressing
     and `bytesPerPixel` (Y pixel stride, default 1) for column addressing.
   - **BGRA8888:** integer-weighted luminance from the single plane
     (`y = (77*R + 150*G + 29*B) >> 8`, BGRA byte order), honoring `bytesPerRow`.
   - If the frame is already ≤ `maxSide` (`k == 1`), copy through tightly (no upscale).

### Changed

3. **`lib/features/scan/opencv_edge_detector.dart`**
   - `detectFrame(CameraFrame frame)` (signature **unchanged**): call
     `reduceToGray(frame, maxSide: kLiveDetectMaxSide)`, then `compute()` a new
     top-level `_segmentGrayFrame(GrayFrame)` isolate entry that wraps the gray bytes as
     a `CV_8UC1` Mat and calls `_segmentGray`. Keep the existing `.timeout(timeout)` guard.
   - **Remove** `_runFramePipeline`, `_bgrMatFromFrame`, `_bgrFromBgra`, `_bgrFromYuv420`,
     `_computeFrameRunner` — dead once the frame path is gray.
   - **Refactor** `_runPipelineOnMat` into a shared `_segmentGray(cv.Mat gray, rows, cols)`
     holding steps 4-7 (blur → dual-Otsu → close → largest contour → quad → plausibility
     guard → confidence, keep best polarity). Two front-ends feed it:
     - *Still* (`detect(bytes)`, unchanged behavior): decode → resize to `_kDetectMaxSide`
       (1024) → `BGR2GRAY` → `_segmentGray`.
     - *Live* (`_segmentGrayFrame`): `GrayFrame` bytes → `CV_8UC1` Mat → `_segmentGray`
       (no resize — already small; no `cvtColor` — already gray).
   - **New constant** `const int kLiveDetectMaxSide = 400;` (public — shared with tests).
     Keep `_kDetectMaxSide = 1024` for the still path.

4. **`lib/features/scan/camera_preview_controller_impl.dart`**
   - Lower `_kMinSampleGapMs` from `700` to `150`. Safe because `camera_screen._onFrame`
     already drops frames while a detection is in flight (`_isDetecting`), preventing
     stacking. No new backpressure needed.

### Unchanged (verified)

- `EdgeDetector` interface, `CameraPreviewController` interface, `camera_screen._onFrame`,
  both test fakes (`FakeEdgeDetector`, `FakeCameraPreviewController`), and all existing
  F3/BDD frame tests keep their `CameraFrame` signatures.
- Still-capture `detect(bytes)` behavior and its 1024px working size.

## Data flow

```
camera stream (8 MP CameraFrame)
  → [main isolate] detectFrame → reduceToGray (k≈10 for 3840px → ~384×216, ~83K samples, sub-ms)
  → GrayFrame (~160 KB)
  → compute() copy
  → [worker isolate] CV_8UC1 Mat → _segmentGray → flat [8 corners + confidence] or null
  → camera_screen: show overlay if confidence ≥ 0.5 (unchanged threshold)
```

## Testing (TDD)

**Host unit tests (the bulk — fully host-runnable, no libdartcv):**
- `frame_reducer_test.dart` — `reduceToGray`:
  - decimation factor for representative sizes (e.g. 3840→k=10, 1920→k=5, ≤400→k=1);
  - output dims and aspect preserved;
  - YUV Y-plane extraction with non-trivial `bytesPerRow` (row padding) and
    `bytesPerPixel > 1` (interleaved Y stride);
  - BGRA luminance correctness (known B/G/R → expected Y) and `bytesPerRow` padding;
  - already-small frame (`k == 1`) copies through, no upscale;
  - edge cases: 1×1, odd dimensions.
- `gray_frame_test.dart` — value type (dims, byte length invariants).

**Probe presence-guard (`apps/mobile/tool/detect_probe.py`):**
- Extend to run each synthetic case at **both** 1024 and 400px working sizes and assert
  the same null/non-null outcome and polarity — guards that the coarse working size does
  not regress detection *presence* on the fixtures.
- **Caveat — this is an approximation, not a mirror of the live path.** The probe
  downscales via `cv2.resize(BGR, INTER_AREA)` then `cvtColor→GRAY`; the live path does
  nearest-neighbor Y-plane decimation straight to gray. So the probe validates that the
  guards (5%-area, 0.55-fill, polarity) still admit the page at ~400px, **not** that the
  exact live pixels match. Bit-level correctness of the decimation itself is covered by
  the host `reduceToGray` tests; overall live behaviour is confirmed by the on-device
  eyeball. Consistent with the probe's existing self-described role (presence/polarity,
  not exact values).

**Existing tests:** `opencv_edge_detector_detectframe_test.dart`,
`opencv_edge_detector_yuv_test.dart`, F3/BDD frame tests — unchanged (still build
`CameraFrame`, still host-skip-guarded where libdartcv is required). Their BGRA/YUV
fixture builders (`brightRectBgra`, the YUV builder) may be reused to feed the new
`reduceToGray` host tests.

**On-device (deferred, tracked as an open gap like the flash/strobe work):**
- Debug-only timing log around `detectFrame` to confirm ~5-8 fps.
- Eyeball live-overlay smoothness on RZCY51D0T1K.

## Migration / blast radius

- **New:** `gray_frame.dart`, `frame_reducer.dart`, their host tests, probe-parity
  extension.
- **Rewrite internals of:** `opencv_edge_detector.dart` (remove 5 frame/BGR helpers,
  add `reduceToGray` call + `_segmentGray` refactor + `kLiveDetectMaxSide`).
- **One-line change:** `camera_preview_controller_impl.dart` throttle constant.
- **No interface, fake, or existing-test signature changes.**

## Open questions / risks

- **Coarse-size detection presence:** at 400px, the `kseg = cols/30` close kernel is
  ~13px and the 5%-area / 0.55-fill guards must still admit a real page. Probe parity at
  400px is the guard; if a fixture regresses, bump `kLiveDetectMaxSide` (e.g. to 480-512)
  — a single constant, no structural change.
- **Nearest-neighbor decimation aliasing** on noisy sensor data is mitigated by the
  existing Gaussian blur (kernel 7) applied inside `_segmentGray`.
