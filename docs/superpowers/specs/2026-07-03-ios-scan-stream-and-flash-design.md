# iOS Scan: Stream-based Live Detection + Flash Toggle — Design

**Status:** Approved (direction), pending spec review
**Date:** 2026-07-03
**Branch:** `fix/ios-scan-flash-strobe`

## Problem

On iOS the scan screen strobes the flash, visibly re-focuses/re-exposes, and
"takes many pictures" continuously while framing. A second symptom: at close
range the camera cannot lock focus.

On-device instrumentation (iPhone, iOS 18.7.8) proved the cause. The live
edge-detection loop samples frames by calling `CameraController.takePicture()`
on an 800 ms `Timer.periodic`. Measured, in steady state over 29 samples:

| Metric | Measured |
|---|---|
| camera config | `resolution=3840×2160` (4K/ultraHigh), `flashMode=auto`, `focusMode=auto`, `exposureMode=auto` |
| `takePicture()` cadence | every ~800 ms |
| cost per `takePicture()` | 325–590 ms, producing a 0.54–1.03 MB JPEG |
| effective rate | ~1.25 full 4K stills / second, indefinitely |

Each capture runs the full still pipeline: `FlashMode.auto` fires a metering
**preflash** (the strobing), `FocusMode.auto` re-runs **autofocus**, and
`ExposureMode.auto` re-meters exposure — every 0.8 s. An isolating test
(disabling the sample loop, rebuilt and verified on-device) removed **both** the
strobing and the close-focus failure, confirming a single root cause: the
`takePicture`-per-800 ms sampling loop thrashes the preview's continuous
autofocus and fires the flash. Close focus fails because near-focus takes the AF
motor longest to lock and the loop yanks it away before it settles.

## Goal

1. Replace live-detection sampling with `CameraController.startImageStream()`,
   which delivers preview frames with **no shutter, no flash, and no AF/AE
   re-trigger**. This eliminates the strobing and restores close-range focus
   while keeping the live document-outline feature working.
2. Add a user-controlled **three-state flash toggle** (Off / Torch / Flash) so
   the flash is only ever used deliberately.

## Non-goals

- Changing the **capture** path. The shutter still uses `takePicture()` at
  `ResolutionPreset.ultraHigh` for sharp final photos; only *live sampling*
  changes.
- Changing the detection algorithm. The OpenCV segmentation pipeline in
  `opencv_edge_detector.dart` is reused byte-for-byte; only how a `cv.Mat` is
  constructed for it changes.
- Changing stored-file layout, DB schema, crop UI, or filter set.
- Auto-focus point / tap-to-focus UI (possible later, not needed for this fix).

## Global constraints

- **No strobing, no AF thrash during preview** — verified on-device (iPhone,
  the device the bug was reported on). This is the acceptance gate.
- **Close focus works** — verified on-device at close range. Gate.
- **Live outline still functions** — the green quad still tracks the document
  from streamed frames.
- **DIP boundary stays plugin-agnostic** — the `camera` package type
  (`CameraImage`) must not leak across `CameraPreviewController`; the fake and
  the detector depend only on our own value types.
