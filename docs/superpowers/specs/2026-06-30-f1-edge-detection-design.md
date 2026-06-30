# F1 — Contour Detection Design

## Goal

Implement an `EdgeDetector` service that accepts a captured JPEG as bytes and
returns the document's four corner points as a `DetectionResult` (corners +
confidence score), or `null` when no document quad is found. F2 will wire this
into `CaptureReviewScreen` to pre-fill the crop overlay; F1 delivers only the
detection engine.

## Context

- **E1** introduced `CropCorners` — normalized [0..1] display coords, four
  role-tagged corners (topLeft, topRight, bottomRight, bottomLeft).
- **E2** introduced `ImageWarper` / `PerspectiveWarper` as the DIP pattern for
  injectable image processing. `EdgeDetector` follows this pattern exactly.
- **F1** adds the detection service (interface + implementation + fakes + tests).
  No UI changes. No changes to `CaptureReviewScreen` or `ScanDependencies`.
- **F2** (next) wires `EdgeDetector` into `CaptureReviewScreen` to pre-fill
  corners and show the green confidence cue.

## Imaging backend

`opencv_dart` (pub.dev) — Dart FFI wrapper around the OpenCV C++ library.
One `pubspec.yaml` dependency, cross-platform (Android, iOS, macOS, Linux, Windows),
ships pre-built OpenCV binaries including macOS host binaries (enabling `flutter test`
unit tests without a device). All detection work runs inside `compute()` — never on
the UI thread.

**Version:** pin to latest stable at implementation time (run `flutter pub add opencv_dart`
and commit the resulting `pubspec.lock`).

**Initialization:** some `opencv_dart` versions require `await cv.init()` before first
use. The implementer must check the chosen version's README. If required, add a single
`await cv.init()` call in `apps/mobile/lib/main.dart` before `runApp()` — this is the
only change to files outside `lib/features/scan/` and is noted in the files-changed table.

Rationale over alternatives:
- **vs. platform channels**: same OpenCV, but no Kotlin/Swift boilerplate and no
  per-platform native build config to maintain.
- **vs. pure Dart (`image` package)**: `image` has no `findContours` /
  `approxPolyDP`; reliable document corner detection is not achievable.

## Architecture

Two files, three types:

### `lib/features/scan/edge_detector.dart`

```dart
/// Immutable detection result: four corners in normalized [0..1] display
/// coordinates and a confidence score in [0.0, 1.0].
class DetectionResult {
  final CropCorners corners;
  final double confidence;
  const DetectionResult({required this.corners, required this.confidence});

  @override
  bool operator ==(Object other) =>
      other is DetectionResult &&
      corners == other.corners &&
      confidence == other.confidence;

  @override
  int get hashCode => Object.hash(corners, confidence);

  @override
  String toString() => 'DetectionResult(corners: $corners, confidence: $confidence)';
}

/// DIP boundary for document-edge detection. Concrete engine (OpenCV) is
/// injected at the composition root; callers never import opencv_dart.
abstract interface class EdgeDetector {
  /// Returns [DetectionResult] when a 4-point quad is found, or [null] when
  /// no document is detected. Never throws — all failures become null.
  Future<DetectionResult?> detect(Uint8List bytes);
}
```

### `lib/features/scan/opencv_edge_detector.dart`

`OpenCvEdgeDetector implements EdgeDetector`. Its `detect()` method calls
`compute(_runPipeline, bytes)` where `_runPipeline` is a **top-level function**
(Flutter's `compute()` requires the callback to be top-level or static — an
instance method will not work). `_runPipeline` is the only function that
imports `opencv_dart`.

**Isolate boundary safety:** `CropCorners` contains `Offset` from `dart:ui`,
which has uncertain sendability across isolate boundaries. To avoid this,
`_runPipeline` returns `List<double>?` — nine primitives: `[tl.dx, tl.dy,
tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]`. The `detect()` method
constructs `CropCorners` and `DetectionResult` on the main thread after
`compute()` returns. `null` from `_runPipeline` means no quad found.

