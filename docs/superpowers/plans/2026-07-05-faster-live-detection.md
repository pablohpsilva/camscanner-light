# Faster Live Document Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live document-edge detection smooth (~5-8 fps) by reducing each camera frame to a small grayscale buffer inside `detectFrame`, before the isolate hop.

**Architecture:** A new pure-Dart `reduceToGray` decimates the full-res camera frame to a ~400px single-channel `GrayFrame` on the main isolate. `detectFrame` sends that tiny buffer (~160 KB) to a worker isolate that runs the existing Otsu segmentation directly on gray — no full-res color conversion or resize. The still-capture path (`detect(bytes)` at 1024px) is untouched. Reduction lives inside `detectFrame`, so no public interface, fake, or existing-test signatures change.

**Tech Stack:** Flutter/Dart, `opencv_dart` (native, device-only), `compute()` isolates, `flutter_test`.

## Global Constraints

- Package name: `mobile`; imports use `package:mobile/features/scan/...`.
- BGRA8888 plane byte order is `B, G, R, A` (`bytes[i]=B, i+1=G, i+2=R, i+3=A`).
- All `cv.*` calls run only inside `compute()` isolate entry points (top-level functions); every native `cv.Mat`/`Vec*` allocated there MUST be disposed in a `finally`.
- libdartcv does not load under host `flutter test` — any test that drives the real OpenCV pipeline must be host-skip-guarded via the `opencvAvailable` probe pattern already in `opencv_edge_detector_detectframe_test.dart`.
- Live detection is a **guide only**; final crop corners come from the full-res still `detect(bytes)` at 1024px. Coarser live working size is acceptable.
- Working directory for all commands: `apps/mobile`.

---

### Task 1: `GrayFrame` value type

**Files:**
- Create: `lib/features/scan/gray_frame.dart`
- Test: `test/features/scan/gray_frame_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class GrayFrame { final int width; final int height; final Uint8List bytes; const GrayFrame({required this.width, required this.height, required this.bytes}); }` — tightly packed, `bytes.length == width * height`.

- [ ] **Step 1: Write the failing test**

`test/features/scan/gray_frame_test.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/gray_frame.dart';

void main() {
  test('GrayFrame holds dims and a tightly-packed single-channel buffer', () {
    final f = GrayFrame(width: 4, height: 3, bytes: Uint8List(12));
    expect(f.width, 4);
    expect(f.height, 3);
    expect(f.bytes.length, f.width * f.height);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/gray_frame_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'mobile' ... gray_frame.dart` / `GrayFrame` not defined.

- [ ] **Step 3: Write minimal implementation**

`lib/features/scan/gray_frame.dart`:
```dart
import 'dart:typed_data';

/// A downscaled single-channel (8-bit grayscale) preview frame, tightly packed:
/// `bytes.length == width * height`, no row padding. Small enough to copy cheaply
/// across an isolate boundary for live edge detection.
class GrayFrame {
  final int width;
  final int height;
  final Uint8List bytes;
  const GrayFrame({
    required this.width,
    required this.height,
    required this.bytes,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/scan/gray_frame_test.dart`
Expected: PASS (+1).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/gray_frame.dart test/features/scan/gray_frame_test.dart
git commit -m "feat(scan): GrayFrame value type for live detection"
```

---

### Task 2: `reduceToGray` — BGRA8888 path

**Files:**
- Create: `lib/features/scan/frame_reducer.dart`
- Test: `test/features/scan/frame_reducer_test.dart`

**Interfaces:**
- Consumes: `GrayFrame` (Task 1); `CameraFrame`/`CameraFramePlane`/`CameraFrameFormat` from `camera_frame.dart`.
- Produces: `GrayFrame reduceToGray(CameraFrame frame, {required int maxSide})` — nearest-neighbour decimation by integer factor `k = longest <= maxSide ? 1 : (longest + maxSide - 1) ~/ maxSide`, same `k` on both axes; output dims `(width + k - 1) ~/ k` × `(height + k - 1) ~/ k`. This task implements the `bgra8888` branch; Task 3 adds `yuv420`.

- [ ] **Step 1: Write the failing tests**

`test/features/scan/frame_reducer_test.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/frame_reducer.dart';

