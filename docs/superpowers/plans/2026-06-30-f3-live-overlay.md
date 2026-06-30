# F3 Live Camera Edge Overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a live green quad outline on the camera preview while the user points the camera at a document, updating every ~800 ms via a throttled sampling loop.

**Architecture:** A `Timer.periodic(800ms)` in `CameraScreen` calls `sampleFrame()` on the `CameraPreviewController` (new method — takes a picture, returns JPEG bytes, deletes the temp file), feeds the bytes to the existing `EdgeDetector`, and stores the result as `_liveResult`. A new `LiveQuadOverlay` widget (`CustomPaint`, no handles, `IgnorePointer`) is stacked over the camera preview in `CameraPreviewView` when `_liveResult` is confident (≥ 0.5). The `EdgeDetector` interface is unchanged.

**Tech Stack:** Flutter/Dart 3.12.2+, `camera` plugin, `dart:async` (Timer, unawaited), existing `EdgeDetector`/`CropCorners` interfaces.

## Global Constraints

- TDD first on every task — write the failing test before the implementation.
- SOLID, KISS, DRY — no extra abstractions beyond what the spec requires.
- `EdgeDetector` interface (`lib/features/scan/edge_detector.dart`) must not be modified.
- Confidence threshold for showing the overlay: `result.confidence >= 0.5`.
- Timer interval: `const Duration(milliseconds: 800)`.
- Overlay widget must carry `const Key('live-quad-overlay')` on its `LayoutBuilder`.
- `previewSize` getter must swap width/height when `sensorOrientation == 90 || == 270`.
- No new `pubspec.yaml` dependencies.
- Run all tests from `apps/mobile/`: `cd apps/mobile && flutter test`.
- Run analyze: `cd apps/mobile && flutter analyze`.

---

### Task 1: Extend `CameraPreviewController` + update both implementations + fake infrastructure

**Files:**
- Modify: `apps/mobile/lib/features/scan/camera_preview_controller.dart`
- Modify: `apps/mobile/lib/features/scan/camera_preview_controller_impl.dart`
- Modify: `apps/mobile/test/support/fake_scan.dart`
- Create: `apps/mobile/test/features/scan/camera_preview_controller_f3_test.dart`

**Interfaces:**
- Produces: `Future<Uint8List?> sampleFrame()` and `Size get previewSize` on `CameraPreviewController`; `FakeCameraPreviewController` gains `sampleFrameResult`, `sampleFrameCalls`, `sampleFrame()`, `previewSize`; `liveDetectionScanDependencies` factory in `fake_scan.dart`.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/scan/camera_preview_controller_f3_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/edge_detector.dart';

import '../../support/fake_scan.dart';