- **Host tests stay green**; new behavior that needs real camera hardware is
  verified on-device (this project's host suite skips `integration_test`).

## Design

### 1. Live sampling: `Timer` + `takePicture` → image stream

**Interface (`camera_preview_controller.dart`).** Replace
`Future<Uint8List?> sampleFrame()` with a start/stop streaming pair:

```dart
/// Begins delivering live preview frames to [onFrame]. No-op if already
/// sampling. Frames are plugin-agnostic [CameraFrame]s. Never throws.
void startSampling(void Function(CameraFrame frame) onFrame);

/// Stops live-frame delivery. Safe to call when not sampling.
void stopSampling();
```

**New value type (`camera_frame.dart`).** A plain, plugin-free description of
one preview frame, carrying exactly what the detector needs to build a `cv.Mat`:

```dart
enum CameraFrameFormat { bgra8888, yuv420 }

class CameraFramePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel; // null for chroma planes where N/A
  const CameraFramePlane(...);
}

class CameraFrame {
  final int width;
  final int height;
  final CameraFrameFormat format;
  final List<CameraFramePlane> planes; // 1 (BGRA) or 3 (YUV420)
  const CameraFrame(...);
}
```

**Production impl (`camera_preview_controller_impl.dart`).**
- Set `imageFormatGroup` on the `CameraController`: `bgra8888` on iOS,
  `yuv420` on Android (chosen per `Platform`), so the stream format is known.
- `startSampling` calls `controller.startImageStream((CameraImage img) {...})`,
  maps `CameraImage` → `CameraFrame`, and invokes `onFrame`.
- **Throttle + drop:** keep a `Stopwatch` and an in-flight flag; ignore a
  streamed frame if `< ~700 ms` since the last accepted one or if the previous
  detection is still running (mirrors today's `_isSampling` guard). This keeps
  detection cost bounded without the frame *backlog* growing.
- `stopSampling` calls `controller.stopImageStream()` (guarded so it is safe
  when not streaming).

**Capture coexistence.** iOS/`camera` does not reliably support
`takePicture()` while an image stream is active. The screen already stops
sampling before capturing; the new `_onShutter`/`_onImport` call
`stopSampling()` before `capture()` and `startSampling()` after returning to the
ready state — same lifecycle as today's `_sampleTimer` cancel/restart. This
sidesteps the constraint entirely.

### 2. Detector: raw-frame path sharing the existing pipeline

`opencv_edge_detector.dart`'s `_runPipeline(Uint8List)` currently starts with
`cv.imdecode(bytes, ...)`. Refactor so the segmentation body operates on a
already-built BGR `cv.Mat`:

- Extract `_runPipelineOnMat(cv.Mat bgr)` containing today's Steps 2–7
  (downscale, grayscale, blur, Otsu dual-polarity, contour→quad, score). No
  logic change.
- `detect(Uint8List bytes)` → `imdecode` → `_runPipelineOnMat`. (Unchanged
  behavior; still used by the capture-review path.)
- New `detectFrame(CameraFrame f)` builds a BGR `Mat` from raw planes:
  - **bgra8888 (iOS):** wrap the single plane as `CV_8UC4` then
    `cvtColor(BGRA2BGR)`.
  - **yuv420 (Android):** assemble planes and `cvtColor` from the appropriate
    YUV layout to BGR.
  then calls `_runPipelineOnMat`.
- `EdgeDetector` interface gains `Future<DetectionResult?> detectFrame(CameraFrame)`.
  Plane→Mat construction runs inside the existing `compute()` isolate with the
  same timeout guard as `detect`.

`CameraFrame` planes are `Uint8List` (isolate-transferable), so the frame record
crosses the `compute()` boundary cleanly.

### 3. Three-state flash toggle

**Boundary enum (`scan_flash_mode.dart`):** `enum ScanFlashMode { off, torch, flash }`.

**Interface:** add to `CameraPreviewController`:
```dart
Future<void> setFlashMode(ScanFlashMode mode); // never throws
```

**Impl mapping:**
- `off` → `controller.setFlashMode(FlashMode.off)`. Capture: off.
- `torch` → `controller.setFlashMode(FlashMode.torch)` immediately (LED on
  during preview + capture).
- `flash` → LED stays off during preview; `capture()` applies
  `FlashMode.always` around the single `takePicture()` (restoring the preview
  mode afterward), so the flash fires only at the moment of capture.

`capture()` therefore honors the currently selected `ScanFlashMode`.

**UI (`camera_preview_view.dart` + `camera_screen.dart`):** a cycling
`IconButton` positioned top-trailing, safe-area aware (mirrors the existing
shutter's `viewPadding` handling). Icons: `Icons.flash_off` /
`Icons.flashlight_on` / `Icons.flash_on`. Tapping cycles
Off→Torch→Flash→Off. Selected `ScanFlashMode` lives in `_CameraScreenState`,
passed down; `onFlashModeChanged` calls `controller.preview.setFlashMode`.
Default on entry: **Off**.

## Data flow (steady state, scanning)

```
startImageStream → CameraImage (BGRA/YUV, ~30fps)
  → impl throttle/drop (~1 per 700ms, skip if detect in-flight)
  → CameraFrame (planes+dims+format)
  → onFrame → EdgeDetector.detectFrame(frame)  [compute() isolate]
      → planes → cv.Mat(BGR) → _runPipelineOnMat → DetectionResult?
  → setState(_liveResult) → LiveQuadOverlay repaints
```
No `takePicture`, no file I/O, no flash, no AF re-trigger in this loop.

Shutter: `stopSampling()` → apply capture flash mode → `takePicture()` →
review → restart `startSampling()`.

## Error handling

- `startSampling`/`stopSampling`/`setFlashMode` never throw (swallow
  `CameraException`, matching the existing `sampleFrame` "never throws"
  contract). A failed frame map is dropped, not surfaced.
- `detectFrame` returns `null` on any decode/convert/timeout failure (same as
  `detect`), so the overlay simply shows no quad — never crashes the preview.
- If `startImageStream` fails to start, the preview still works; only the live
  outline is absent. Logged in debug builds.

## Testing

**Host (TDD, `flutter test`):**
- `CameraFrame`/format value-type construction.
- Detector: `detectFrame` on a synthetic BGRA frame of a known bright rectangle
  returns a plausible quad; on garbage returns `null`. (Parity spot-check
  vs `detect` on an encoded version of the same image.)
- `_runPipelineOnMat` refactor: existing `detect(bytes)` tests stay green
  (proves the extraction didn't change behavior).
- Fake controller updated to the streaming interface; F3 widget/BDD tests
  drive `startSampling`'s `onFrame` callback with a canned `CameraFrame` and
  assert the overlay appears — replacing today's `sampleFrame`-count assertions.
- Flash: tapping the toggle cycles `ScanFlashMode` and calls
  `setFlashMode` on the fake; capture uses the selected mode.

**On-device (iPhone — the reported device, and the Android RZCY51D0T1K):**
- Scan screen: no strobing, no AF pulsing; live green outline still tracks a
  document.
- Close-range: focus locks cleanly.
- Flash toggle: Off (dark) / Torch (LED steady during preview) / Flash (LED
  fires only at shutter). Captured photo reflects the chosen mode.
- Instrumentation confirms `startImageStream` is active and `takePicture` is
  **not** called during preview.

## Risks

- **YUV420 plane layout (Android)** varies (row/pixel stride, NV21 vs I420).
  Mitigation: pick `yuv420` group explicitly, validate the `cvtColor` code
  against a device frame; BGRA (iOS, the reported platform) is simpler and
  handled first.
- **`takePicture` while streaming** — mitigated by stop-before-capture (see
  Capture coexistence).
- **Detector input scale differs** — streamed frames are preview-resolution
  (smaller than 4K stills). Detection normalizes corners to [0..1] and already
  downscales, so this is fine and in fact cheaper; confidence threshold (0.5)
  re-checked on-device.

## Rollout

1. Land the fix behind the existing DI; keep debug instrumentation until
   on-device acceptance passes.
2. Remove all `[SCAN-DEBUG]` logging, the `_dbg*` fields, and the
   `_kDbgDisableSampleLoop` flag.
3. Verify host suite green + on-device acceptance (iPhone + Android), then merge
   `fix/ios-scan-flash-strobe`.