/// Builds a BGRA frame where every channel of pixel (x,y) is `pixel(x,y)`
/// (so its luma equals that value), with optional row padding.
CameraFrame _bgra(int w, int h,
    {int? bytesPerRow, required int Function(int x, int y) pixel}) {
  final stride = bytesPerRow ?? w * 4;
  final bytes = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = pixel(x, y);
      final i = y * stride + x * 4;
      bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255;
    }
  }
  return CameraFrame(
    width: w, height: h, format: CameraFrameFormat.bgra8888,
    planes: [CameraFramePlane(bytes: bytes, bytesPerRow: stride, bytesPerPixel: 4)],
  );
}

void main() {
  test('already-small frame passes through with k=1 (no upscale)', () {
    final g = reduceToGray(_bgra(4, 3, pixel: (x, y) => 100), maxSide: 400);
    expect(g.width, 4);
    expect(g.height, 3);
    expect(g.bytes.length, 12);
    expect(g.bytes.every((b) => b == 100), isTrue);
  });

  test('decimates by ceil(longest/maxSide), preserving aspect', () {
    final g = reduceToGray(_bgra(800, 400, pixel: (x, y) => 128), maxSide: 400);
    expect(g.width, 400); // k = 2
    expect(g.height, 200);
  });

  test('BGRA luma uses Rec.601 integer weights (pure red -> 76)', () {
    final bytes = Uint8List(4)
      ..[0] = 0    // B
      ..[1] = 0    // G
      ..[2] = 255  // R
      ..[3] = 255; // A
    final f = CameraFrame(
      width: 1, height: 1, format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: 4, bytesPerPixel: 4)],
    );
    expect(reduceToGray(f, maxSide: 400).bytes[0], (77 * 255) >> 8); // 76
  });

  test('honors row padding (bytesPerRow > width*4)', () {
    final f = _bgra(2, 2,
        bytesPerRow: 2 * 4 + 8, pixel: (x, y) => (x == 1 && y == 1) ? 200 : 10);
    expect(reduceToGray(f, maxSide: 400).bytes, [10, 10, 10, 200]);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/scan/frame_reducer_test.dart`
Expected: FAIL — `reduceToGray` not defined.

- [ ] **Step 3: Write minimal implementation (BGRA + shared skeleton)**

`lib/features/scan/frame_reducer.dart`:
```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'camera_frame.dart';
import 'gray_frame.dart';

/// Reduces a raw camera [frame] to a small, tightly-packed grayscale [GrayFrame]
/// whose longest side is at most [maxSide]. Pure Dart (no OpenCV) so it runs on
/// the main isolate before the detection `compute()` hop and is host-testable.
///
/// Nearest-neighbour decimation by an integer factor `k` (same on both axes, so
/// aspect ratio — and therefore normalized detection corners — is preserved).
/// - YUV420: samples the Y plane (already luminance).
/// - BGRA8888: Rec.601 luma from B, G, R.
GrayFrame reduceToGray(CameraFrame frame, {required int maxSide}) {
  final longest = math.max(frame.width, frame.height);
  final k = longest <= maxSide ? 1 : (longest + maxSide - 1) ~/ maxSide;
  final outW = (frame.width + k - 1) ~/ k;
  final outH = (frame.height + k - 1) ~/ k;
  final out = Uint8List(outW * outH);
  switch (frame.format) {
    case CameraFrameFormat.bgra8888:
      _decimateBgra(frame, k, outW, outH, out);
    case CameraFrameFormat.yuv420:
      throw UnimplementedError('yuv420 added in Task 3');
  }
  return GrayFrame(width: outW, height: outH, bytes: out);
}

void _decimateBgra(
    CameraFrame frame, int k, int outW, int outH, Uint8List out) {
  final p = frame.planes[0];
  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    final srcRow = (oy * k) * p.bytesPerRow;
    for (var ox = 0; ox < outW; ox++) {
      final i = srcRow + (ox * k) * 4;
      final b = p.bytes[i], g = p.bytes[i + 1], r = p.bytes[i + 2];
      out[o++] = (77 * r + 150 * g + 29 * b) >> 8; // weights sum to 256
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/scan/frame_reducer_test.dart`
Expected: PASS (+4).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/frame_reducer.dart test/features/scan/frame_reducer_test.dart
git commit -m "feat(scan): reduceToGray BGRA path"
```

---

### Task 3: `reduceToGray` — YUV420 path

**Files:**
- Modify: `lib/features/scan/frame_reducer.dart`
- Test: `test/features/scan/frame_reducer_test.dart` (add cases)

**Interfaces:**
- Consumes: `reduceToGray` skeleton (Task 2).
- Produces: `yuv420` branch — reads plane 0 (Y), honoring `bytesPerRow` (row stride) and `bytesPerPixel` (Y pixel stride, default 1).

- [ ] **Step 1: Write the failing tests (append to existing file)**

Append inside `main()` in `test/features/scan/frame_reducer_test.dart`, and add this helper above `main()`:
```dart
/// Builds a YUV420 frame whose Y(x,y) == `luma(x,y)`, with optional Y row/pixel
/// stride. U/V are filled mid-gray (unused by reduceToGray).
CameraFrame _yuv(int w, int h,
    {int? yRow, int yPixStride = 1, required int Function(int x, int y) luma}) {
  final row = yRow ?? w * yPixStride;
  final yb = Uint8List(row * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      yb[y * row + x * yPixStride] = luma(x, y);
    }
  }
  final cw = w ~/ 2, ch = h ~/ 2;
  final u = Uint8List(cw * ch)..fillRange(0, cw * ch, 128);
  final v = Uint8List(cw * ch)..fillRange(0, cw * ch, 128);
  return CameraFrame(
    width: w, height: h, format: CameraFrameFormat.yuv420,
    planes: [
      CameraFramePlane(bytes: yb, bytesPerRow: row, bytesPerPixel: yPixStride),
      CameraFramePlane(bytes: u, bytesPerRow: cw, bytesPerPixel: 1),
      CameraFramePlane(bytes: v, bytesPerRow: cw, bytesPerPixel: 1),
    ],
  );
}
```
```dart
  test('YUV samples the Y plane directly', () {
    final g = reduceToGray(_yuv(4, 4, luma: (x, y) => x * 10 + y), maxSide: 400);
    expect(g.width, 4);
    expect(g.height, 4);
    expect(g.bytes[0], 0);  // (0,0)
    expect(g.bytes[1], 10); // (1,0)
    expect(g.bytes[4], 1);  // (0,1)
  });

  test('YUV honors Y row stride padding', () {
    final f = _yuv(2, 2, yRow: 2 + 5, luma: (x, y) => (x == 1 && y == 1) ? 99 : 5);
    expect(reduceToGray(f, maxSide: 400).bytes, [5, 5, 5, 99]);
  });

  test('YUV honors Y pixel stride', () {
    final f = _yuv(2, 2, yPixStride: 2, luma: (x, y) => x * 10 + y);
    expect(reduceToGray(f, maxSide: 400).bytes, [0, 10, 1, 11]);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/scan/frame_reducer_test.dart`
Expected: FAIL — `UnimplementedError: yuv420 added in Task 3`.

- [ ] **Step 3: Implement the YUV branch**

In `lib/features/scan/frame_reducer.dart`, replace the `yuv420` throw with `_decimateY(frame, k, outW, outH, out);` and add:
```dart
void _decimateY(
    CameraFrame frame, int k, int outW, int outH, Uint8List out) {
  final p = frame.planes[0];
  final ps = p.bytesPerPixel ?? 1;
  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    final srcRow = (oy * k) * p.bytesPerRow;
    for (var ox = 0; ox < outW; ox++) {
      out[o++] = p.bytes[srcRow + (ox * k) * ps];
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/scan/frame_reducer_test.dart`
Expected: PASS (+7 total in file).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/frame_reducer.dart test/features/scan/frame_reducer_test.dart
git commit -m "feat(scan): reduceToGray YUV420 path"
```

---

### Task 4: Wire live detection through gray + refactor segmentation core

**Files:**
- Modify: `lib/features/scan/opencv_edge_detector.dart`
- Test: `test/features/scan/opencv_edge_detector_detectframe_test.dart`, `test/features/scan/opencv_edge_detector_yuv_test.dart` (unchanged — must still pass), plus full scan suite.

**Interfaces:**
- Consumes: `reduceToGray` (Tasks 2-3), `GrayFrame` (Task 1).
- Produces: `const int kLiveDetectMaxSide = 400;` (public); unchanged public `detectFrame(CameraFrame)` / `detect(Uint8List)` signatures; new isolate entry `List<double>? _segmentGrayFrame(GrayFrame)`; new shared `List<double>? _segmentGray(cv.Mat gray)` (takes ownership of `gray`).

This task is mostly a **mechanical refactor of native code that cannot run on the host**, so its verification is: (a) `flutter analyze` clean, (b) the existing detector tests still pass (they host-skip the native assertions), (c) the full scan suite stays green, (d) on-device behaviour (deferred). No new host unit test is added here — `reduceToGray` (Tasks 2-3) already covers the new pure-Dart logic.

- [ ] **Step 1: Add imports and the live-size constant**

At the top of `lib/features/scan/opencv_edge_detector.dart`, add to the imports:
```dart
import 'frame_reducer.dart';
import 'gray_frame.dart';
```
Below `const int _kDetectMaxSide = 1024;`, add:
```dart
/// Longest side (px) for LIVE frame detection — coarser than the still path
/// (`_kDetectMaxSide`) because the live overlay is only a guide; the final crop
/// corners come from `detect()` on the full-resolution still.
const int kLiveDetectMaxSide = 400;
```

- [ ] **Step 2: Rewrite `detectFrame` to reduce-then-segment**

Replace the whole `detectFrame` method body with:
```dart
  @override
  Future<DetectionResult?> detectFrame(CameraFrame frame) async {
    try {
      final gray = reduceToGray(frame, maxSide: kLiveDetectMaxSide);
      final flat = await compute(_segmentGrayFrame, gray).timeout(timeout);
      if (flat == null) return null;
      return _resultFromFlat(flat);
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 3: Remove the dead frame→BGR helpers and old frame runner**

Delete these now-unused top-level members from the file:
- `Future<List<double>?> _computeFrameRunner(CameraFrame frame) => ...`
- `List<double>? _runFramePipeline(CameraFrame frame) { ... }`
- `cv.Mat? _bgrMatFromFrame(CameraFrame frame) { ... }`
- `cv.Mat _bgrFromBgra(CameraFrame frame) { ... }`
- `cv.Mat? _bgrFromYuv420(CameraFrame frame) { ... }`

(Keep the `import 'camera_frame.dart';` — `detectFrame` still takes a `CameraFrame`.)

- [ ] **Step 4: Add the gray isolate entry point**

Add near the other top-level isolate entries (after `_runPipeline`):
```dart
/// Isolate entry (top-level, for `compute()`): wraps a [GrayFrame]'s single-channel
/// bytes as a CV_8UC1 Mat and runs the shared segmentation. Returns the flat
/// 9-element result (see [_resultFromFlat]) or null.
List<double>? _segmentGrayFrame(GrayFrame frame) {
  cv.Mat? gray;
  try {
    gray = cv.Mat.fromList(
        frame.height, frame.width, cv.MatType.CV_8UC1, frame.bytes);
    if (gray.isEmpty) {
      gray.dispose();
      return null;
    }
    final out = _segmentGray(gray); // takes ownership: disposes `gray`
    gray = null;
    return out;
  } catch (_) {
    gray?.dispose();
    return null;
  }
}
```

- [ ] **Step 5: Extract steps 4-7 into `_segmentGray`, shrink `_runPipelineOnMat` to a front-end**

Replace the current `_runPipelineOnMat(cv.Mat bgr)` (the still front-end + segmentation, ~lines 205-346) with the two functions below. The still front-end keeps decode-time resize + grayscale; `_segmentGray` is the existing steps 4-7 (blur → dual-Otsu → close → largest contour → quad → guard → confidence) moved **verbatim**, now taking a gray Mat it owns.

```dart
/// Still-capture front-end: downscale a large capture to `_kDetectMaxSide`,
/// convert to gray, then segment. Takes ownership of [bgr].
List<double>? _runPipelineOnMat(cv.Mat bgr) {
  cv.Mat? mat = bgr, gray;
  try {
    final longest = math.max(mat.rows, mat.cols);
    if (longest > _kDetectMaxSide) {
      final scale = _kDetectMaxSide / longest;
      final resized = cv.resize(
        mat,
        ((mat.cols * scale).round(), (mat.rows * scale).round()),
        interpolation: cv.INTER_AREA,
      );
      mat.dispose();
      mat = resized;
    }
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;
    final out = _segmentGray(gray); // takes ownership: disposes `gray`
    gray = null;
    return out;
  } catch (_) {
    return null;
  } finally {
    mat?.dispose();
    gray?.dispose();
  }
}

/// Shared segmentation core (steps 4-7). Takes ownership of [gray] (single-channel
/// CV_8UC1) and disposes it and all intermediates. Returns the flat 9-element
/// result (see [_resultFromFlat]) or null.
List<double>? _segmentGray(cv.Mat gray) {
  cv.Mat? g = gray, blurred, maskBright, maskDark;
  try {
    final rows = g.rows;
    final cols = g.cols;
    final imageArea = (rows * cols).toDouble();

    // Step 4: Blur so text/texture doesn't fragment the page region.
    blurred = cv.gaussianBlur(g, (_kSegBlur, _kSegBlur), 0);
    g.dispose();
    g = null;

    // ── The block below is the existing steps 5-7 moved verbatim from the old
    //    _runPipelineOnMat (dual-Otsu → close → largest contour → approxPolyDP/
    //    minAreaRect → isPlausiblePage guard → detectionConfidence → best
    //    polarity → normalized flat result). It already references only
    //    `blurred`, `rows`, `cols`, `imageArea`, `maskBright`, `maskDark`. ──
    //    (Paste lines currently spanning "Step 5: Otsu" through the final
    //    `return [ ... ];` unchanged.)

  } catch (_) {
    return null;
  } finally {
    g?.dispose();
    blurred?.dispose();
    maskBright?.dispose();
    maskDark?.dispose();
  }
}
```

When moving the block: the old code created `gray` from `mat` then built `blurred` from `gray`; here `blurred` is built from the incoming `g` instead, and the `mat?.dispose()` line from the old finally is dropped (there is no `mat` in `_segmentGray`). Everything from `// Step 5: Otsu` onward is identical.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/features/scan/opencv_edge_detector.dart`
Expected: `No issues found!` (no unused-element warnings — the deleted helpers are gone; `reduceToGray`/`GrayFrame`/`kLiveDetectMaxSide` are all referenced).

- [ ] **Step 7: Run the detector tests + full scan suite**

Run: `flutter test test/features/scan/`
Expected: PASS — same count as before this task (the two `detectFrame` tests remain host-skip-guarded via `opencvAvailable`; the YUV `detectFrame` "without throwing" test still returns null and passes). No regressions.

- [ ] **Step 8: Commit**

```bash
git add lib/features/scan/opencv_edge_detector.dart
git commit -m "feat(scan): live detection via reduceToGray; share _segmentGray core"
```

---

### Task 5: Lower the live sampling throttle

**Files:**
- Modify: `lib/features/scan/camera_preview_controller_impl.dart:21`

**Interfaces:**
- Consumes: nothing.
- Produces: no API change — behavioural constant only.

Rationale: the 700ms gap capped the overlay at ~1.4 fps. `camera_screen._onFrame` already drops frames while a detection is in flight (`_isDetecting`), so a shorter gap cannot stack detections — it just lets the overlay refresh as fast as the (now-cheaper) pipeline allows. No host test exercises this timing (the fake controller's `emitFrame` bypasses the throttle); verification is the on-device smoothness check in Task 7.

- [ ] **Step 1: Change the constant**

In `lib/features/scan/camera_preview_controller_impl.dart`, replace:
```dart
  static const _kMinSampleGapMs = 700;
```
with:
```dart
  // Overlay refreshes as fast as the pipeline allows; _onFrame's _isDetecting
  // guard prevents detections from stacking, so a short gap is safe.
  static const _kMinSampleGapMs = 150;
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/scan/camera_preview_controller_impl.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/scan/camera_preview_controller_impl.dart
git commit -m "perf(scan): lower live sampling gap 700ms -> 150ms"
```

---

### Task 6: Extend the probe with a 400px presence guard

**Files:**
- Modify: `apps/mobile/tool/detect_probe.py`

**Interfaces:**
- Consumes: nothing (host Python tool).
- Produces: `detect(img, max_side=DETECT_MAX_SIDE)` param; a parity assertion that each fixture's null/non-null outcome and polarity match at both 1024 and 400px.

Note (from the spec): this is an **approximate** presence/polarity guard — the probe downscales via `cv2.resize(BGR, INTER_AREA)` then gray, whereas the live path does nearest-neighbour Y-plane decimation. It confirms the guards still admit the page at ~400px, not exact live pixels (those are covered by `reduceToGray` host tests).

- [ ] **Step 1: Parameterize `detect` by working size**

In `apps/mobile/tool/detect_probe.py`, change the signature:
```python
def detect(img, max_side=DETECT_MAX_SIDE):
    """Return (confidence, areaFrac, fill, polarity) or None."""
    h0, w0 = img.shape[:2]
    longest = max(h0, w0)
    if longest > max_side:
        s = max_side / longest
```
(The `resize` line already uses `s`; only the guard and `s` now reference `max_side`.)

- [ ] **Step 2: Add the parity check in `main`**

In `main()`, after the existing per-case outcome is computed, add a coarse-size check. Replace the body of the `for name, img, expect_polarity in _cases():` loop's tail so that, in addition to the existing 1024px assertion, it also runs `detect(img, max_side=400)` and flags a failure if the coarse outcome disagrees on null-vs-non-null or polarity:
```python
        r400 = detect(img, max_side=400)
        coarse_ok = (r is None) == (r400 is None) and (
            r is None or r[3] == r400[3])
        if not coarse_ok:
            print(f"[FAIL] {name:22s} 400px parity: "
                  f"1024={'NULL' if r is None else r[3]} "
                  f"400={'NULL' if r400 is None else r400[3]}")
            failures += 1
```

- [ ] **Step 3: Run the probe**

Run: `python3 apps/mobile/tool/detect_probe.py`
Expected: exit 0, `0 failure(s)`, and no `400px parity` FAIL lines.
(If a fixture regresses at 400px, bump `kLiveDetectMaxSide` in `opencv_edge_detector.dart` to 480 and re-run — a single-constant tune, no structural change; update Task 4's constant to match.)

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/tool/detect_probe.py
git commit -m "test(scan): probe presence-guard parity at 400px live size"
```

---

### Task 7: On-device timing instrumentation (deferred verification)

**Files:**
- Modify: `lib/features/scan/camera_screen.dart` (the `_onFrame` method)

**Interfaces:**
- Consumes: nothing.
- Produces: debug-only timing log; no behavioural change in release builds.

This measures the full per-frame detection wall-clock so smoothness can be confirmed on RZCY51D0T1K. It is stripped from release builds via `kDebugMode`. On-device run is a **deferred/tracked gap** (like the flash/strobe work), not part of the host green gate.

- [ ] **Step 1: Add a guarded stopwatch around detection**

In `lib/features/scan/camera_screen.dart`, ensure `import 'package:flutter/foundation.dart' show kDebugMode;` is present (add if missing), then wrap the detect call in `_onFrame`:
```dart
    _isDetecting = true;
    try {
      final sw = kDebugMode ? (Stopwatch()..start()) : null;
      final result = await _edgeDetector.detectFrame(frame);
      if (sw != null) {
        debugPrint('[scan] detectFrame ${sw.elapsedMilliseconds}ms');
      }
      if (!mounted) return;
      setState(() {
        _liveResult =
            (result != null && result.confidence >= 0.5) ? result : null;
      });
    } finally {
      _isDetecting = false;
    }
```

- [ ] **Step 2: Analyze + run the scan suite**

Run: `flutter analyze lib/features/scan/camera_screen.dart && flutter test test/features/scan/`
Expected: `No issues found!` and all scan tests PASS (behaviour unchanged; `debugPrint` is inert under test).

- [ ] **Step 3: Commit**

```bash
git add lib/features/scan/camera_screen.dart
git commit -m "chore(scan): debug-only detectFrame timing log for on-device tuning"
```

- [ ] **Step 4: (Deferred, on-device) Verify smoothness**

On RZCY51D0T1K, run the app, open the scanner, and confirm the log reports well under ~200ms per `detectFrame` and the overlay updates smoothly (~5-8 fps). Record the result; this closes the feature's open gap.

---

## Self-Review

**Spec coverage:**
- Sink 1 (700ms throttle) → Task 5. ✓
- Sinks 2-4 (full-res copy / color convert / resize) → Tasks 2-4 (reduce to ~400px gray before the isolate hop; live path skips cvtColor + resize). ✓
- `GrayFrame` + `reduceToGray` components → Tasks 1-3. ✓
- Detector refactor (`_segmentGray` shared core, remove dead helpers, `kLiveDetectMaxSide`) → Task 4. ✓
- Still path unchanged → Task 4 keeps `_runPipelineOnMat` front-end at 1024px. ✓
- Host tests for `reduceToGray`/`GrayFrame` → Tasks 1-3. ✓
- Probe presence-guard at 400px (with approximation caveat) → Task 6. ✓
- On-device timing log + deferred smoothness check → Task 7. ✓
- No interface/fake/existing-test signature changes → verified in Task 4 (Step 7 expects same test count). ✓
- Out-of-scope (worker isolate, accuracy, camera resolution split, features A/C) → not in any task. ✓

**Placeholder scan:** No TBD/TODO/"add error handling". The one delegated block (Task 4 Step 5, "paste steps 5-7 verbatim") is an explicit verbatim move of existing, in-repo code with precise boundaries and the exact local-variable contract stated — not an unspecified placeholder.

**Type consistency:** `GrayFrame{width,height,bytes}` used identically in Tasks 1, 2, 4. `reduceToGray(CameraFrame, {required int maxSide})` identical in Tasks 2, 3, 4. `_segmentGray(cv.Mat gray)` (owns gray) called from both `_segmentGrayFrame` (Task 4 Step 4) and `_runPipelineOnMat` (Step 5). `kLiveDetectMaxSide` defined Task 4 Step 1, referenced Task 4 Step 2 and Task 6 Step 3 note. Consistent.