void main() {
  group('FakeCameraPreviewController.sampleFrame', () {
    test('returns sampleFrameResult when set', () async {
      final controller = FakeCameraPreviewController(
        sampleFrameResult: Uint8List.fromList([1, 2, 3]),
      );
      final result = await controller.sampleFrame();
      expect(result, equals(Uint8List.fromList([1, 2, 3])));
      expect(controller.sampleFrameCalls, 1);
    });

    test('returns null when sampleFrameResult is null', () async {
      final controller = FakeCameraPreviewController();
      final result = await controller.sampleFrame();
      expect(result, isNull);
      expect(controller.sampleFrameCalls, 1);
    });

    test('increments sampleFrameCalls on each call', () async {
      final controller = FakeCameraPreviewController();
      await controller.sampleFrame();
      await controller.sampleFrame();
      expect(controller.sampleFrameCalls, 2);
    });
  });

  group('FakeCameraPreviewController.previewSize', () {
    test('returns 1920x1080', () {
      final controller = FakeCameraPreviewController();
      expect(controller.previewSize, const Size(1920, 1080));
    });
  });

  group('liveDetectionScanDependencies', () {
    const confidentResult = DetectionResult(
      corners: CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      ),
      confidence: 0.8,
    );

    test('edge detector returns configured result', () async {
      final deps = liveDetectionScanDependencies(
          detectionResult: confidentResult);
      final detector = deps.createEdgeDetector();
      final result = await detector.detect(Uint8List.fromList([0]));
      expect(result, confidentResult);
    });

    test('edge detector returns null when configured as null', () async {
      final deps =
          liveDetectionScanDependencies(detectionResult: null);
      final detector = deps.createEdgeDetector();
      final result = await detector.detect(Uint8List.fromList([0]));
      expect(result, isNull);
    });

    test('preview controller sampleFrame returns kFakeJpegBytes by default',
        () async {
      final deps =
          liveDetectionScanDependencies(detectionResult: null);
      final controller = deps.createPreviewController()
          as FakeCameraPreviewController;
      final bytes = await controller.sampleFrame();
      expect(bytes, kFakeJpegBytes);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd apps/mobile && flutter test test/features/scan/camera_preview_controller_f3_test.dart
```

Expected: compile error — `sampleFrame`, `sampleFrameCalls`, `previewSize`, `liveDetectionScanDependencies` not defined.

- [ ] **Step 3: Add `sampleFrame()` and `previewSize` to the interface**

Replace `apps/mobile/lib/features/scan/camera_preview_controller.dart` with:

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'captured_image.dart';

/// Thrown when the device has no usable camera, or it fails to initialize.
class CameraUnavailableException implements Exception {
  final String message;
  const CameraUnavailableException(this.message);

  @override
  String toString() => 'CameraUnavailableException: $message';
}

/// Abstraction over the live camera preview (DIP). Production wraps the
/// `camera` plugin; tests inject a fake that paints a placeholder, so on-device
/// integration tests are deterministic without real camera hardware.
abstract interface class CameraPreviewController {
  /// Initializes the device camera. Throws [CameraUnavailableException] if no
  /// camera exists or initialization fails.
  Future<void> initialize();

  /// Builds the live preview widget. Only valid after [initialize] succeeds.
  Widget buildPreview();

  /// Captures a still image to a temporary file. Only valid after [initialize]
  /// succeeds. Throws [CameraUnavailableException] if capture fails.
  Future<CapturedImage> capture();

  /// Returns JPEG bytes of a sampled still frame, or null on any error.
  /// Only valid after [initialize()] succeeds. Never throws.
  Future<Uint8List?> sampleFrame();

  /// Camera native resolution in display-space coordinates — width and height
  /// are already swapped when sensor orientation is 90° or 270°. Valid after
  /// [initialize()] succeeds.
  Size get previewSize;

  /// Releases the camera.
  Future<void> dispose();
}
```

- [ ] **Step 4: Implement `sampleFrame()` and `previewSize` in the production controller**

Replace `apps/mobile/lib/features/scan/camera_preview_controller_impl.dart` with:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_preview_controller.dart';
import 'captured_image.dart';

/// Production [CameraPreviewController] backed by the `camera` plugin.
class PluginCameraPreviewController implements CameraPreviewController {
  PluginCameraPreviewController();

  CameraController? _controller;

  @override
  Future<void> initialize() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw CameraUnavailableException(e.description ?? e.code);
    }
    if (cameras.isEmpty) {
      throw const CameraUnavailableException('No camera available');
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw CameraUnavailableException(e.description ?? e.code);
    }
    _controller = controller;
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('buildPreview() called before initialize() succeeded');
    }
    return CameraPreview(controller);
  }

  @override
  Future<CapturedImage> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraUnavailableException('capture() before initialize()');
    }
    try {
      final file = await controller.takePicture();
      return CapturedImage(file.path);
    } on CameraException catch (e) {
      throw CameraUnavailableException(e.description ?? e.code);
    }
  }

  @override
  Future<Uint8List?> sampleFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      final file = await controller.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Size get previewSize {
    final controller = _controller!;
    final size = controller.value.previewSize;
    final rot = controller.description.sensorOrientation;
    return (rot == 90 || rot == 270)
        ? Size(size.height, size.width)
        : size;
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
```

- [ ] **Step 5: Update `FakeCameraPreviewController` and add `liveDetectionScanDependencies`**

In `apps/mobile/test/support/fake_scan.dart`, make these changes:

**a) Add `sampleFrameResult` to `FakeCameraPreviewController`:**

Find the class definition and replace the constructor + fields block:

```dart
class FakeCameraPreviewController implements CameraPreviewController {
  final bool unavailable;
  final String? captureReturnPath;
  final Uint8List? sampleFrameResult;  // NEW
  bool disposed = false;
  bool captureCalled = false;
  int sampleFrameCalls = 0;            // NEW
  CameraUnavailableException? captureError;

  FakeCameraPreviewController({
    this.unavailable = false,
    this.captureReturnPath,
    this.sampleFrameResult,             // NEW
  });
```

**b) Add `sampleFrame()` and `previewSize` implementations** at the end of `FakeCameraPreviewController` (before the closing `}`):

```dart
  @override
  Future<Uint8List?> sampleFrame() async {
    sampleFrameCalls++;
    return sampleFrameResult;
  }

  @override
  Size get previewSize => const Size(1920, 1080);
```

**c) Add `liveDetectionScanDependencies` factory** at the bottom of the file (after the existing factory functions):

```dart
/// [ScanDependencies] with controllable frame sampling and edge detection.
/// Use in F3 widget and BDD tests. The preview controller returns
/// [sampleFrameResult] (defaults to [kFakeJpegBytes]) from [sampleFrame()];
/// the edge detector returns [detectionResult] from [detect()].
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

- [ ] **Step 6: Run tests — expect green**

```bash
cd apps/mobile && flutter test test/features/scan/camera_preview_controller_f3_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Verify analyze is clean**

```bash
cd apps/mobile && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/scan/camera_preview_controller.dart \
        apps/mobile/lib/features/scan/camera_preview_controller_impl.dart \
        apps/mobile/test/support/fake_scan.dart \
        apps/mobile/test/features/scan/camera_preview_controller_f3_test.dart
git commit -m "feat(f3): add sampleFrame() + previewSize to CameraPreviewController; update fake"
```

---

### Task 2: `LiveQuadOverlay` widget

**Files:**
- Create: `apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart`
- Create: `apps/mobile/test/features/scan/widgets/live_quad_overlay_test.dart`

**Interfaces:**
- Consumes: `CropCorners` from `lib/features/library/crop_corners.dart`
- Produces: `LiveQuadOverlay(corners: CropCorners, previewSize: Size, color: Color)` with `Key('live-quad-overlay')` on the `LayoutBuilder`

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/scan/widgets/live_quad_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders with Key(live-quad-overlay)', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: const Size(1920, 1080),
        color: Colors.green,
      ),
    )));
    expect(find.byKey(const Key('live-quad-overlay')), findsOneWidget);
  });

  testWidgets('contains a CustomPaint', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: const Size(1920, 1080),
        color: Colors.green,
      ),
    )));
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('fills its parent container', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: const Size(1920, 1080),
        color: Colors.green,
      ),
    )));
    final size =
        tester.getSize(find.byKey(const Key('live-quad-overlay')));
    expect(size, const Size(400, 300));
  });

  testWidgets('handles zero previewSize gracefully', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: Size.zero,
        color: Colors.green,
      ),
    )));
    // Should not throw — falls back to empty box
    expect(find.byKey(const Key('live-quad-overlay')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd apps/mobile && flutter test test/features/scan/widgets/live_quad_overlay_test.dart
```

Expected: compile error — `LiveQuadOverlay` not defined.

- [ ] **Step 3: Implement `LiveQuadOverlay`**

Create `apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';

/// Draws a quad outline (green when confident) over the live camera preview.
/// Non-interactive — callers wrap in [IgnorePointer]. Fitted-rect math
/// matches [CropOverlay] so normalized corners align correctly.
class LiveQuadOverlay extends StatelessWidget {
  final CropCorners corners;
  final Size previewSize;
  final Color color;

  const LiveQuadOverlay({
    super.key,
    required this.corners,
    required this.previewSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('live-quad-overlay'),
      builder: (context, constraints) {
        if (previewSize.width <= 0 || previewSize.height <= 0) {
          return const SizedBox.expand();
        }
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = math.min(
          box.width / previewSize.width,
          box.height / previewSize.height,
        );
        final display = previewSize * scale;
        final rect = Offset(
              (box.width - display.width) / 2,
              (box.height - display.height) / 2,
            ) &
            display;

        Offset pixelOf(Offset n) =>
            rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height);

        return CustomPaint(
          size: box,
          painter: _LiveQuadPainter(
            points: [
              pixelOf(corners.topLeft),
              pixelOf(corners.topRight),
              pixelOf(corners.bottomRight),
              pixelOf(corners.bottomLeft),
            ],
            color: color,
          ),
        );
      },
    );
  }
}

class _LiveQuadPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  const _LiveQuadPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiveQuadPainter old) =>
      old.points != points || old.color != color;
}
```

- [ ] **Step 4: Run tests — expect green**

```bash
cd apps/mobile && flutter test test/features/scan/widgets/live_quad_overlay_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart \
        apps/mobile/test/features/scan/widgets/live_quad_overlay_test.dart
git commit -m "feat(f3): LiveQuadOverlay widget — quad outline painter for live detection"
```

---

### Task 3: Wire overlay into `CameraPreviewView`

**Files:**
- Modify: `apps/mobile/lib/features/scan/widgets/camera_preview_view.dart`
- Create: `apps/mobile/test/features/scan/widgets/camera_preview_view_f3_test.dart`

**Interfaces:**
- Consumes: `LiveQuadOverlay` (Task 2), `CropCorners`
- Produces: `CameraPreviewView` gains optional `liveCorners: CropCorners?` and `previewSize: Size?`; renders `IgnorePointer(child: LiveQuadOverlay(...))` between preview and shutter when both are non-null

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/scan/widgets/camera_preview_view_f3_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/camera_preview_view.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

import '../../../support/fake_scan.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('no overlay when liveCorners is null', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LiveQuadOverlay), findsNothing);
    expect(find.byKey(const Key('live-quad-overlay')), findsNothing);
  });

  testWidgets('overlay appears when liveCorners and previewSize are set',
      (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      liveCorners: CropCorners.fullFrame,
      previewSize: const Size(1920, 1080),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LiveQuadOverlay), findsOneWidget);
    expect(find.byKey(const Key('live-quad-overlay')), findsOneWidget);
  });

  testWidgets('shutter button is tappable when overlay is shown',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () => tapped = true,
      liveCorners: CropCorners.fullFrame,
      previewSize: const Size(1920, 1080),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('overlay absent when only liveCorners set (no previewSize)',
      (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      liveCorners: CropCorners.fullFrame,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LiveQuadOverlay), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd apps/mobile && flutter test test/features/scan/widgets/camera_preview_view_f3_test.dart
```

Expected: compile error — `liveCorners`, `previewSize` params don't exist on `CameraPreviewView`.

- [ ] **Step 3: Update `CameraPreviewView`**

Replace `apps/mobile/lib/features/scan/widgets/camera_preview_view.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';
import '../camera_preview_controller.dart';
import 'live_quad_overlay.dart';

/// Frames the live preview with a shutter button. [onShutter] fires on tap;
/// while [capturing] is true the button shows progress and is disabled.
/// When [liveCorners] and [previewSize] are both non-null, draws a
/// [LiveQuadOverlay] (green quad, non-interactive) over the preview.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;
  final VoidCallback onShutter;
  final bool capturing;
  final CropCorners? liveCorners;
  final Size? previewSize;

  const CameraPreviewView({
    super.key,
    required this.controller,
    required this.onShutter,
    this.capturing = false,
    this.liveCorners,
    this.previewSize,
  });

  @override
  Widget build(BuildContext context) {
    final corners = liveCorners;
    final size = previewSize;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: controller.buildPreview()),
          if (corners != null && size != null)
            IgnorePointer(
              child: LiveQuadOverlay(
                corners: corners,
                previewSize: size,
                color: Colors.green,
              ),
            ),
          Positioned(
            bottom: 32,
            child: SizedBox(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                key: const Key('scan-shutter'),
                heroTag: 'scan-shutter',
                onPressed: capturing ? null : onShutter,
                shape: const CircleBorder(),
                backgroundColor: Colors.white,
                child: capturing
                    ? const CircularProgressIndicator(
                        key: Key('scan-shutter-busy'))
                    : const Icon(Icons.camera_alt, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests — expect green**

```bash
cd apps/mobile && flutter test test/features/scan/widgets/camera_preview_view_f3_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Run the full suite — no regressions**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass (existing `camera_screen_test.dart` still works because the new params are optional).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/widgets/camera_preview_view.dart \
        apps/mobile/test/features/scan/widgets/camera_preview_view_f3_test.dart
git commit -m "feat(f3): CameraPreviewView shows LiveQuadOverlay with IgnorePointer when liveCorners set"
```

---

### Task 4: `CameraScreen` periodic detection loop

**Files:**
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Create: `apps/mobile/test/features/scan/camera_screen_f3_test.dart`

**Interfaces:**
- Consumes: `liveDetectionScanDependencies` (Task 1), `LiveQuadOverlay` (Task 2), `CameraPreviewView.liveCorners` (Task 3)
- Produces: `CameraScreen` with `_sampleTimer`, `_doSample()`, `_liveResult`; passes `liveCorners: _liveResult?.corners` and `previewSize` to `CameraPreviewView`

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/scan/camera_screen_f3_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

const _confidentResult = DetectionResult(
  corners: CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  ),
  confidence: 0.8,
);

const _lowConfResult = DetectionResult(
  corners: CropCorners.fullFrame,
  confidence: 0.3,
);

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('overlay appears after timer fires with confident detection',
      (tester) async {
    await tester.pumpWidget(host(CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: _confidentResult),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle(); // camera reaches ScanStatus.ready

    expect(find.byType(LiveQuadOverlay), findsNothing);

    await tester.pump(const Duration(milliseconds: 900)); // fire 800ms timer
    await tester.pump(); // drain sampleFrame microtask
    await tester.pump(); // drain detect microtask + setState rebuild

    expect(find.byType(LiveQuadOverlay), findsOneWidget);
  });

  testWidgets('overlay absent when detection returns null', (tester) async {
    await tester.pumpWidget(host(CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: null),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsNothing);
  });

  testWidgets('overlay absent when confidence is below 0.5', (tester) async {
    await tester.pumpWidget(host(CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: _lowConfResult),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsNothing);
  });

  testWidgets('sampleFrame is called after timer fires', (tester) async {
    final fakeController = FakeCameraPreviewController(
      sampleFrameResult: kFakeJpegBytes,
    );
    await tester.pumpWidget(host(CameraScreen(
      dependencies: ScanDependencies(
        createPermissionService: () =>
            FakeCameraPermissionService(CameraPermissionStatus.granted),
        createPreviewController: () => fakeController,
        createEdgeDetector: () =>
            FakeEdgeDetector(result: _confidentResult),
      ),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle();

    expect(fakeController.sampleFrameCalls, 0);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(fakeController.sampleFrameCalls, greaterThan(0));
  });
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd apps/mobile && flutter test test/features/scan/camera_screen_f3_test.dart
```

Expected: tests compile but fail — `LiveQuadOverlay` not found in the widget tree (camera screen doesn't have the detection loop yet).

- [ ] **Step 3: Replace `camera_screen.dart` with the updated version**

Replace `apps/mobile/lib/features/scan/camera_screen.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/save_controller.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'scan_controller.dart';
import 'scan_dependencies.dart';
import 'scan_view_state.dart';
import 'widgets/camera_preview_view.dart';
import 'widgets/camera_unavailable_view.dart';
import 'widgets/permission_denied_view.dart';

/// The Scan screen: requests camera permission and shows the live preview, or
/// a graceful fallback. Capture (shutter) → review screen lives here (A3/B1).
/// F3: periodic detection loop draws a live quad outline on the preview.
class CameraScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;

  const CameraScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final ScanController _controller;
  late final SaveController _saveController;
  late final EdgeDetector _edgeDetector;
  Timer? _sampleTimer;
  DetectionResult? _liveResult;
  bool _isSampling = false;

  @override
  void initState() {
    super.initState();
    _controller = ScanController(
      permission: widget.dependencies.createPermissionService(),
      preview: widget.dependencies.createPreviewController(),
    );
    _controller.start();
    _saveController = SaveController(repository: widget.repository);
    _edgeDetector = widget.dependencies.createEdgeDetector();
    _startSampleTimer();
  }

  void _startSampleTimer() {
    _sampleTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_doSample()),
    );
  }

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

  @override
  void dispose() {
    _sampleTimer?.cancel();
    // _edgeDetector is not disposed — OpenCvEdgeDetector is a const stateless instance.
    _controller.dispose();
    _saveController.dispose();
    super.dispose();
  }

  Future<void> _onShutter() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final image = await _controller.capture();
    if (!mounted) return;
    if (image == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Try again.')),
      );
      if (mounted && _controller.status == ScanStatus.ready) {
        _startSampleTimer();
      }
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            edgeDetector: _edgeDetector,
            saving: _saveController.saving,
            onRetake: navigator.pop,
            onAccept: (corners) => _onAccept(image, corners),
          ),
        ),
      ),
    );
    if (mounted && _controller.status == ScanStatus.ready) {
      _startSampleTimer();
    }
  }

  Future<void> _onAccept(CapturedImage image, CropCorners corners) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final doc = await _saveController.save(image, corners: corners);
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save document. Try again.")),
      );
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          switch (_controller.status) {
            case ScanStatus.checking:
              return const Center(
                key: Key('scan-checking'),
                child: CircularProgressIndicator(),
              );
            case ScanStatus.ready:
              return CameraPreviewView(
                key: const Key('scan-preview'),
                controller: _controller.preview,
                capturing: _controller.capturing,
                onShutter: _onShutter,
                liveCorners: _liveResult?.corners,
                previewSize: _controller.preview.previewSize,
              );
            case ScanStatus.permissionDenied:
              return PermissionDeniedView(
                permanentlyDenied: _controller.permanentlyDenied,
                onOpenSettings: _controller.openSettings,
              );
            case ScanStatus.unavailable:
              return const CameraUnavailableView();
          }
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run F3 tests — expect green**

