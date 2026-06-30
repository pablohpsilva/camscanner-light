# F2 — Pre-fill Crop Corners from Auto-Detection

**Date:** 2026-06-30
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** F1 (EdgeDetector + DetectionResult); E1 (CropOverlay, CropCorners)
**Feeds:** F3 (live overlay, stretch)

## Purpose

Wire the `EdgeDetector` (F1) into the review screen so captured images open with
corners already placed on the detected document. A green overlay cue tells the
user detection succeeded; the default blue cue appears when it did not. The user
can always adjust or reset corners manually.

## Scope

**In scope**
- Run `EdgeDetector.detect()` on the captured JPEG inside
  `CaptureReviewScreen.initState()`, concurrently with the existing image-size
  decode.
- Pre-fill `_corners` from the detection result (any confidence level).
- Show a **green** overlay (handles + quad outline) when `confidence ≥ 0.5`;
  **blue** otherwise.
- Guard: if the user touches a handle **or taps Reset** before detection
  completes, the result is silently discarded — user intent is never overridden.
- Reset always restores `CropCorners.fullFrame` and sets `_userInteracted = true`
  so any in-flight detection is blocked; green cue persists after Reset (the
  image still has a document).
- Wire `EdgeDetector` through `ScanDependencies` → `CameraScreen` →
  `CaptureReviewScreen` (dependency injection via composition root).

**Out of scope**
- Live edge overlay in camera preview (F3, stretch).
- Auto-capture on high confidence (separate feature).
- Changing Reset to restore detected corners instead of full-frame.

## Architecture

### `scan_dependencies.dart` (modified)

Add `EdgeDetectorFactory` and a new field:

```dart
import 'edge_detector.dart';
import 'opencv_edge_detector.dart';

typedef EdgeDetectorFactory = EdgeDetector Function();

EdgeDetector _defaultEdgeDetector() => const OpenCvEdgeDetector();

class ScanDependencies {
  final CameraPermissionServiceFactory createPermissionService;
  final CameraPreviewControllerFactory createPreviewController;
  final EdgeDetectorFactory createEdgeDetector;            // NEW

  const ScanDependencies({
    this.createPermissionService = _defaultPermissionService,
    this.createPreviewController = _defaultPreviewController,
    this.createEdgeDetector = _defaultEdgeDetector,        // NEW
  });
}
```

### `camera_screen.dart` (modified)

Add `_edgeDetector` field, create it in `initState`, pass to `CaptureReviewScreen`:

```dart
late final EdgeDetector _edgeDetector;

@override
void initState() {
  super.initState();
  // ... existing _controller and _saveController setup ...
  _edgeDetector = widget.dependencies.createEdgeDetector();  // NEW
}
```

In `_onShutter`, pass to `CaptureReviewScreen`:

```dart
CaptureReviewScreen(
  image: image,
  edgeDetector: _edgeDetector,      // NEW
  saving: _saveController.saving,
  onRetake: navigator.pop,
  onAccept: (corners) => _onAccept(image, corners),
)
```

No dispose needed — `EdgeDetector` is stateless (`OpenCvEdgeDetector` is `const`).

### `capture_review_screen.dart` (modified)

**New constructor parameter:**

```dart
final EdgeDetector? edgeDetector;   // null → no detection, behaves as pre-F2
```

**New state fields:**

```dart
double? _detectionConfidence;   // null = pending or not run; ≥ 0 = result received
bool _userInteracted = false;   // true once user drags any handle
```

**`initState` — kick off detection concurrently:**

```dart
@override
void initState() {
  super.initState();
  widget.decodeImageSize(widget.image.path).then((size) {
    if (!mounted) return;
    setState(() => _imageSize = size);
  }).catchError((_) {});
  _runDetection();   // NEW — runs concurrently
}
```

**`_runDetection()`:**

