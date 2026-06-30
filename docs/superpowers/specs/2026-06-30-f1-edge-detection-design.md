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

`opencv_dart ^0.9.0` (pub.dev) — Dart FFI wrapper around the OpenCV C++ library.
One `pubspec.yaml` dependency, cross-platform (Android + iOS), ships pre-built
OpenCV binaries. All detection work runs inside `compute()` — never on the UI
thread. No explicit `cv.init()` call is required; the FFI binding is loaded lazily.

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

Pipeline steps inside `_runPipeline`:

1. Decode image dimensions from JPEG header.
2. `cvtColor` → grayscale.
3. `GaussianBlur` — 5×5 kernel.
4. `Canny` — thresholds 75 / 200.
5. `findContours` — RETR\_EXTERNAL, CHAIN\_APPROX\_SIMPLE.
6. For each contour: `approxPolyDP` with ε = 2 % of arc length; keep 4-vertex
   results only.
7. Select the largest-area 4-vertex quad. If none → return `null`.
8. Sort the four points into canonical roles:
   - topLeft: smallest (x + y)
   - bottomRight: largest (x + y)
   - topRight: smallest (y − x)
   - bottomLeft: largest (y − x)
9. Normalize pixel coords to [0..1] by dividing by width / height.
10. Compute confidence (see below).
11. Return `DetectionResult(corners: …, confidence: …)`.

All exceptions (corrupt JPEG, opencv_dart failure, zero contours) are caught;
the method returns `null` — never rethrows to the caller.

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

All fixtures are generated programmatically using the `image` package (already
in `pubspec.yaml`). No binary test assets committed.

**Algorithm correctness**
- White rect on dark background → non-null, confidence > 0.5
- Uniform white → null
- Uniform black → null
- Low-contrast gray noise → null or confidence < 0.3
- Pentagon / triangle / circle contours → null
- Concave shape → null
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
- Corrupt JPEG bytes → null, no throw
- Empty `Uint8List` → null, no throw
- Single-pixel image → null, no throw
- Large image (4000 × 3000) → completes in < 2 s
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
  └─ compute(_runPipeline, bytes)        ← isolate, off UI thread
       ├─ cv.imdecode → Mat (width, height, pixels)
       ├─ cvtColor → grayscale
       ├─ GaussianBlur (5×5)
       ├─ Canny (75/200)
       ├─ findContours (RETR_EXTERNAL)
       ├─ approxPolyDP per contour (ε = 2% perimeter) → keep 4-vertex
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
| Corrupt / empty bytes | Caught in `compute()`; returns `null` |
| No 4-point contour found | Returns `null` |
| `opencv_dart` internal error | Caught; returns `null` |
| Single-pixel or degenerate image | Returns `null` |
| Large image (perf) | Completes in < 2 s; asserted in unit test |

## Files changed

| Action | File |
|--------|------|
| Modify | `apps/mobile/pubspec.yaml` (add `opencv_dart ^0.9.0`) |
| Create | `apps/mobile/lib/features/scan/edge_detector.dart` |
| Create | `apps/mobile/lib/features/scan/opencv_edge_detector.dart` |
| Modify | `apps/mobile/test/support/fake_scan.dart` (add `FakeEdgeDetector`) |
| Create | `apps/mobile/test/features/scan/opencv_edge_detector_test.dart` |
| Create | `apps/mobile/integration_test/f1_edge_detection_test.dart` (hand-written) |
| Create | `scripts/verify/f1.sh` |

No schema migration. No changes to existing library or scan screens.
`ScanDependencies` unchanged — `EdgeDetector` injection is F2's responsibility.
