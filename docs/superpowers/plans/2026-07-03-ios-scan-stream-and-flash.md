# iOS Scan: Stream-based Live Detection + Flash Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `takePicture()`-per-800ms live-detection loop with a
`startImageStream()` feed (no flash, no autofocus thrash) and add a three-state
Off/Torch/Flash toggle.

**Architecture:** Live frames arrive from `CameraController.startImageStream`,
are time-throttled and mapped to a plugin-agnostic `CameraFrame`, and fed to the
existing OpenCV segmentation pipeline via a new `EdgeDetector.detectFrame` that
builds a `cv.Mat` from raw planes. The still-capture path (shutter) is unchanged
except that it honors a user-selected `ScanFlashMode`.

**Tech Stack:** Flutter, `camera: ^0.12.0+1`, `opencv_dart: ^1.4.5`
(`import 'package:opencv_dart/opencv_dart.dart' as cv`), `compute()` isolates.

## Global Constraints

- **DIP boundary stays plugin-agnostic:** the `camera` package type
  `CameraImage` must not appear in `camera_preview_controller.dart`,
  `edge_detector.dart`, the fake, or any test. Only
  `camera_preview_controller_impl.dart` imports `package:camera`.
- **`detect(Uint8List)` behavior unchanged** — the capture-review path still
  uses it; its existing tests must stay green.
- **Detector never throws** — `detect` and `detectFrame` return `null` on any
  failure (decode/convert/timeout), run inside `compute()` with the existing
  timeout guard.
- **Controller sampling/flash methods never throw** — swallow `CameraException`.
- **Host suite green** (`flutter test`); camera-hardware behavior is verified
  on-device (iPhone `00008120-0016355C21E8201E`, Android `RZCY51D0T1K`) — the
  host suite skips `integration_test`.
- **Capture stays `ResolutionPreset.ultraHigh`.** Only live sampling changes.
- **Default flash on scan entry: Off.**

---

## File Structure

- Create `lib/features/scan/camera_frame.dart` — `CameraFrame`,
  `CameraFramePlane`, `CameraFrameFormat` value types.
- Create `lib/features/scan/scan_flash_mode.dart` — `ScanFlashMode` enum.
- Modify `lib/features/scan/edge_detector.dart` — add `detectFrame`.
- Modify `lib/features/scan/opencv_edge_detector.dart` — refactor
  `_runPipeline` → `_runPipelineOnMat`; add BGRA + YUV frame→Mat builders.
- Modify `lib/features/scan/camera_preview_controller.dart` — replace
  `sampleFrame` with `startSampling`/`stopSampling`; add `setFlashMode`.
- Modify `lib/features/scan/camera_preview_controller_impl.dart` — image stream,
  throttle, format group, flash mapping; remove debug instrumentation.
- Modify `lib/features/scan/widgets/camera_preview_view.dart` — flash toggle button.
- Modify `lib/features/scan/camera_screen.dart` — stream wiring + flash state;
  remove `_kDbgDisableSampleLoop` + debug prints.
- Modify `test/support/fake_scan.dart` — fake streaming + flash + `detectFrame`.
- Modify/replace `test/features/scan/camera_preview_controller_f3_test.dart`,
  `test/features/scan/camera_screen_f3_test.dart`,
  `test/features/scan/widgets/camera_preview_view_f3_test.dart`.

---

## Task 1: `CameraFrame` + `ScanFlashMode` value types

**Files:**
- Create: `lib/features/scan/camera_frame.dart`
- Create: `lib/features/scan/scan_flash_mode.dart`
- Test: `test/features/scan/camera_frame_test.dart`

**Interfaces:**
- Produces: `enum CameraFrameFormat { bgra8888, yuv420 }`;
  `class CameraFramePlane { Uint8List bytes; int bytesPerRow; int? bytesPerPixel; }`;
  `class CameraFrame { int width; int height; CameraFrameFormat format; List<CameraFramePlane> planes; }`;
  `enum ScanFlashMode { off, torch, flash }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/scan/camera_frame_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';

void main() {
  test('CameraFrame holds dims, format, and planes', () {
    final frame = CameraFrame(
      width: 4,
      height: 2,
      format: CameraFrameFormat.bgra8888,
      planes: [
        CameraFramePlane(
          bytes: Uint8List.fromList(List.filled(4 * 2 * 4, 7)),
          bytesPerRow: 4 * 4,
          bytesPerPixel: 4,
        ),
      ],
    );
    expect(frame.width, 4);
    expect(frame.height, 2);
    expect(frame.format, CameraFrameFormat.bgra8888);
    expect(frame.planes, hasLength(1));
    expect(frame.planes.first.bytesPerRow, 16);
    expect(frame.planes.first.bytes.first, 7);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/camera_frame_test.dart`