```dart
Future<void> _runDetection() async {
  final detector = widget.edgeDetector;
  if (detector == null) return;
  try {
    final bytes = await File(widget.image.path).readAsBytes();
    final result = await detector.detect(bytes);
    if (!mounted || _userInteracted) return;
    if (result != null) {
      setState(() {
        _corners = result.corners;
        _detectionConfidence = result.confidence;
      });
    }
  } catch (_) {
    // Silent fallback — leave _corners as fullFrame, _detectionConfidence null.
  }
}
```

**`onCornersChanged` handler — set user-interacted guard:**

```dart
onCornersChanged: (c) => setState(() {
  _userInteracted = true;
  _corners = c;
}),
```

**`highlightColor` getter:**

```dart
Color get _highlightColor =>
    (_detectionConfidence ?? -1) >= 0.5 ? Colors.green : Colors.blue;
```

**Reset button — also sets guard:**

```dart
TextButton(
  key: const Key('crop-reset'),
  onPressed: canCrop
      ? () => setState(() {
            _userInteracted = true;         // block any in-flight detection
            _corners = CropCorners.fullFrame;
          })
      : null,
  child: const Text('Reset'),
),
```

**Pass to `CropOverlay`:**

```dart
CropOverlay(
  imageSize: size,
  image: _imageWidget(),
  corners: _corners,
  enabled: !widget.saving,
  highlightColor: _highlightColor,   // NEW
  onCornersChanged: (c) => setState(() {
    _userInteracted = true;
    _corners = c;
  }),
)
```

### `widgets/crop_overlay.dart` (modified)

**New constructor parameter** (default preserves all existing callers):

```dart
final Color highlightColor;

const CropOverlay({
  super.key,
  required this.imageSize,
  required this.image,
  required this.corners,
  required this.onCornersChanged,
  this.enabled = true,
  this.highlightColor = Colors.blue,    // NEW
});
```

**Propagate to `_DragHandle`** — add `highlightColor` parameter:

```dart
Widget buildHandle(String role, String label, Offset cornerNorm) {
  ...
  child: _DragHandle(
    key: Key('crop-handle-$role'),
    enabled: enabled,
    cornerNorm: cornerNorm,
    rectSize: rect.size,
    highlightColor: highlightColor,    // NEW
    onNewNorm: (n) => emitNew(role, n),
  ),
  ...
}
```

**`_DragHandle`** — add `highlightColor`, use for border:

```dart
final Color highlightColor;   // NEW constructor param

// In build():
decoration: BoxDecoration(
  color: Colors.white,
  shape: BoxShape.circle,
  border: Border.all(color: widget.highlightColor, width: 2),  // was Colors.blue
),
```

**`_QuadPainter`** — add `highlightColor`, use for quad outline:

```dart
_QuadPainter({required this.rect, required this.corners, required this.highlightColor})

// In paint():
..color = highlightColor   // was Colors.blue
```

Pass it from `CropOverlay.build()`:

```dart
CustomPaint(
  painter: _QuadPainter(
    rect: rect,
    corners: corners,
    highlightColor: highlightColor,   // NEW
  ),
),
```

## Data flow

```
CameraScreen._onShutter()
  capture() → CapturedImage(path)
  push CaptureReviewScreen(image: image, edgeDetector: _edgeDetector, ...)
    │
    └─ initState() kicks off concurrently:
         ┌─ decodeImageSize(path) ──────────────────────────────────────────┐
         │                                                                  ↓
         └─ _runDetection()                                        setState(_imageSize)
              File(path).readAsBytes()                                      │
              detector.detect(bytes)                                        ↓
              if !_userInteracted && result != null:           CropOverlay(corners, highlightColor)
                setState(_corners, _detectionConfidence)
```

## Confidence cue

| `_detectionConfidence` | `_highlightColor` | Visible cue |
|------------------------|-------------------|-------------|
| `null` (pending / no detection / error) | `Colors.blue` | Blue handles + outline |
| `≥ 0` but `< 0.5` | `Colors.blue` | Blue handles + outline |
| `≥ 0.5` | `Colors.green` | Green handles + outline |

## Error handling

