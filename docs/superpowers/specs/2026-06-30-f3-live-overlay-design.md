# F3 Live Camera Edge Overlay — Implementation Design

**Date:** 2026-06-30
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** F1 (OpenCvEdgeDetector, EdgeDetector interface), F2 (ScanDependencies EdgeDetectorFactory, CropOverlay highlightColor)
**Step in roadmap:** F3 — live overlay in camera preview (stretch)

## Purpose

Show a live green quad outline on the camera preview while the user frames a
document, giving immediate visual confirmation that the scanner has found
document edges before they tap the shutter. The overlay updates periodically
via a throttled sampling loop — not every frame — to keep the UI smooth.

Auto-capture (firing the shutter automatically when confident) is explicitly
**out of scope** for this step.

## Architecture

A `Timer.periodic` in `CameraScreen` drives the detection loop:

1. Every 800 ms the timer calls `sampleFrame()` on the `CameraPreviewController`
2. `sampleFrame()` calls `takePicture()` internally, reads the JPEG bytes, deletes the temp file, and returns `Uint8List?` (null on any error)
3. The bytes are passed to the existing `EdgeDetector.detect()` — interface unchanged
4. If the result's confidence is ≥ 0.5 the screen stores it as `_liveResult`; otherwise `_liveResult` is set to null (no overlay — option A)
5. `CameraPreviewView` renders a `LiveQuadOverlay` widget (green quad, no handles) stacked over the preview when `_liveResult` is non-null

`EdgeDetector` interface is **unchanged**. No image-stream or format-conversion
work is required: `sampleFrame()` produces JPEG bytes via the same
`takePicture()` path already used for the still capture (F1/F2), so OpenCV
receives data in the format it already handles correctly.

## Scope boundary

- Scan screen (`CameraScreen`, `CameraPreviewView`) only
- Review screen (`CaptureReviewScreen`, `CropOverlay`) is untouched
- No auto-capture, no stability check, no frame streaming

## Components

### New: `lib/features/scan/widgets/live_quad_overlay.dart`

`LiveQuadOverlay extends StatelessWidget`

| Prop | Type | Notes |
|------|------|-------|
| `corners` | `CropCorners` | normalized [0..1], from `DetectionResult.corners` |
| `previewSize` | `Size` | camera native resolution (after orientation swap) |
| `color` | `Color` | always `Colors.green` at call site |

Internally: `LayoutBuilder` → fitted-rect math (same formula as `CropOverlay`)
→ `CustomPaint` with a private `_LiveQuadPainter` that draws four stroked
lines forming the quad. No fill, no handles, no gesture detection. Widget
carries `const Key('live-quad-overlay')` for stable test finders.

The fitted-rect formula (identical to `CropOverlay`):
```
scale  = min(box.width / previewSize.width, box.height / previewSize.height)
display = previewSize * scale
rect   = Offset((box.width − display.width) / 2,
                (box.height − display.height) / 2) & display
pixelOf(n) = rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height)
```

### Modified: `lib/features/scan/camera_preview_controller.dart`

Two new abstract members added to the interface:

```dart
/// Returns JPEG bytes of a sampled still frame, or null on any error.
/// Only valid after [initialize()] succeeds. Never throws.
Future<Uint8List?> sampleFrame();

/// Native camera resolution after [initialize()]. Width and height are
/// already swapped when sensor orientation is 90° or 270°, so this always
/// reflects the display-space dimensions.
Size get previewSize;
```

### Modified: `lib/features/scan/camera_preview_controller_impl.dart`

**`sampleFrame()`**
```dart
Future<Uint8List?> sampleFrame() async {
  try {
    final file = await _controller!.takePicture();
    final bytes = await File(file.path).readAsBytes();
    await File(file.path).delete();
    return bytes;
  } catch (_) {
    return null;
  }
}
```

**`previewSize`** — swaps dimensions when sensor orientation is 90° or 270°:
```dart
Size get previewSize {
  final size = _controller!.value.previewSize;
  final rot  = _controller!.description.sensorOrientation;
  return (rot == 90 || rot == 270) ? Size(size.height, size.width) : size;
}
```