```bash
cd apps/mobile && flutter test test/features/scan/camera_screen_f3_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Run the full suite — no regressions**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/camera_screen.dart \
        apps/mobile/test/features/scan/camera_screen_f3_test.dart
git commit -m "feat(f3): CameraScreen periodic detection loop — live quad overlay on camera preview"
```

---

### Task 5: BDD feature file, step definitions, and codegen

**Files:**
- Create: `apps/mobile/integration_test/f3_live_overlay.feature`
- Create: `apps/mobile/test/step/the_camera_is_ready_with_a_detector_returning_confident_corners.dart`
- Create: `apps/mobile/test/step/the_camera_is_ready_with_a_detector_returning_no_result.dart`
- Create: `apps/mobile/test/step/the_live_overlay_sample_timer_fires.dart`
- Create: `apps/mobile/test/step/the_live_quad_overlay_is_visible_on_the_camera_preview.dart`
- Create: `apps/mobile/test/step/no_live_quad_overlay_is_visible_on_the_camera_preview.dart`
- Generated: `apps/mobile/integration_test/f3_live_overlay_test.dart`

**Interfaces:**
- Consumes: `liveDetectionScanDependencies` (Task 1), `LiveQuadOverlay` key (Task 2), `CameraScreen` (Task 4)

- [ ] **Step 1: Write the feature file**