**Sync-only rule:** All `opencv_dart` calls inside `_runPipeline` MUST use the
**synchronous** variants (`cv.cvtColor`, `cv.GaussianBlur`, etc.) — never the
async variants (`cv.cvtColorAsync`, etc.). The async variants spawn their own
isolates; calling them inside `compute()` (which already runs in an isolate)
causes nested isolate spawning and undefined behavior.

**Mat disposal rule:** Every `Mat` allocated in `_runPipeline` (from `imdecode`,
`cvtColor`, `GaussianBlur`, `Canny`, `findContours`) MUST be disposed before the
function returns — on every path (success, null, and exception). `opencv_dart`
does not GC native memory; an undisposed `Mat` leaks 5–30 MB of heap per call.
Use `try/finally` or dispose immediately after each operation is no longer needed.

Pipeline steps inside `_runPipeline` (all sync, all Mats disposed):

1. `cv.imdecode(bytes, cv.IMREAD_COLOR)` → `mat`. **Immediately check
   `mat.isEmpty`; if true, `mat.dispose()` and return `null`** — this is
   `imdecode`'s silent failure mode for corrupt input (it does NOT throw).
2. `cv.cvtColor(mat, cv.COLOR_BGR2GRAY)` → `gray`. Dispose `mat`.
3. `cv.GaussianBlur(gray, (5, 5), 0)` → `blurred`. Dispose `gray`.
4. `cv.Canny(blurred, 75, 200)` → `edges`. Dispose `blurred`.
5. `cv.findContours(edges, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE)` →
   `(contours, hierarchy)`. Dispose `edges` and `hierarchy` (hierarchy is
   returned but unused with RETR\_EXTERNAL; it still holds native memory).
6. For each contour: `cv.approxPolyDP(contour, cv.arcLength(contour, true) * 0.02,
   true)` → keep results with **exactly 4 vertices AND `cv.isContourConvex(approx) == true`**.
   Non-convex 4-point shapes (overlapping documents, table corners) are discarded.
   The feature spec requires "largest **convex** 4-point quad" — this is how it is enforced.
7. Select the largest-area convex 4-vertex quad (`cv.contourArea`). If none → return `null`.
8. Sort the four points into canonical roles:
   - topLeft: smallest (x + y)
   - bottomRight: largest (x + y)
   - topRight: smallest (y − x)
   - bottomLeft: largest (y − x)
9. Normalize pixel coords to [0..1]: divide x by `mat.cols`, y by `mat.rows`
   (use the dimensions captured from `mat` before disposal in step 2).
10. Compute confidence (see below).
11. Return `List<double>[tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y, confidence]`.

All exceptions are caught in a `try/catch` wrapping the entire body; the `finally`
block disposes any Mat that may not have been disposed yet. Returns `null` on any
exception — never rethrows.

### Confidence scoring

Two components blended with fixed weights:

| Component | Formula | Weight |
|-----------|---------|--------|
| `areaScore` | detected quad pixel area ÷ image pixel area | 0.6 |
| `angleScore` | `1 − (meanInteriorAngleErrorDeg / 90)`, clamped [0, 1] | 0.4 |

`confidence = (0.6 × areaScore + 0.4 × angleScore).clamp(0.0, 1.0)`

Area ratio captures "does the quad fill a meaningful portion of the frame?"
Angle regularity captures "do the four corners form right angles?" — prevents
large non-document shapes (a wall, a desk) from scoring highly.

No threshold is applied in F1. The score is returned raw; F2 decides the
pre-fill vs. full-frame policy.

## Test double

**`test/support/fake_scan.dart`** — `FakeEdgeDetector`:

```dart
class FakeEdgeDetector implements EdgeDetector {
  final DetectionResult? result;
  int calls = 0;
  FakeEdgeDetector({this.result});

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    calls++;
    return result;
  }
}
```

Used by F2 widget tests to inject a fixed detection result without running OpenCV.

## Testing

### Unit tests (~35 cases)

File: `test/features/scan/opencv_edge_detector_test.dart`

These tests call the real `OpenCvEdgeDetector.detect()` via `opencv_dart` FFI.
`opencv_dart` ships macOS host binaries, so `flutter test` (which runs on macOS)
loads the native library without a device. If the CI runner is not macOS, move
these tests to the integration test file. All fixtures are generated
programmatically using the `image` package (already in `pubspec.yaml`). No
binary test assets committed.

**Algorithm correctness**
- White rect on dark background → non-null, confidence > 0.5
- Uniform white → null
- Uniform black → null
- Low-contrast gray noise → null or confidence < 0.3
- Pentagon / triangle / circle contours → null
- Concave 4-vertex shape → null (fails `isContourConvex` check)
- Non-convex quad (arrow/chevron shape) → null
- Two rects present → largest selected
- Portrait-oriented rect → corners correct
- Landscape-oriented rect → corners correct
- Rect tilted ~15° → detected
- Rect tilted ~30° → detected
- Rect tilted ~45° → detected
- Rect with mild perspective distortion → detected
- Rect touching image edges → detected
- Rect occupying < 5 % of image → null or confidence < 0.3

**Corner ordering**
- topLeft has smallest (x + y)
- bottomRight has largest (x + y)
- topRight has smallest (y − x)
- bottomLeft has largest (y − x)
- All normalized values in [0.0, 1.0]
- Normalization proportional to image dimensions (non-square image verified)

**Confidence scoring**
- Perfect axis-aligned rect → angleScore ≈ 1.0
- Highly skewed quad → angleScore < 0.5
- Area score correct for known rect pixel dimensions
- Weighted blend = 0.6 × area + 0.4 × angle, asserted numerically
- confidence always clamped to [0.0, 1.0]

**Robustness**
- Corrupt JPEG bytes → null, no throw (empty-Mat path, not exception)
- Empty `Uint8List` → null, no throw
- Single-pixel image → null, no throw
- Repeated calls do not grow native heap (Mat disposal verified by calling
  `detect()` 10× in a loop and asserting no crash / no OOM)
- Large image (4000 × 3000) → completes in < 2 s (integration test)
- `detect()` does not block the UI thread (runs in `compute()`)

### Integration tests (on-device, plain `testWidgets`)

File: `integration_test/f1_edge_detection_test.dart` (hand-written, not
build\_runner generated).