Expected: FAIL — `camera_frame.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/scan/camera_frame.dart
import 'dart:typed_data';

/// Raw pixel layout of a streamed preview frame. Plugin-agnostic so the
/// detector and fakes never depend on `package:camera`.
enum CameraFrameFormat { bgra8888, yuv420 }

/// One image plane: its bytes plus the row stride (may exceed width*bpp due to
/// hardware row padding) and pixel stride.
class CameraFramePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  const CameraFramePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });
}

/// One live preview frame. [planes] is length 1 for [CameraFrameFormat.bgra8888]
/// (iOS) and length 3 (Y, U, V) for [CameraFrameFormat.yuv420] (Android).
class CameraFrame {
  final int width;
  final int height;
  final CameraFrameFormat format;
  final List<CameraFramePlane> planes;
  const CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });
}
```

```dart
// lib/features/scan/scan_flash_mode.dart

/// User-selectable flash behavior on the scan screen.
/// - [off]: LED off during preview and capture.
/// - [torch]: LED on continuously during preview and capture.
/// - [flash]: LED off during preview, fires only at the moment of capture.
enum ScanFlashMode { off, torch, flash }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/scan/camera_frame_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/camera_frame.dart lib/features/scan/scan_flash_mode.dart test/features/scan/camera_frame_test.dart
git commit -m "feat(scan): CameraFrame + ScanFlashMode value types"
```

---

## Task 2: Detector — pipeline refactor + `detectFrame` BGRA path

**Files:**
- Modify: `lib/features/scan/edge_detector.dart`
- Modify: `lib/features/scan/opencv_edge_detector.dart`
- Modify: `test/support/fake_scan.dart` (add `detectFrame` to `FakeEdgeDetector`)
- Test: `test/features/scan/opencv_edge_detector_detectframe_test.dart`

**Interfaces:**
- Consumes: `CameraFrame`, `CameraFrameFormat` (Task 1).
- Produces: `EdgeDetector.detectFrame(CameraFrame frame) → Future<DetectionResult?>`;
  internal `List<double>? _runPipelineOnMat(cv.Mat bgr)`;
  `cv.Mat _bgrMatFromFrame(CameraFrame f)`.

**Context:** `opencv_edge_detector.dart` currently has
`List<double>? _runPipeline(Uint8List bytes)` that starts with
`cv.imdecode(bytes, cv.IMREAD_COLOR)` then runs Steps 2–7 (downscale → grayscale
→ blur → dual-Otsu → contour → quad → score). We extract Steps 2–7 into
`_runPipelineOnMat(cv.Mat)` so both the byte path and the frame path share them.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/scan/opencv_edge_detector_detectframe_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

void main() {
  // A bright rectangle centered on a dark background, as a tightly-packed
  // BGRA frame. The detector should find a plausible quad.
  CameraFrame brightRectBgra(int w, int h) {
    final bytes = Uint8List(w * h * 4); // all zero = opaque-ish dark
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final inside = x > w * 0.2 && x < w * 0.8 && y > h * 0.2 && y < h * 0.8;
        final v = inside ? 240 : 15;
        bytes[i] = v;      // B
        bytes[i + 1] = v;  // G
        bytes[i + 2] = v;  // R
        bytes[i + 3] = 255; // A
      }
    }
    return CameraFrame(
      width: w,
      height: h,
      format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: w * 4, bytesPerPixel: 4)],
    );
  }

  test('detectFrame finds a quad in a bright-rectangle BGRA frame', () async {
    const detector = OpenCvEdgeDetector();
    final result = await detector.detectFrame(brightRectBgra(320, 240));
    expect(result, isNotNull);
    expect(result!.confidence, greaterThan(0.5));
  });

  test('detectFrame returns null on a uniform (no-document) frame', () async {
    const detector = OpenCvEdgeDetector();
    final w = 320, h = 240;
    final bytes = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128);
    final frame = CameraFrame(
      width: w,
      height: h,
      format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: w * 4, bytesPerPixel: 4)],
    );
    expect(await detector.detectFrame(frame), isNull);
  });
}
```

> Note: like the existing `opencv_edge_detector_test.dart`, these exercise the
> native lib and are environmental on hosts where `libdartcv` will not load (see
> memory `opencv-host-test-and-detect-timeout`). If the native lib is
> unavailable they return null/timeout rather than asserting engine behavior;
> the real gate is the on-device run in Task 8. Run them where the lib loads
> (CI/device) to confirm the quad.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/opencv_edge_detector_detectframe_test.dart`
Expected: FAIL — `detectFrame` not defined.

- [ ] **Step 3a: Add `detectFrame` to the interface**

```dart
// lib/features/scan/edge_detector.dart — add import + method
import 'camera_frame.dart';
// ... inside abstract interface class EdgeDetector:
  /// Detects the document quad in a raw live-preview [frame]. Returns null when
  /// no document is found. Never throws — all failures become null.
  Future<DetectionResult?> detectFrame(CameraFrame frame);
```