Create `apps/mobile/integration_test/f3_live_overlay.feature`:

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

- [ ] **Step 2: Write step definitions**

Create `apps/mobile/test/step/the_camera_is_ready_with_a_detector_returning_confident_corners.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

const _confidentResult = DetectionResult(
  corners: CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  ),
  confidence: 0.8,
);

/// Usage: the camera is ready with a detector returning confident corners
Future<void> theCameraIsReadyWithADetectorReturningConfidentCorners(
    WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: _confidentResult),
      repository: FakeDocumentRepository(),
    ),
  ));
  await tester.pumpAndSettle();
}
```

Create `apps/mobile/test/step/the_camera_is_ready_with_a_detector_returning_no_result.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_screen.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the camera is ready with a detector returning no result
Future<void> theCameraIsReadyWithADetectorReturningNoResult(
    WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: CameraScreen(
      dependencies: liveDetectionScanDependencies(detectionResult: null),
      repository: FakeDocumentRepository(),
    ),
  ));
  await tester.pumpAndSettle();
}
```

Create `apps/mobile/test/step/the_live_overlay_sample_timer_fires.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

/// Usage: the live overlay sample timer fires
Future<void> theLiveOverlaySampleTimerFires(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();
  await tester.pump();
}
```

Create `apps/mobile/test/step/the_live_quad_overlay_is_visible_on_the_camera_preview.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the live quad overlay is visible on the camera preview
Future<void> theLiveQuadOverlayIsVisibleOnTheCameraPreview(
    WidgetTester tester) async {
  expect(
    find.byKey(const Key('live-quad-overlay')),
    findsOneWidget,
    reason: 'LiveQuadOverlay should be visible after confident detection',
  );
}
```