### Modified: `lib/features/scan/widgets/camera_preview_view.dart`

Two optional params added:

```dart
final CropCorners? liveCorners;  // non-null only when confidence ≥ 0.5
final Size? previewSize;
```

`CameraScreen` does the confidence filter and passes `_liveResult?.corners`
(null when result is absent or low-confidence). `CameraPreviewView` stays
decoupled from `DetectionResult`. When both params are non-null, `LiveQuadOverlay`
is inserted into the Stack between the camera preview and the shutter button,
wrapped in `IgnorePointer` so touch events pass through to the shutter button:

```
Stack:
  Center(child: controller.buildPreview())   ← bottom
  IgnorePointer(child: LiveQuadOverlay(...)) ← middle (only when liveCorners != null)
  Positioned(bottom: 32, child: shutter)     ← top
```

### Modified: `lib/features/scan/camera_screen.dart`

New state fields:
```dart
Timer? _sampleTimer;
DetectionResult? _liveResult;
bool _isSampling = false;
```

**`_startSampleTimer()`**
```dart
void _startSampleTimer() {
  _sampleTimer = Timer.periodic(
    const Duration(milliseconds: 800),
    (_) => unawaited(_doSample()),
  );
}
```

**`_doSample()`** — guards against overlap and race with user shutter:
```dart
Future<void> _doSample() async {
  if (_isSampling ||
      _controller.capturing ||
      _controller.status != ScanStatus.ready) return;
  _isSampling = true;
  try {
    final bytes = await _controller.preview.sampleFrame();
    if (!mounted || bytes == null) return;
    final result = await _edgeDetector.detect(bytes);
    if (!mounted) return;
    setState(() {
      _liveResult =
          (result != null && result.confidence >= 0.5) ? result : null;
    });
  } finally {
    _isSampling = false;
  }
}
```

**`initState()`** — starts the timer (callback guards non-ready status):
```dart
_sampleTimer = Timer.periodic(...); // via _startSampleTimer()
```

**`dispose()`** — cancels the timer:
```dart
_sampleTimer?.cancel();
```

**`_onShutter()`** — pauses detection during the review screen, restarts on return:
```dart
Future<void> _onShutter() async {
  _sampleTimer?.cancel();
  _sampleTimer = null;
  // ... existing push logic ...
  await navigator.push(...);
  if (mounted && _controller.status == ScanStatus.ready) {
    _startSampleTimer();
  }
}
```

**`build()` — ready branch** passes overlay data down:
```dart
case ScanStatus.ready:
  return CameraPreviewView(
    key: const Key('scan-preview'),
    controller: _controller.preview,
    capturing: _controller.capturing,
    onShutter: _onShutter,
    liveCorners: _liveResult?.corners,
    previewSize: _controller.preview.previewSize,
  );
```

### Modified: `test/support/fake_scan.dart`

**`FakeCameraPreviewController`** gains:
```dart
final Uint8List? sampleFrameResult;
int sampleFrameCalls = 0;

@override
Future<Uint8List?> sampleFrame() async {
  sampleFrameCalls++;
  return sampleFrameResult;
}

@override
Size get previewSize => const Size(1920, 1080);
```

**New factory helper:**
```dart
/// [ScanDependencies] with controllable frame sampling and edge detection.
/// Use in F3 widget and BDD tests.
ScanDependencies liveDetectionScanDependencies({
  required DetectionResult? detectionResult,
  Uint8List? sampleFrameResult,
}) =>
    ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController(
        sampleFrameResult: sampleFrameResult ?? kFakeJpegBytes,
      ),
      createEdgeDetector: () => FakeEdgeDetector(result: detectionResult),
    );
```

## BDD scenarios

**Feature file:** `integration_test/f3_live_overlay.feature`
**Generated test:** `integration_test/f3_live_overlay_test.dart` (build_runner)
**Step defs:** `test/step/`

```gherkin
Feature: F3 live edge overlay in camera preview

  Scenario: Document detected — green outline appears
    Given the camera is ready with a detector returning confident corners
    When the live overlay sample timer fires
    Then the live quad overlay is visible on the camera preview

  Scenario: No document detected — no outline shown
    Given the camera is ready with a detector returning no result
    When the live overlay sample timer fires
    Then no live quad overlay is visible on the camera preview
```