- [ ] **Step 3b: Refactor pipeline + implement `detectFrame` (BGRA)**

In `opencv_edge_detector.dart`:

Add imports/typedef and a frame pipeline runner alongside the existing byte one:

```dart
import 'camera_frame.dart';

Future<List<double>?> _computeFrameRunner(CameraFrame frame) =>
    Future.value(_runFramePipeline(frame));
```

Split the existing `_runPipeline`: keep the decode, delegate the rest.

```dart
List<double>? _runPipeline(Uint8List bytes) {
  final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
  if (mat.isEmpty) {
    mat.dispose();
    return null;
  }
  return _runPipelineOnMat(mat); // takes ownership: disposes `mat`
}

List<double>? _runFramePipeline(CameraFrame frame) {
  cv.Mat? bgr;
  try {
    bgr = _bgrMatFromFrame(frame);
    if (bgr == null || bgr.isEmpty) return null;
    final out = _runPipelineOnMat(bgr); // takes ownership
    bgr = null;
    return out;
  } finally {
    bgr?.dispose();
  }
}
```

`_runPipelineOnMat(cv.Mat mat)` is the current body of `_runPipeline` starting
at "Step 2: Downscale" (everything after the `imdecode`/`isEmpty` guard), with
the `mat` variable already assigned. Move that code verbatim; it already
disposes `mat` and its derivatives in its `finally`.

Add the BGRA builder (stride-aware; iOS `CVPixelBuffer` rows may be padded):

```dart
/// Builds a BGR [cv.Mat] from a [frame]. Returns null for unsupported formats.
cv.Mat? _bgrMatFromFrame(CameraFrame frame) {
  switch (frame.format) {
    case CameraFrameFormat.bgra8888:
      return _bgrFromBgra(frame);
    case CameraFrameFormat.yuv420:
      return _bgrFromYuv420(frame); // implemented in Task 3
  }
}

cv.Mat _bgrFromBgra(CameraFrame frame) {
  final plane = frame.planes.first;
  final w = frame.width, h = frame.height;
  final rowLen = w * 4;
  Uint8List packed;
  if (plane.bytesPerRow == rowLen) {
    packed = plane.bytes;
  } else {
    // Drop per-row padding into a tight w*4 buffer.
    packed = Uint8List(rowLen * h);
    for (var row = 0; row < h; row++) {
      final src = row * plane.bytesPerRow;
      packed.setRange(row * rowLen, row * rowLen + rowLen, plane.bytes, src);
    }
  }
  final bgra = cv.Mat.fromList(h, w, cv.MatType.CV_8UC4, packed);
  final bgr = cv.cvtColor(bgra, cv.COLOR_BGRA2BGR);
  bgra.dispose();
  return bgr;
}
```

Add a stub for YUV so the switch compiles (Task 3 replaces it):

```dart
cv.Mat? _bgrFromYuv420(CameraFrame frame) => null; // TODO Task 3
```

Add the public method + timeout guard (mirror `detect`):

```dart
@override
Future<DetectionResult?> detectFrame(CameraFrame frame) async {
  try {
    final flat = await compute(_computeFrameRunner, frame)
        .timeout(_kDetectTimeout);
    if (flat == null) return null;
    return _resultFromFlat(flat); // same mapping detect() already uses
  } catch (_) {
    return null;
  }
}
```

If `detect` currently inlines the flat→`DetectionResult` mapping, extract it to
`DetectionResult? _resultFromFlat(List<double> flat)` and call it from both.
`_kDetectTimeout` is the existing timeout constant.

- [ ] **Step 3c: Update `FakeEdgeDetector`**

```dart
// test/support/fake_scan.dart — FakeEdgeDetector
int frameCalls = 0;
@override
Future<DetectionResult?> detectFrame(CameraFrame frame) async {
  frameCalls++;
  return result;
}
```
Add `import 'package:mobile/features/scan/camera_frame.dart';` to the file.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/scan/opencv_edge_detector_test.dart test/features/scan/opencv_edge_detector_detectframe_test.dart`
Expected: existing byte-path tests PASS (refactor preserved behavior);
`detectFrame` tests PASS where the native lib loads (else null/timeout per note).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/edge_detector.dart lib/features/scan/opencv_edge_detector.dart test/support/fake_scan.dart test/features/scan/opencv_edge_detector_detectframe_test.dart
git commit -m "feat(scan): EdgeDetector.detectFrame BGRA path; share pipeline via _runPipelineOnMat"
```

---

## Task 3: Detector — YUV420 (Android) frame path

**Files:**
- Modify: `lib/features/scan/opencv_edge_detector.dart`
- Test: `test/features/scan/opencv_edge_detector_yuv_test.dart`

**Interfaces:**
- Produces: real `cv.Mat _bgrFromYuv420(CameraFrame f)` replacing the Task-2 stub.