Create `apps/mobile/test/step/no_live_quad_overlay_is_visible_on_the_camera_preview.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: no live quad overlay is visible on the camera preview
Future<void> noLiveQuadOverlayIsVisibleOnTheCameraPreview(
    WidgetTester tester) async {
  expect(
    find.byKey(const Key('live-quad-overlay')),
    findsNothing,
    reason: 'LiveQuadOverlay should not be visible when no confident detection',
  );
}
```

- [ ] **Step 3: Run codegen**

```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs 2>&1
```

Expected output contains: `Built with build_runner`

This generates `apps/mobile/integration_test/f3_live_overlay_test.dart`.

- [ ] **Step 4: Verify the generated file imports the correct step functions**

The generated file should contain:
```dart
theCameraIsReadyWithADetectorReturningConfidentCorners(tester)
theLiveOverlaySampleTimerFires(tester)
theLiveQuadOverlayIsVisibleOnTheCameraPreview(tester)
theCameraIsReadyWithADetectorReturningNoResult(tester)
noLiveQuadOverlayIsVisibleOnTheCameraPreview(tester)
```

Run:
```bash
grep "theCameraIsReady\|theLiveOverlay\|noLiveQuad" apps/mobile/integration_test/f3_live_overlay_test.dart
```

Expected: all five function names found.