The existing BDD step pattern uses `WidgetTester` for state sharing through the
widget tree. F1 has no UI — there is no widget tree to share `Uint8List` inputs
or `DetectionResult?` outputs between steps. Gherkin BDD therefore does not fit
F1. The user-visible BDD scenario ("capture a document → crop screen opens with
corners pre-filled") belongs to F2 where the full widget flow is present.

F1's on-device tests call `OpenCvEdgeDetector.detect()` directly inside
`testWidgets()` groups — 5 scenarios mirroring the approved Gherkin intent:

```dart
group('F1 edge detection — on-device', () {
  late EdgeDetector detector;
  setUp(() => detector = const OpenCvEdgeDetector());

  testWidgets('white rect on dark background → non-null, confidence > 0.5', ...);
  testWidgets('uniform white image → null', ...);
  testWidgets('circular-only shapes → null', ...);
  testWidgets('corrupt bytes → null, no throw', ...);
  testWidgets('corner ordering canonical (upper-left rect)', ...);
});
```

Fixtures generated programmatically with the `image` package (same as unit
tests). No Gherkin step files added in F1. No `build_runner` invocation needed.

### Verify script

`scripts/verify/f1.sh` — mirrors `e3.sh`:

**Static asserts:**
- `EdgeDetector` interface in `lib/features/scan/edge_detector.dart`
- `DetectionResult` class in `lib/features/scan/edge_detector.dart`
- `DetectionResult` has `operator ==` (equality for test assertions)
- `OpenCvEdgeDetector` in `lib/features/scan/opencv_edge_detector.dart`
- `_runPipeline` top-level function in `opencv_edge_detector.dart`
- `List<double>` return type in `_runPipeline` (isolate-safe primitives)
- `isContourConvex` in `opencv_edge_detector.dart` (convexity filter)
- `compute(` in `opencv_edge_detector.dart` (off-thread assertion)
- `opencv_dart` in `pubspec.yaml`
- `FakeEdgeDetector` in `test/support/fake_scan.dart`
- Integration test file `integration_test/f1_edge_detection_test.dart` present

**Suite:** `flutter test apps/mobile` — all tests pass, coverage ≥ 70%.  
**Analyze:** `flutter analyze apps/mobile` — clean.  
**Integration gate:** `VERIFY_SKIP_DEVICE=1` by default; `REAL_DEVICE=1` opts in.  
**Fail-closed:** exits non-zero on any assertion failure.

## Data flow

```
OpenCvEdgeDetector.detect(bytes)
  └─ compute(_runPipeline, bytes)        ← isolate, off UI thread (sync variants only)
       ├─ cv.imdecode → Mat; if mat.isEmpty → dispose + return null
       ├─ cvtColor → gray; dispose Mat
       ├─ GaussianBlur (5×5)
       ├─ Canny (75/200)
       ├─ findContours (RETR_EXTERNAL)
       ├─ approxPolyDP per contour (ε = 2% perimeter) → keep 4-vertex + convex
       ├─ largest area quad selected
       ├─ sort → topLeft/topRight/bottomRight/bottomLeft
       ├─ normalize to [0..1]
       ├─ confidence = 0.6×areaScore + 0.4×angleScore
       └─ return List<double>[tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy,
                              bl.dx, bl.dy, confidence]   ← primitives only
  back on main thread:
  └─ detect() converts List<double> → CropCorners → DetectionResult
  → DetectionResult(corners, confidence)   ← returned to caller
  → null                                   ← if no quad found or any exception
```

Cancel path: caller receives `null` → F2 defaults to `CropCorners.fullFrame`.

## Error handling

| Failure | Behaviour |
|---------|-----------|
| Corrupt / empty bytes | `imdecode` returns empty `Mat`; `mat.isEmpty` guard returns `null` (not exception) |
| No convex 4-point contour found | Returns `null`; all Mats disposed |
| `opencv_dart` internal error | Caught by outer `try/catch`; `finally` disposes remaining Mats; returns `null` |
| Single-pixel or degenerate image | `mat.isEmpty` or zero contours; returns `null` |
| Async variant called in isolate | Prevented by sync-only rule above |
| Mat not disposed | Prevented by `try/finally` dispose pattern |
| Large image (perf) | Completes in < 2 s; asserted in integration test |

## Files changed

| Action | File |
|--------|------|
| Modify | `apps/mobile/pubspec.yaml` (add `opencv_dart`, latest stable) |
| Possibly modify | `apps/mobile/lib/main.dart` (add `await cv.init()` if required by chosen version) |
| Create | `apps/mobile/lib/features/scan/edge_detector.dart` |
| Create | `apps/mobile/lib/features/scan/opencv_edge_detector.dart` |
| Modify | `apps/mobile/test/support/fake_scan.dart` (add `FakeEdgeDetector`) |
| Create | `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` |
| Create | `apps/mobile/integration_test/f1_edge_detection_test.dart` (hand-written) |
| Create | `scripts/verify/f1.sh` |

No schema migration. No changes to existing library or scan screens.
`ScanDependencies` unchanged — `EdgeDetector` injection is F2's responsibility.