All detection errors (file read failure, corrupt bytes, OpenCV exception) are
caught silently in `_runDetection`. The screen falls back to
`CropCorners.fullFrame` and blue overlay — identical to pre-F2 behavior. No
crash, no user-visible error message.

## Testing strategy

### Widget tests — `test/features/scan/capture_review_screen_test.dart`

All use `FakeEdgeDetector` from `test/support/fake_scan.dart`. A non-loadable
image path is used (existing convention — no real file I/O in host widget tests).
Override `decodeImageSize` to resolve synchronously. Pass `readBytes` injectable
(see note below) so `_runDetection` can be exercised without real file I/O.

> **Testability note:** `File(image.path).readAsBytes()` in `_runDetection`
> requires a real file for non-trivial bytes. In widget tests that need to
> exercise the detection branch, `CaptureReviewScreen` accepts an optional
> `Future<Uint8List> Function(String path) readBytes` injectable (default:
> `File(path).readAsBytes()`), mirroring the existing `decodeImageSize`
> injectable pattern. Pass a function returning `kFakeJpegBytes` in tests.

New constructor parameter:

```dart
final Future<Uint8List> Function(String path) readBytes;

const CaptureReviewScreen({
  ...
  this.readBytes = _defaultReadBytes,    // NEW
});

Future<Uint8List> _defaultReadBytes(String path) => File(path).readAsBytes();
```

Test cases:

- `detection result pre-fills corners` — `FakeEdgeDetector` returns a preset
  `DetectionResult`; after settle, Accept passes detected corners (not fullFrame)
- `confidence ≥ 0.5 → green overlay` — inspect
  `tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor == Colors.green`
- `null detection → full-frame corners, blue overlay` — `FakeEdgeDetector(result: null)`;
  verify `highlightColor == Colors.blue`
- `late result discarded after user drag` — fake detector completes via
  `Completer` after test drags a handle; complete the future; verify corners
  unchanged from user's drag
- `late result discarded after Reset` — fake detector completes via `Completer`
  after test taps Reset; complete the future; verify corners remain fullFrame
- `detection throws → full-frame fallback, no crash` — `FakeEdgeDetector`
  overridden to throw; expect no exception, `highlightColor == Colors.blue`

### Widget tests — `test/features/scan/widgets/crop_overlay_test.dart`

- `highlightColor Colors.green propagates to handle border` — render
  `CropOverlay(highlightColor: Colors.green, ...)`; find
  `Key('crop-handle-tl')`; verify the inner `Container`'s `BoxDecoration.border`
  is `Border.all(color: Colors.green, width: 2)`
- `highlightColor Colors.green propagates to quad painter` — render with
  `Colors.green`; find the `CustomPaint` in the overlay; cast its `painter` to
  `_QuadPainter` and assert `.highlightColor == Colors.green`
  (or, if private-class cast is unavailable, a `matchesGoldenFile` snapshot at
  small size to verify the outline color visually)
- `default highlightColor is Colors.blue` — existing tests continue to pass
  (no `highlightColor` argument → default `Colors.blue`)

### Unit tests — `test/features/scan/scan_dependencies_test.dart`

- `createEdgeDetector() returns OpenCvEdgeDetector` — verify
  `deps.createEdgeDetector() is OpenCvEdgeDetector`

### Widget / camera-screen tests — `test/features/scan/camera_screen_capture_test.dart`

- `_onShutter passes edgeDetector to CaptureReviewScreen` — wire
  `ScanDependencies(createEdgeDetector: () => FakeEdgeDetector(...))` and
  verify that the `CaptureReviewScreen` pushed after shutter tap has
  `edgeDetector` set (inspect via `tester.widget<CaptureReviewScreen>(...)`)

### BDD — `integration_test/f2_auto_corners.feature`

```gherkin
Feature: Auto-fill crop corners

  Scenario: Document detected — corners pre-filled and overlay turns green
    Given the app is launched with a fake detector that returns detected corners
    When I tap the Scan button
    And I tap the shutter
    Then I see the crop overlay with green handles

  Scenario: No document detected — full-frame corners and blue overlay
    Given the app is launched with a fake detector that returns null
    When I tap the Scan button
    And I tap the shutter
    Then I see the crop overlay with blue handles
```