- [ ] **Step 5: Run the full suite**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/integration_test/f3_live_overlay.feature \
        apps/mobile/integration_test/f3_live_overlay_test.dart \
        apps/mobile/test/step/the_camera_is_ready_with_a_detector_returning_confident_corners.dart \
        apps/mobile/test/step/the_camera_is_ready_with_a_detector_returning_no_result.dart \
        apps/mobile/test/step/the_live_overlay_sample_timer_fires.dart \
        apps/mobile/test/step/the_live_quad_overlay_is_visible_on_the_camera_preview.dart \
        apps/mobile/test/step/no_live_quad_overlay_is_visible_on_the_camera_preview.dart
git commit -m "test(f3): BDD scenarios + step definitions + generated test"
```

---

### Task 6: Verify script

**Files:**
- Create: `scripts/verify/f3.sh`

**Interfaces:**
- Consumes: everything from Tasks 1–5; `scripts/verify/lib.sh`

- [ ] **Step 1: Create `scripts/verify/f3.sh`**

```bash
#!/usr/bin/env bash
# Verify F3 (live camera edge overlay) acceptance criteria.
# Run: bash scripts/verify/f3.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== F3 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git

# ---- Source presence (static asserts) ----
assert_file_has "LiveQuadOverlay widget exists" \
  "apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart" "class LiveQuadOverlay"