**Context:** Android `startImageStream` with `ImageFormatGroup.yuv420` yields 3
planes: Y (full res), U, V (half res), each with `bytesPerRow` (row stride) and
`bytesPerPixel` (pixel stride — often 2 for semi-planar). We pack into I420
(planar Y then U then V, tight) and `cvtColor(COLOR_YUV2BGR_I420)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/scan/opencv_edge_detector_yuv_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

void main() {
  // Flat gray YUV420 (Y=128, U=V=128) → mid-gray BGR, no document → null,
  // but must NOT throw and must produce a non-empty Mat internally.
  test('detectFrame handles a well-formed YUV420 frame without throwing',
      () async {
    const detector = OpenCvEdgeDetector();
    final w = 320, h = 240;
    final y = Uint8List(w * h)..fillRange(0, w * h, 128);
    final u = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
    final v = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
    final frame = CameraFrame(
      width: w,
      height: h,
      format: CameraFrameFormat.yuv420,
      planes: [
        CameraFramePlane(bytes: y, bytesPerRow: w, bytesPerPixel: 1),
        CameraFramePlane(bytes: u, bytesPerRow: w ~/ 2, bytesPerPixel: 1),
        CameraFramePlane(bytes: v, bytesPerRow: w ~/ 2, bytesPerPixel: 1),
      ],
    );
    final result = await detector.detectFrame(frame); // uniform → null
    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/opencv_edge_detector_yuv_test.dart`
Expected: with the Task-2 stub, `_bgrFromYuv420` returns null so `detectFrame`
returns null and the test PASSES trivially — so first make the stub `throw
UnimplementedError()` to see it FAIL, then implement. (Change stub to throw,
run, observe FAIL, then Step 3.)

- [ ] **Step 3: Implement `_bgrFromYuv420`**

```dart
cv.Mat? _bgrFromYuv420(CameraFrame frame) {
  if (frame.planes.length < 3) return null;
  final w = frame.width, h = frame.height;
  final cw = w ~/ 2, ch = h ~/ 2;

  // Pack Y tightly.
  final out = Uint8List(w * h + 2 * cw * ch);
  final yP = frame.planes[0];
  for (var row = 0; row < h; row++) {
    final src = row * yP.bytesPerRow;
    out.setRange(row * w, row * w + w, yP.bytes, src);
  }
  // Pack U then V tightly (I420), honoring pixel stride.
  var o = w * h;
  for (final plane in [frame.planes[1], frame.planes[2]]) {
    final ps = plane.bytesPerPixel ?? 1;
    for (var row = 0; row < ch; row++) {
      var src = row * plane.bytesPerRow;
      for (var col = 0; col < cw; col++) {
        out[o++] = plane.bytes[src];
        src += ps;
      }
    }
  }

  final yuv = cv.Mat.fromList(h + ch, w, cv.MatType.CV_8UC1, out);
  final bgr = cv.cvtColor(yuv, cv.COLOR_YUV2BGR_I420);
  yuv.dispose();
  return bgr;
}
```

Revert the stub throw (this replaces it).

- [ ] **Step 4: Run test**