Step definitions required:
- `the_app_is_launched_with_a_fake_detector_that_returns_detected_corners.dart`
  — uses `ScanDependencies(createEdgeDetector: () => FakeEdgeDetector(result: aDetectedResult))`
  where `aDetectedResult` is a `DetectionResult` with `CropCorners` set to
  `const CropCorners(topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1), bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9))`
  and `confidence: 0.8`
- `the_app_is_launched_with_a_fake_detector_that_returns_null.dart`
  — uses `ScanDependencies(createEdgeDetector: () => FakeEdgeDetector(result: null))`
- `i_see_the_crop_overlay_with_green_handles.dart`
  — `tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor == Colors.green`
- `i_see_the_crop_overlay_with_blue_handles.dart`
  — `tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor == Colors.blue`

Both step definitions need to:
1. Create a `FakeCameraPreviewController` that writes `kFakeJpegBytes` (existing pattern)
2. Create a `FakeEdgeDetector` returning the appropriate result
3. Provide a `readBytes` injectable that returns `kFakeJpegBytes` synchronously,
   so `_runDetection` completes in the test environment

### Verify script — `scripts/verify/f2.sh`

Static asserts:
1. `ScanDependencies` declares `createEdgeDetector`
2. `CaptureReviewScreen` has `edgeDetector` parameter
3. `CropOverlay` has `highlightColor` parameter
4. `_userInteracted` guard present in `capture_review_screen.dart`
5. `opencv_dart` is NOT imported in `capture_review_screen.dart` (DIP boundary)
6. `Colors.green` referenced in `capture_review_screen.dart`
7. BDD feature file `integration_test/f2_auto_corners.feature` exists

Suite gate: `flutter test` passes; `flutter analyze` clean.
Device gate (VERIFY_SKIP_DEVICE=1 skips): `flutter test integration_test/f2_auto_corners_test.dart`.

## Deliverable (user-testable)

**Auto corner pre-fill on the review screen.** You can test it by:

1. **Happy path:** Capture a document on a contrasting background → review screen
   opens with handles placed near the document edges and the outline + handles
   are **green**.
2. **Fallback path:** Capture a blank or featureless image → review screen opens
   on the full frame; outline and handles are **blue**. No error or crash.
3. **User-wins guard:** Quickly drag a corner handle immediately after capture.
   Any delayed detection result does not snap your corners back — your
   adjustment is kept.

## Acceptance criteria

- [ ] `ScanDependencies.createEdgeDetector` defaults to `OpenCvEdgeDetector` — *unit: scan_dependencies_test*
- [ ] `CaptureReviewScreen` accepts `EdgeDetector?`; runs `detect()` in `initState` concurrently with size decode — *widget: capture_review_screen_test*
- [ ] High-confidence result (`≥ 0.5`) pre-fills corners AND shows green overlay — *widget: capture_review_screen_test; BDD: happy path*
- [ ] Null detection result → full-frame corners, blue overlay, no error — *widget: capture_review_screen_test; BDD: fallback path*
- [ ] User-adjusted corners are never overridden by a late detection result — *widget: late-result-discarded test*
- [ ] Detection error (file read / OpenCV) → silent fallback to full-frame, no crash — *widget: throws test*
- [ ] `CropOverlay.highlightColor` propagates to handle border and quad outline — *widget: crop_overlay_test*
- [ ] `EdgeDetector` passed from `CameraScreen` to `CaptureReviewScreen` via `ScanDependencies` — *widget: camera_screen_capture_test*
- [ ] `opencv_dart` not imported in `capture_review_screen.dart` (DIP boundary) — *static: verify/f2.sh*
- [ ] Full test suite green; `flutter analyze` clean — *suite gate: verify/f2.sh*

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`,
> this feature is **not done** until every acceptance criterion above is mapped to a
> passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is
> run and observed green, quality gates pass, and the work is reviewed and
> double-checked. "Looks right" / "should pass" is not done.