assert_file_has "LiveQuadOverlay has test key" \
  "apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart" "live-quad-overlay"
assert_file_has "CameraPreviewController declares sampleFrame" \
  "apps/mobile/lib/features/scan/camera_preview_controller.dart" "sampleFrame"
assert_file_has "CameraPreviewController declares previewSize" \
  "apps/mobile/lib/features/scan/camera_preview_controller.dart" "previewSize"
assert_file_has "PluginCameraPreviewController implements sampleFrame" \
  "apps/mobile/lib/features/scan/camera_preview_controller_impl.dart" "sampleFrame"
assert_file_has "previewSize swaps for sensor orientation" \
  "apps/mobile/lib/features/scan/camera_preview_controller_impl.dart" "sensorOrientation"
assert_file_has "CameraPreviewView has liveCorners param" \
  "apps/mobile/lib/features/scan/widgets/camera_preview_view.dart" "liveCorners"
assert_file_has "CameraPreviewView uses IgnorePointer" \
  "apps/mobile/lib/features/scan/widgets/camera_preview_view.dart" "IgnorePointer"
assert_file_has "CameraScreen has _sampleTimer" \
  "apps/mobile/lib/features/scan/camera_screen.dart" "_sampleTimer"
assert_file_has "CameraScreen has _doSample" \
  "apps/mobile/lib/features/scan/camera_screen.dart" "_doSample"