Run: `flutter test test/features/scan/opencv_edge_detector_yuv_test.dart`
Expected: PASS where native lib loads. (Exact quad correctness verified on the
Android device in Task 8.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/opencv_edge_detector.dart test/features/scan/opencv_edge_detector_yuv_test.dart
git commit -m "feat(scan): YUV420 frame->BGR path for Android live detection"
```

---

## Task 4: Controller interface + plugin/fake implementations

**Files:**
- Modify: `lib/features/scan/camera_preview_controller.dart`
- Modify: `lib/features/scan/camera_preview_controller_impl.dart`
- Modify: `test/support/fake_scan.dart`
- Test: `test/features/scan/camera_preview_controller_f3_test.dart` (replace body)

**Interfaces:**
- Consumes: `CameraFrame`, `ScanFlashMode`.
- Produces on `CameraPreviewController`:
  `void startSampling(void Function(CameraFrame) onFrame)`,
  `void stopSampling()`, `Future<void> setFlashMode(ScanFlashMode mode)`.
  `sampleFrame()` is **kept for now** (removed in Task 7) so `camera_screen.dart`
  still compiles until Task 6.
- `FakeCameraPreviewController` gains `void emitFrame(CameraFrame)` (invokes the
  registered `onFrame`), plus records `bool sampling`, `ScanFlashMode? lastFlashMode`.

- [ ] **Step 1: Write the failing test** (fake behavior — no hardware)

```dart
// test/features/scan/camera_preview_controller_f3_test.dart  (new body)
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/scan_flash_mode.dart';
import '../../support/fake_scan.dart';

CameraFrame _frame() => CameraFrame(
      width: 2,
      height: 2,
      format: CameraFrameFormat.bgra8888,
      planes: [
        CameraFramePlane(
            bytes: Uint8List(2 * 2 * 4), bytesPerRow: 8, bytesPerPixel: 4),
      ],
    );

void main() {
  test('startSampling registers a callback that emitFrame invokes', () {
    final c = FakeCameraPreviewController();
    final received = <CameraFrame>[];
    c.startSampling(received.add);
    expect(c.sampling, isTrue);
    c.emitFrame(_frame());
    c.emitFrame(_frame());
    expect(received, hasLength(2));
  });

  test('stopSampling halts delivery', () {
    final c = FakeCameraPreviewController();
    final received = <CameraFrame>[];
    c.startSampling(received.add);
    c.stopSampling();
    expect(c.sampling, isFalse);
    c.emitFrame(_frame());
    expect(received, isEmpty);
  });

  test('setFlashMode records the requested mode', () async {
    final c = FakeCameraPreviewController();
    await c.setFlashMode(ScanFlashMode.torch);
    expect(c.lastFlashMode, ScanFlashMode.torch);
  });

  test('previewSize returns 1920x1080', () {
    expect(FakeCameraPreviewController().previewSize, const Size(1920, 1080));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/camera_preview_controller_f3_test.dart`
Expected: FAIL — `startSampling`/`emitFrame`/`setFlashMode` not defined.

- [ ] **Step 3a: Extend the interface**

```dart
// camera_preview_controller.dart — add imports + methods (keep sampleFrame)
import 'camera_frame.dart';
import 'scan_flash_mode.dart';
// inside abstract interface class CameraPreviewController:
  /// Starts delivering live preview frames to [onFrame]. No-op if already
  /// sampling. Never throws.
  void startSampling(void Function(CameraFrame frame) onFrame);

  /// Stops live-frame delivery. Safe when not sampling. Never throws.
  void stopSampling();

  /// Sets the flash/torch behavior. Never throws.
  Future<void> setFlashMode(ScanFlashMode mode);
```

- [ ] **Step 3b: Implement in `PluginCameraPreviewController`**

Set the stream format in `initialize()` — add `imageFormatGroup`:

```dart
import 'dart:io' show Platform; // already imports dart:io
import 'package:camera/camera.dart';
import 'camera_frame.dart';
import 'scan_flash_mode.dart';
// ...
final controller = CameraController(
  cameras.first,
  ResolutionPreset.ultraHigh,
  enableAudio: false,
  imageFormatGroup:
      Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
);
```

Add state + methods:

```dart
void Function(CameraFrame)? _onFrame;
bool _streaming = false;
final Stopwatch _throttle = Stopwatch();
ScanFlashMode _flash = ScanFlashMode.off;
static const _kMinSampleGapMs = 700;

@override
void startSampling(void Function(CameraFrame frame) onFrame) {
  final controller = _controller;
  if (controller == null || !controller.value.isInitialized) return;
  _onFrame = onFrame;
  if (_streaming) return;
  _streaming = true;
  _throttle
    ..reset()
    ..start();
  var first = true;
  controller.startImageStream((image) {
    if (!_streaming) return;
    if (!first && _throttle.elapsedMilliseconds < _kMinSampleGapMs) return;
    first = false;
    _throttle.reset();
    final frame = _mapFrame(image);
    if (frame != null) _onFrame?.call(frame);
  }).catchError((_) {
    _streaming = false;
  });
}

@override
void stopSampling() {
  _onFrame = null;
  if (!_streaming) return;
  _streaming = false;
  _controller?.stopImageStream().catchError((_) {});
}

CameraFrame? _mapFrame(CameraImage image) {
  final group = image.format.group;
  final CameraFrameFormat fmt;
  if (group == ImageFormatGroup.bgra8888) {
    fmt = CameraFrameFormat.bgra8888;
  } else if (group == ImageFormatGroup.yuv420) {
    fmt = CameraFrameFormat.yuv420;
  } else {
    return null;
  }
  return CameraFrame(
    width: image.width,
    height: image.height,
    format: fmt,
    planes: image.planes
        .map((p) => CameraFramePlane(
              bytes: p.bytes,
              bytesPerRow: p.bytesPerRow,
              bytesPerPixel: p.bytesPerPixel,
            ))
        .toList(growable: false),
  );
}

@override
Future<void> setFlashMode(ScanFlashMode mode) async {
  _flash = mode;
  final controller = _controller;
  if (controller == null || !controller.value.isInitialized) return;
  try {
    // Torch lights immediately; off/flash keep the LED dark during preview
    // (flash fires only at capture, applied in capture()).
    await controller.setFlashMode(
      mode == ScanFlashMode.torch ? FlashMode.torch : FlashMode.off,
    );
  } on CameraException {
    // never throws
  }
}
```

Update `capture()` to honor `flash` mode:

```dart
@override
Future<CapturedImage> capture() async {
  final controller = _controller;
  if (controller == null || !controller.value.isInitialized) {
    throw const CameraUnavailableException('capture() before initialize()');
  }
  try {
    if (_flash == ScanFlashMode.flash) {
      await controller.setFlashMode(FlashMode.always);
    }
    final file = await controller.takePicture();
    return CapturedImage(file.path);
  } on CameraException catch (e) {
    throw CameraUnavailableException(e.description ?? e.code);
  } finally {
    if (_flash == ScanFlashMode.flash) {
      await controller.setFlashMode(FlashMode.off).catchError((_) {});
    }
  }
}
```

Note: the old `capture()` `_takingPicture` wait loop existed to avoid colliding
with `sampleFrame`'s `takePicture`. With streaming, live sampling no longer calls
`takePicture`, and the screen stops sampling before capture — so the wait loop
and `_takingPicture` flag are removed here (and `sampleFrame` is deleted in Task
7).

- [ ] **Step 3c: Implement in `FakeCameraPreviewController`**

```dart
// test/support/fake_scan.dart
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/scan_flash_mode.dart';
// ... fields:
bool sampling = false;
ScanFlashMode? lastFlashMode;
void Function(CameraFrame)? _onFrame;

@override
void startSampling(void Function(CameraFrame frame) onFrame) {
  sampling = true;
  _onFrame = onFrame;
}

@override
void stopSampling() {
  sampling = false;
  _onFrame = null;
}

/// Test hook: simulate a streamed frame.
void emitFrame(CameraFrame frame) {
  if (sampling) _onFrame?.call(frame);
}

@override
Future<void> setFlashMode(ScanFlashMode mode) async {
  lastFlashMode = mode;
}
```

Keep the fake's existing `sampleFrame` for now (removed Task 7).

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/scan/camera_preview_controller_f3_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/camera_preview_controller.dart lib/features/scan/camera_preview_controller_impl.dart test/support/fake_scan.dart test/features/scan/camera_preview_controller_f3_test.dart
git commit -m "feat(scan): image-stream sampling + ScanFlashMode on CameraPreviewController"
```

---

## Task 5: Flash toggle button in `CameraPreviewView`

**Files:**
- Modify: `lib/features/scan/widgets/camera_preview_view.dart`
- Test: `test/features/scan/widgets/camera_preview_view_f3_test.dart` (add cases)

**Interfaces:**
- Consumes: `ScanFlashMode`.
- Produces: `CameraPreviewView` gains
  `final ScanFlashMode flashMode; final ValueChanged<ScanFlashMode> onFlashModeChanged;`
  and renders a button keyed `scan-flash-toggle` that cycles Off→Torch→Flash→Off.

- [ ] **Step 1: Write the failing test**

```dart
// add to camera_preview_view_f3_test.dart
import 'package:mobile/features/scan/scan_flash_mode.dart';
// ...
testWidgets('flash toggle cycles off -> torch on tap', (tester) async {
  ScanFlashMode? changed;
  await tester.pumpWidget(MaterialApp(
    home: CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      flashMode: ScanFlashMode.off,
      onFlashModeChanged: (m) => changed = m,
    ),
  ));
  await tester.tap(find.byKey(const Key('scan-flash-toggle')));
  await tester.pump();
  expect(changed, ScanFlashMode.torch);
});

testWidgets('flash toggle cycles flash -> off on tap', (tester) async {
  ScanFlashMode? changed;
  await tester.pumpWidget(MaterialApp(
    home: CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      flashMode: ScanFlashMode.flash,
      onFlashModeChanged: (m) => changed = m,
    ),
  ));
  await tester.tap(find.byKey(const Key('scan-flash-toggle')));
  await tester.pump();
  expect(changed, ScanFlashMode.off);
});
```

The `FakeCameraPreviewController` here needs `buildPreview()` to render without
hardware — it already returns a placeholder `ColoredBox`, fine.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/widgets/camera_preview_view_f3_test.dart`
Expected: FAIL — `flashMode`/`onFlashModeChanged` params don't exist.

- [ ] **Step 3: Implement**

Add fields + a cycling helper, and a positioned icon button. In
`camera_preview_view.dart`:

```dart
import '../scan_flash_mode.dart';
// fields:
final ScanFlashMode flashMode;
final ValueChanged<ScanFlashMode> onFlashModeChanged;
// constructor: add
//   this.flashMode = ScanFlashMode.off,
//   required this.onFlashModeChanged,

IconData get _flashIcon => switch (flashMode) {
      ScanFlashMode.off => Icons.flash_off,
      ScanFlashMode.torch => Icons.flashlight_on,
      ScanFlashMode.flash => Icons.flash_on,
    };

ScanFlashMode get _nextFlash => switch (flashMode) {
      ScanFlashMode.off => ScanFlashMode.torch,
      ScanFlashMode.torch => ScanFlashMode.flash,
      ScanFlashMode.flash => ScanFlashMode.off,
    };
```

Add to the `Stack` children (top-trailing, safe-area aware):

```dart
Positioned(
  top: 16 + MediaQuery.of(context).viewPadding.top,
  right: 16,
  child: IconButton(
    key: const Key('scan-flash-toggle'),
    icon: Icon(_flashIcon, color: Colors.white, size: 28),
    onPressed: () => onFlashModeChanged(_nextFlash),
  ),
),
```

- [ ] **Step 4: Run test**

Run: `flutter test test/features/scan/widgets/camera_preview_view_f3_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/widgets/camera_preview_view.dart test/features/scan/widgets/camera_preview_view_f3_test.dart
git commit -m "feat(scan): three-state flash toggle button in CameraPreviewView"
```

---

## Task 6: Rewire `camera_screen.dart` to streaming + flash state

**Files:**
- Modify: `lib/features/scan/camera_screen.dart`
- Test: `test/features/scan/camera_screen_f3_test.dart` (rewrite)

**Interfaces:**
- Consumes: `startSampling`/`stopSampling`/`setFlashMode`, `CameraFrame`,
  `ScanFlashMode`, `FakeCameraPreviewController.emitFrame`, `detectFrame`.

**Context:** Replace the `Timer? _sampleTimer` + `_startSampleTimer` +
`_doSample`(`sampleFrame`) machinery with stream registration. The
start/stop lifecycle around shutter/import stays the same (stop before leaving
ready, start on return). Remove the temporary `_kDbgDisableSampleLoop` flag and
`unawaited(_doSample())`.

- [ ] **Step 1: Write the failing test** (rewrite F3 widget tests)

```dart
// camera_screen_f3_test.dart — key cases (replace timer-based ones)
testWidgets('overlay appears when a streamed frame yields confident detection',
    (tester) async {
  final fake = FakeCameraPreviewController();
  await tester.pumpWidget(MaterialApp(home: CameraScreen(
    dependencies: ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => fake,
      createEdgeDetector: () => FakeEdgeDetector(result: _confidentResult),
    ),
    repository: FakeDocumentRepository(),
  )));
  await tester.pumpAndSettle(); // reaches ScanStatus.ready, startSampling called
  expect(find.byType(LiveQuadOverlay), findsNothing);

  fake.emitFrame(_bgraFrame());
  await tester.pump(); // detectFrame future
  await tester.pump(); // setState

  expect(find.byType(LiveQuadOverlay), findsOneWidget);
});

testWidgets('stops sampling after shutter tap', (tester) async {
  final fake = FakeCameraPreviewController(captureReturnPath: '/nonexistent/x.jpg');
  await tester.pumpWidget(MaterialApp(home: CameraScreen(
    dependencies: ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => fake,
      createEdgeDetector: () => FakeEdgeDetector(result: _confidentResult),
    ),
    repository: FakeDocumentRepository(),
  )));
  await tester.pumpAndSettle();
  expect(fake.sampling, isTrue);
  await tester.tap(find.byKey(const Key('scan-shutter')));
  await tester.pump();
  expect(fake.sampling, isFalse);
});
```

Add a `_bgraFrame()` helper (2×2 BGRA) and drop the old `sampleFrameCalls`
assertions. Keep the confidence-threshold cases but drive them via `emitFrame`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/camera_screen_f3_test.dart`
Expected: FAIL — screen still uses the timer/`sampleFrame`.

- [ ] **Step 3: Rewire the screen**

Remove `Timer? _sampleTimer`, `_startSampleTimer`, `_doSample`, the
`_kDbgDisableSampleLoop` flag, and the `dart:async`/`unawaited` sampling usage.
Add:

```dart
bool _isDetecting = false;
ScanFlashMode _flashMode = ScanFlashMode.off;

void _startSampling() {
  if (_controller.status != ScanStatus.ready) return;
  _controller.preview.startSampling(_onFrame);
}

void _stopSampling() => _controller.preview.stopSampling();

Future<void> _onFrame(CameraFrame frame) async {
  if (_isDetecting || _controller.capturing ||
      _controller.status != ScanStatus.ready) {
    return;
  }
  _isDetecting = true;
  try {
    final result = await _edgeDetector.detectFrame(frame);
    if (!mounted) return;
    setState(() {
      _liveResult =
          (result != null && result.confidence >= 0.5) ? result : null;
    });
  } finally {
    _isDetecting = false;
  }
}

void _onFlashModeChanged(ScanFlashMode mode) {
  setState(() => _flashMode = mode);
  _controller.preview.setFlashMode(mode);
}
```

- Replace every `_startSampleTimer()` call with `_startSampling()`, every
  `_sampleTimer?.cancel(); _sampleTimer = null;` with `_stopSampling();`.
- In `initState`, call `_startSampling()` after the controller is ready. Since
  `start()` is async, start sampling when status becomes ready — the existing
  `ListenableBuilder`/status flow already gates on `ScanStatus.ready`; call
  `_startSampling()` in the same place the old code called `_startSampleTimer()`
  (initState + the post-shutter/import `status == ready` guards).
- In `dispose`, `_stopSampling()` before `_controller.dispose()`.
- Pass flash props into `CameraPreviewView`:

```dart
CameraPreviewView(
  controller: _controller.preview,
  onShutter: _onShutter,
  capturing: _controller.capturing,
  liveCorners: _liveResult?.corners,
  previewSize: _liveResult != null ? _controller.preview.previewSize : null,
  flashMode: _flashMode,
  onFlashModeChanged: _onFlashModeChanged,
)
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/scan/`
Expected: F3 + capture + h1/h4/g1/i2 scan tests PASS. Fix any remaining
references to the removed timer API.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/camera_screen.dart test/features/scan/camera_screen_f3_test.dart
git commit -m "feat(scan): drive live detection from image stream + wire flash toggle"
```

---

## Task 7: Remove `sampleFrame` + debug instrumentation

**Files:**
- Modify: `lib/features/scan/camera_preview_controller.dart` (drop `sampleFrame`)
- Modify: `lib/features/scan/camera_preview_controller_impl.dart` (drop
  `sampleFrame`, `_takingPicture`, and all `[SCAN-DEBUG]` `_dbg*` fields + prints)
- Modify: `test/support/fake_scan.dart` (drop `sampleFrame`,
  `sampleFrameCalls`, `sampleFrameResult`, and `liveDetectionScanDependencies`'s
  `sampleFrameResult` param)
- Modify: any test still referencing `sampleFrame*`.

- [ ] **Step 1: Grep for remaining references**

Run: `grep -rn "sampleFrame\|SCAN-DEBUG\|_dbg\|_kDbgDisableSampleLoop\|_takingPicture" lib/ test/`
Expected: a finite list to clean.

- [ ] **Step 2: Remove them**

Delete the `sampleFrame()` method from the interface, the plugin impl, and the
fake; delete `sampleFrameCalls`/`sampleFrameResult`; remove the debug
`Stopwatch`/counters/`debugPrint`s added during investigation and the
`import 'package:flutter/foundation.dart'` if now unused. Update
`liveDetectionScanDependencies` to drop `sampleFrameResult`. Delete the obsolete
`FakeCameraPreviewController.sampleFrame` tests in
`camera_preview_controller_f3_test.dart` (already replaced in Task 4).

- [ ] **Step 3: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: analyzer clean; all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(scan): remove takePicture-based sampleFrame + debug instrumentation"
```

---

## Task 8: On-device verification (iPhone + Android)

**Files:** none (manual acceptance). Confirms the acceptance gates.

- [ ] **Step 1: Run on the iPhone**

Run: `cd apps/mobile && flutter run -d 00008120-0016355C21E8201E`
Open the scanner, frame a document. Verify:
- No flash strobing; no autofocus/exposure pulsing during preview.
- Live green quad still tracks the document (`detectFrame` working over the stream).
- **Close range:** move in close — focus locks cleanly (the reported bug is gone).
- Flash toggle cycles Off (dark) → Torch (LED steady during preview) → Flash
  (LED off in preview, fires only at shutter). Captured photo reflects the mode.
- Shutter capture still produces a sharp 4K page; review/save unaffected.

- [ ] **Step 2: Run on Android**

Run: `cd apps/mobile && flutter run -d RZCY51D0T1K`
Verify the live quad still appears (YUV420 path) and the flash toggle behaves;
no regression vs. before.

- [ ] **Step 3: Confirm no residual debug output**

While running, confirm no `[SCAN-DEBUG]` lines appear in the log.

- [ ] **Step 4: Finish the branch**

Use `superpowers:finishing-a-development-branch`. Host suite green + both
devices verified → merge `fix/ios-scan-flash-strobe`.

---

## Self-Review

- **Spec coverage:** startImageStream (T4/T6), CameraFrame (T1), detectFrame +
  pipeline reuse (T2/T3), three-state flash Off/Torch/Flash (T1/T4/T5/T6),
  stop-before-capture coexistence (T4/T6), instrumentation removal (T7), device
  verification incl. close focus (T8). ✔ All spec sections mapped.
- **Type consistency:** `startSampling(void Function(CameraFrame))`,
  `stopSampling()`, `setFlashMode(ScanFlashMode)`, `detectFrame(CameraFrame)`,
  `emitFrame(CameraFrame)`, `_bgrMatFromFrame`/`_bgrFromBgra`/`_bgrFromYuv420`,
  `CameraFrameFormat.{bgra8888,yuv420}` used identically across tasks. ✔
- **Placeholder scan:** the only intentional temporary stub (`_bgrFromYuv420`
  returns null in T2) is explicitly replaced in T3; no other TODOs. ✔
- **Note:** native-lib host tests (T2/T3) are environmental per memory
  `opencv-host-test-and-detect-timeout`; the real detection gate is on-device
  (T8), consistent with this project's practice.