Step definitions needed (new files in `test/step/`):
- `the_camera_is_ready_with_a_detector_returning_confident_corners.dart`
- `the_camera_is_ready_with_a_detector_returning_no_result.dart`
- `the_live_overlay_sample_timer_fires.dart` — pumps `Duration(milliseconds: 900)`
- `the_live_quad_overlay_is_visible_on_the_camera_preview.dart` — `find.byKey(Key('live-quad-overlay'))`
- `no_live_quad_overlay_is_visible_on_the_camera_preview.dart` — `findsNothing`

## Testing strategy

| Layer | What is tested |
|-------|---------------|
| Widget: `LiveQuadOverlay` | Renders quad lines at correct screen positions for known corners + previewSize; invisible quad when no widget is built |
| Widget: `CameraPreviewView` | Overlay present when `liveCorners` non-null; absent when null; shutter button still tappable (IgnorePointer) |
| Widget: `CameraScreen` | After `pump(900ms)` with `liveDetectionScanDependencies(confident result)` → overlay visible; with null result → overlay absent |
| Widget: `CameraScreen` | `sampleFrame` not called while `_controller.capturing` is true |
| BDD integration | Both scenarios above, on-device with fakes |
| Static | `EdgeDetector` interface unchanged; `LiveQuadOverlay` file exists; `Key('live-quad-overlay')` present |

## Verify script

`scripts/verify/f3.sh` — follows the lib.sh pattern:
- Static assertions (file presence, interface, key, sensor-rotation logic)
- OpenCV host library setup (same as b3.sh / f2.sh pattern)
- `pnpm nx run mobile:test` — all host tests pass
- `pnpm nx run mobile:analyze` — clean
- Coverage floor: 70%
- Device gate: BDD integration test (skippable with `VERIFY_SKIP_DEVICE=1`)

## Deliverable (user-testable)

A live green quadrilateral outline on the camera preview that tracks document
edges as the user moves the phone. When no confident document is found the
preview is clean — no overlay.

**You can test it by:**
1. Open the Scan screen and point the camera at a flat document on a
   contrasting background — a green outline should appear around the document
   edges within ~1 second and update as you move the phone.
2. Point the camera at a blank wall or a cluttered scene — the outline should
   disappear; no error, no flash.
3. Tap the shutter — the overlay freezes (timer paused), the review screen
   opens normally, and when you return the overlay resumes.

## Acceptance criteria

- [ ] A green quad outline appears on the camera preview within 800 ms when
      `EdgeDetector` returns confidence ≥ 0.5 — *widget: CameraScreen timer*
- [ ] No overlay is shown when detection returns null or confidence < 0.5
      — *widget: CameraScreen timer*
- [ ] Overlay is non-interactive: shutter button remains tappable through it
      — *widget: CameraPreviewView IgnorePointer*
- [ ] Corner positions are correctly mapped to screen pixels accounting for
      camera aspect-ratio letterboxing (fitted-rect math) — *widget: LiveQuadOverlay*
- [ ] `previewSize` swaps width/height when sensor orientation is 90° or 270°
      — *widget / device: PluginCameraPreviewController*
- [ ] Sampling does not race with the user's shutter tap (`_isSampling` +
      `_controller.capturing` guards) — *widget: CameraScreen*
- [ ] Timer is paused while the review screen is active and resumes on return
      — *widget: CameraScreen _onShutter*
- [ ] `EdgeDetector` interface is unchanged from F1 — *static assertion*
- [ ] BDD: document detected → outline visible — *integration*
- [ ] BDD: no document → no outline — *integration*
- [ ] All host tests pass; analyze clean; coverage ≥ 70% — *verify script*

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, this feature is
> not done until every acceptance criterion above maps to a passing test (TDD:
> unit/widget first; BDD for user-facing behavior), the full suite is run and
> observed green, quality gates pass, and the work is reviewed and
> double-checked. "Looks right" / "should pass" is not done.