assert_file_has "CameraScreen guards _isSampling" \
  "apps/mobile/lib/features/scan/camera_screen.dart" "_isSampling"
assert_file_has "EdgeDetector interface is unchanged" \
  "apps/mobile/lib/features/scan/edge_detector.dart" "Future<DetectionResult?> detect"
assert_file_has "liveDetectionScanDependencies factory exists" \
  "apps/mobile/test/support/fake_scan.dart" "liveDetectionScanDependencies"
assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/f3_live_overlay.feature" "live edge overlay"
assert_file_has "generated test calls confident-corners step" \
  "apps/mobile/integration_test/f3_live_overlay_test.dart" "theCameraIsReadyWithADetectorReturningConfidentCorners"
assert_file_has "generated test calls timer step" \
  "apps/mobile/integration_test/f3_live_overlay_test.dart" "theLiveOverlaySampleTimerFires"
assert_file_has "generated test calls overlay-visible step" \
  "apps/mobile/integration_test/f3_live_overlay_test.dart" "theLiveQuadOverlayIsVisibleOnTheCameraPreview"

# ---- Generated code is current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (f3 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/f3_live_overlay_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- OpenCV host library (required by scan tests in the shared suite) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "f3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: BDD integration test ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android f3_live_overlay_test.dart
verify_integration_ios f3_live_overlay_test.dart

verify_summary
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x scripts/verify/f3.sh
```

- [ ] **Step 3: Run the verify script (skipping device)**

```bash
VERIFY_SKIP_DEVICE=1 bash scripts/verify/f3.sh
```

Expected: all static assertions pass; tests green; analyze clean; coverage ≥ 70%; one intentional FAIL for the device-skip gate. Summary: `N passed, 1 failed`.

- [ ] **Step 4: Commit**

```bash
git add scripts/verify/f3.sh
git commit -m "test(f3): verify script f3.sh — static assertions + host tests + coverage gate"
```
