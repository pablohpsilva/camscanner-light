# Live Auto-Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-fire the shutter when a live-detected document is held steady, with a countdown ring and an on/off toggle (default ON); the manual shutter always works.

**Architecture:** A pure `AutoCaptureController` consumes one `DetectionResult?` per frame and tracks consecutive frame stability (max per-corner displacement in normalized coords, above a confidence floor). `camera_screen` feeds it in `_onFrame`, drives a countdown ring from its progress, and on the fire signal reuses the existing `_onShutter()` capture path. `CameraPreviewView` gains a toggle button and the ring. No detector, controller, or capture/save changes.

**Tech Stack:** Flutter/Dart, `flutter_test`.

## Global Constraints

- Package name: `mobile`; imports use `package:mobile/features/scan/...`.
- Live detection is gated by the 150ms sampling throttle + the `_isDetecting` in-flight guard (from Feature B) — frame-count stability therefore has a wall-time floor and needs no clock.
- Auto-capture default is **ON**; the manual shutter (`Key('scan-shutter')`) always fires.
- Post-capture goes to the existing review screen — auto-capture reuses `_onShutter()`.
- Tunable constants (single source, on-device tuning is a tracked follow-up): `requiredStableFrames = 6`, `maxCornerDelta = 0.02`, `minConfidence = 0.6`.
- `CropCorners` corners are `topLeft`/`topRight`/`bottomRight`/`bottomLeft` (`Offset`, normalized `[0..1]`).
- Working directory for all commands: `apps/mobile`.

---

### Task 1: `AutoCaptureController` + `AutoCaptureState`

**Files:**
- Create: `lib/features/scan/auto_capture_controller.dart`
- Test: `test/features/scan/auto_capture_controller_test.dart`

**Interfaces:**
- Consumes: `DetectionResult` (`lib/features/scan/edge_detector.dart` — `{CropCorners corners, double confidence}`); `CropCorners` (`lib/features/library/crop_corners.dart`).
- Produces:
  - `class AutoCaptureState { final double progress; final bool shouldFire; const AutoCaptureState({required this.progress, required this.shouldFire}); }`
  - `class AutoCaptureController { AutoCaptureController({int requiredStableFrames = 6, double maxCornerDelta = 0.02, double minConfidence = 0.6}); AutoCaptureState update(DetectionResult? result); void reset(); }`

- [ ] **Step 1: Write the failing tests**

`test/features/scan/auto_capture_controller_test.dart`:
```dart
import 'dart:ui' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/auto_capture_controller.dart';
import 'package:mobile/features/scan/edge_detector.dart';

DetectionResult _res(CropCorners c, double conf) =>
    DetectionResult(corners: c, confidence: conf);

/// A unit-square-ish quad translated by (dx, dy).
CropCorners _quad(double dx, double dy) => CropCorners(
      topLeft: Offset(0.1 + dx, 0.1 + dy),
      topRight: Offset(0.9 + dx, 0.1 + dy),
      bottomRight: Offset(0.9 + dx, 0.9 + dy),
      bottomLeft: Offset(0.1 + dx, 0.9 + dy),
    );

void main() {
  test('null result keeps progress 0 and never fires', () {
    final s = AutoCaptureController().update(null);
    expect(s.progress, 0);
    expect(s.shouldFire, isFalse);
  });

  test('below-minConfidence result resets progress', () {
    final c = AutoCaptureController(requiredStableFrames: 3);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    final s = c.update(_res(_quad(0, 0), 0.4)); // low conf -> reset
    expect(s.progress, 0);
    expect(s.shouldFire, isFalse);
  });

  test('N stable confident frames fire on the Nth, progress climbs to 1', () {
    final c = AutoCaptureController(requiredStableFrames: 3);
    expect(c.update(_res(_quad(0, 0), 0.9)).progress, closeTo(1 / 3, 1e-9));
    expect(c.update(_res(_quad(0, 0), 0.9)).progress, closeTo(2 / 3, 1e-9));
    final third = c.update(_res(_quad(0, 0), 0.9));
    expect(third.progress, 1.0);
    expect(third.shouldFire, isTrue);
  });

  test('a jump larger than maxCornerDelta restarts the count', () {
    final c = AutoCaptureController(requiredStableFrames: 3, maxCornerDelta: 0.02);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    c.update(_res(_quad(0, 0), 0.9)); // count 2
    final moved = c.update(_res(_quad(0.2, 0), 0.9)); // big jump -> count 1
    expect(moved.progress, closeTo(1 / 3, 1e-9));
    expect(moved.shouldFire, isFalse);
  });

  test('displacement at the threshold boundary counts as stable', () {
    final c = AutoCaptureController(requiredStableFrames: 2, maxCornerDelta: 0.05);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    // every corner shifts by exactly 0.05 in x -> per-corner distance == 0.05
    final s = c.update(_res(_quad(0.05, 0), 0.9));
    expect(s.progress, 1.0);
    expect(s.shouldFire, isTrue);
  });

  test('fires once; re-arms after losing the doc or reset()', () {
    final c = AutoCaptureController(requiredStableFrames: 2);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    expect(c.update(_res(_quad(0, 0), 0.9)).shouldFire, isTrue); // fires
    expect(c.update(_res(_quad(0, 0), 0.9)).shouldFire, isFalse); // no re-fire
    c.update(null); // lose the doc -> internal reset
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    expect(c.update(_res(_quad(0, 0), 0.9)).shouldFire, isTrue); // fires again
  });

  test('reset() clears accumulated progress', () {
    final c = AutoCaptureController(requiredStableFrames: 3);
    c.update(_res(_quad(0, 0), 0.9));
    c.update(_res(_quad(0, 0), 0.9));
    c.reset();
    expect(c.update(_res(_quad(0, 0), 0.9)).progress, closeTo(1 / 3, 1e-9));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/scan/auto_capture_controller_test.dart`
Expected: FAIL — `auto_capture_controller.dart` / `AutoCaptureController` not defined.

- [ ] **Step 3: Write the implementation**

`lib/features/scan/auto_capture_controller.dart`:
```dart
import 'dart:math' as math;

import '../library/crop_corners.dart';
import 'edge_detector.dart';

/// Progress toward an automatic capture, emitted once per frame by
/// [AutoCaptureController].
class AutoCaptureState {
  /// Fraction of the required stable dwell accumulated so far, in `[0,1]`.
  final double progress;

  /// True on the frame the dwell is first satisfied. The caller should fire the
  /// shutter and then call [AutoCaptureController.reset].
  final bool shouldFire;

  const AutoCaptureState({required this.progress, required this.shouldFire});
}

/// Tracks whether a live-detected document quad is being held steady, so the
/// scan screen can auto-fire the shutter. Pure and frame-driven (no clock): the
/// live sampling throttle floors the wall-time of [requiredStableFrames].
class AutoCaptureController {
  /// Consecutive stable, confident frames required to fire.
  final int requiredStableFrames;

  /// Max per-corner displacement (normalized `[0..1]` coords) between two frames
  /// still counted as "stable".
  final double maxCornerDelta;

  /// Minimum detection confidence for a frame to count toward stability.
  final double minConfidence;

  AutoCaptureController({
    this.requiredStableFrames = 6,
    this.maxCornerDelta = 0.02,
    this.minConfidence = 0.6,
  });

  CropCorners? _last;
  int _count = 0;
  bool _fired = false;

  /// Feeds one detection [result] (null = no document this frame). Returns the
  /// updated progress and whether the dwell is now satisfied.
  AutoCaptureState update(DetectionResult? result) {
    if (result == null || result.confidence < minConfidence) {
      reset();
      return const AutoCaptureState(progress: 0, shouldFire: false);
    }
    final corners = result.corners;
    if (_last != null && _maxDelta(_last!, corners) > maxCornerDelta) {
      _count = 1; // moved too much — this frame is the new baseline
    } else if (_count < requiredStableFrames) {
      _count += 1;
    }
    _last = corners;
    final fire = _count >= requiredStableFrames && !_fired;
    if (fire) _fired = true;
    return AutoCaptureState(
      progress: (_count / requiredStableFrames).clamp(0.0, 1.0),
      shouldFire: fire,
    );
  }

  /// Clears accumulated stability (call after firing, or when sampling stops).
  void reset() {
    _last = null;
    _count = 0;
    _fired = false;
  }

  static double _maxDelta(CropCorners a, CropCorners b) => [
        (a.topLeft - b.topLeft).distance,
        (a.topRight - b.topRight).distance,
        (a.bottomRight - b.bottomRight).distance,
        (a.bottomLeft - b.bottomLeft).distance,
      ].reduce(math.max);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/scan/auto_capture_controller_test.dart`
Expected: PASS (+7).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scan/auto_capture_controller.dart test/features/scan/auto_capture_controller_test.dart
git commit -m "feat(scan): AutoCaptureController — frame-count stability tracker"
```

---

### Task 2: Auto-capture toggle + countdown ring in `CameraPreviewView`

**Files:**
- Modify: `lib/features/scan/widgets/camera_preview_view.dart`
- Test: `test/features/scan/widgets/camera_preview_view_auto_capture_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 (widget-only).
- Produces (new `CameraPreviewView` params, all optional so existing call sites/tests keep working): `bool autoCaptureEnabled = false`, `VoidCallback? onAutoCaptureToggled`, `double autoCaptureProgress = 0`. New keys: `Key('scan-auto-capture-toggle')`, `Key('scan-auto-capture-ring')`.

- [ ] **Step 1: Write the failing tests**

`test/features/scan/widgets/camera_preview_view_auto_capture_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/widgets/camera_preview_view.dart';

import '../../../support/fake_scan.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('auto-capture toggle is present and invokes the callback',
      (tester) async {
    var toggled = false;
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
      onAutoCaptureToggled: () => toggled = true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-auto-capture-toggle')));
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('toggle icon reflects enabled vs disabled', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
    )));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('scan-auto-capture-toggle')),
          matching: find.byType(Icon),
        )).icon,
        Icons.motion_photos_auto);

    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: false,
    )));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('scan-auto-capture-toggle')),
          matching: find.byType(Icon),
        )).icon,
        Icons.motion_photos_paused);
  });

  testWidgets('ring shows when enabled with progress > 0', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
      autoCaptureProgress: 0.5,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-auto-capture-ring')), findsOneWidget);
  });

  testWidgets('ring hidden when progress is 0', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
      autoCaptureProgress: 0.0,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-auto-capture-ring')), findsNothing);
  });

  testWidgets('ring hidden when disabled even with progress', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: false,
      autoCaptureProgress: 0.8,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-auto-capture-ring')), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/scan/widgets/camera_preview_view_auto_capture_test.dart`
Expected: FAIL — `autoCaptureEnabled`/`onAutoCaptureToggled`/`autoCaptureProgress` are not params of `CameraPreviewView`.

- [ ] **Step 3: Add the params**

In `lib/features/scan/widgets/camera_preview_view.dart`, add these fields after `onFlashModeChanged` (line 21):
```dart
  final bool autoCaptureEnabled;
  final VoidCallback? onAutoCaptureToggled;
  final double autoCaptureProgress;
```
and add to the constructor (after `this.onFlashModeChanged,`):
```dart
    this.autoCaptureEnabled = false,
    this.onAutoCaptureToggled,
    this.autoCaptureProgress = 0,
```

- [ ] **Step 4: Add the toggle-icon getter**

After the `_nextFlash` getter (line 44):
```dart
  IconData get _autoCaptureIcon => autoCaptureEnabled
      ? Icons.motion_photos_auto
      : Icons.motion_photos_paused;
```

- [ ] **Step 5: Add the toggle button (top-left)**

In `build`, immediately after the flash-toggle `Positioned` (the block ending at line 72, before the shutter `Positioned`), insert:
```dart
          Positioned(
            top: 16 + MediaQuery.of(context).viewPadding.top,
            left: 16,
            child: IconButton(
              key: const Key('scan-auto-capture-toggle'),
              icon: Icon(_autoCaptureIcon, color: Colors.white, size: 28),
              tooltip:
                  autoCaptureEnabled ? 'Auto-capture on' : 'Auto-capture off',
              onPressed: () => onAutoCaptureToggled?.call(),
            ),
          ),
```

- [ ] **Step 6: Wrap the shutter with the countdown ring**

Replace the shutter `Positioned`'s child — currently `SizedBox(width: 72, height: 72, child: FloatingActionButton(...))` — with a ring+button stack. The `FloatingActionButton` itself is unchanged; only its wrapper changes:
```dart
            child: SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (autoCaptureEnabled && autoCaptureProgress > 0)
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: CircularProgressIndicator(
                        key: const Key('scan-auto-capture-ring'),
                        value: autoCaptureProgress,
                        strokeWidth: 4,
                        color: Colors.green,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  SizedBox(
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
                ],
              ),
            ),
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter analyze lib/features/scan/widgets/camera_preview_view.dart && flutter test test/features/scan/widgets/camera_preview_view_auto_capture_test.dart test/features/scan/widgets/camera_preview_view_f3_test.dart`
Expected: `No issues found!`; the new file PASSES (+5) and the existing `camera_preview_view_f3_test.dart` still PASSES (unchanged — new params defaulted).

- [ ] **Step 8: Commit**

```bash
git add lib/features/scan/widgets/camera_preview_view.dart test/features/scan/widgets/camera_preview_view_auto_capture_test.dart
git commit -m "feat(scan): auto-capture toggle + countdown ring in CameraPreviewView"
```

---

### Task 3: Wire auto-capture into `CameraScreen`

**Files:**
- Modify: `lib/features/scan/camera_screen.dart`
- Test: `test/features/scan/camera_screen_auto_capture_test.dart`

**Interfaces:**
- Consumes: `AutoCaptureController`/`AutoCaptureState` (Task 1); `CameraPreviewView`'s `autoCaptureEnabled`/`onAutoCaptureToggled`/`autoCaptureProgress` params (Task 2).
- Produces: no new public API — internal wiring only.

- [ ] **Step 1: Write the failing tests**

`test/features/scan/camera_screen_auto_capture_test.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

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

CameraFrame _bgraFrame() => CameraFrame(
      width: 2,
      height: 2,
      format: CameraFrameFormat.bgra8888,
      planes: [
        CameraFramePlane(
            bytes: Uint8List(2 * 2 * 4), bytesPerRow: 8, bytesPerPixel: 4),
      ],
    );

// Non-loadable capture path: a real file through Image.file hangs a host widget
// test; a bad path errors fast so pumpAndSettle works (see camera_screen_capture_test).
FakeCameraPreviewController _fake() =>
    FakeCameraPreviewController(captureReturnPath: '/nonexistent/capture.jpg');

Widget _screen(FakeCameraPreviewController fake) => MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: _confidentResult),
        ),
        repository: FakeDocumentRepository(),
      ),
    );

Future<void> _emitStable(WidgetTester tester, FakeCameraPreviewController fake,
    int n) async {
  for (var i = 0; i < n; i++) {
    fake.emitFrame(_bgraFrame());
    await tester.pump(); // detectFrame future
    await tester.pump(); // setState
  }
}

void main() {
  testWidgets('auto-capture (default ON) fires after N stable frames',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle(); // ready + sampling

    await _emitStable(tester, fake, 6); // requiredStableFrames default
    await tester.pumpAndSettle(); // capture + navigate to review

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
  });

  testWidgets('toggling auto-capture off suppresses auto-fire',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-auto-capture-toggle')));
    await tester.pump();

    await _emitStable(tester, fake, 8); // more than N
    await tester.pumpAndSettle();

    expect(find.byType(CaptureReviewScreen), findsNothing);
  });

  testWidgets('manual shutter still fires when auto-capture is off',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-auto-capture-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/scan/camera_screen_auto_capture_test.dart`
Expected: FAIL — no `scan-auto-capture-toggle` widget yet, and no auto-fire, so `CaptureReviewScreen` is not found in the first test.

- [ ] **Step 3: Add imports + auto-capture state**

In `lib/features/scan/camera_screen.dart`:
- Add to imports (after line 2):
```dart
import 'dart:async';

import 'auto_capture_controller.dart';
```
(`dart:async` provides `unawaited`; `auto_capture_controller.dart` is the Task 1 file.)
- Add fields to `_CameraScreenState` after `DetectionResult? _liveResult;` (line 54):
```dart
  bool _autoCaptureEnabled = true;
  double _autoProgress = 0;
  final AutoCaptureController _autoCapture = AutoCaptureController();
```

- [ ] **Step 4: Feed the tracker in `_onFrame`**

In `_onFrame`, replace the existing `setState` block (currently lines 109-113):
```dart
      if (!mounted) return;
      setState(() {
        _liveResult =
            (result != null && result.confidence >= 0.5) ? result : null;
      });
```
with:
```dart
      if (!mounted) return;
      setState(() {
        _liveResult =
            (result != null && result.confidence >= 0.5) ? result : null;
      });
      if (_autoCaptureEnabled) {
        final auto = _autoCapture.update(result);
        if (auto.shouldFire) {
          _autoCapture.reset();
          setState(() => _autoProgress = 0);
          unawaited(_onShutter());
        } else if (auto.progress != _autoProgress) {
          setState(() => _autoProgress = auto.progress);
        }
      }
```

- [ ] **Step 5: Reset the tracker in `_stopSampling`**

Replace `_stopSampling` (currently lines 90-94):
```dart
  void _stopSampling() {
    if (!_sampling) return;
    _sampling = false;
    _controller.preview.stopSampling();
  }
```
with:
```dart
  void _stopSampling() {
    if (!_sampling) return;
    _sampling = false;
    _controller.preview.stopSampling();
    _autoCapture.reset();
    _autoProgress = 0;
  }
```

- [ ] **Step 6: Add the toggle handler**

After `_onFlashModeChanged` (ends at line 122), add:
```dart
  void _onAutoCaptureToggled() {
    setState(() {
      _autoCaptureEnabled = !_autoCaptureEnabled;
      if (!_autoCaptureEnabled) {
        _autoCapture.reset();
        _autoProgress = 0;
      }
    });
  }
```

- [ ] **Step 7: Pass the params to `CameraPreviewView`**

In `build`, in the `CameraPreviewView(...)` for `ScanStatus.ready` (currently lines 288-299), add after `onFlashModeChanged: _onFlashModeChanged,`:
```dart
                autoCaptureEnabled: _autoCaptureEnabled,
                onAutoCaptureToggled: _onAutoCaptureToggled,
                autoCaptureProgress: _autoProgress,
```

- [ ] **Step 8: Run tests + analyze + full scan suite**

Run: `flutter analyze lib/features/scan/camera_screen.dart && flutter test test/features/scan/camera_screen_auto_capture_test.dart`
Expected: `No issues found!`; the new file PASSES (+3).

Then run the whole scan suite for regressions:
Run: `flutter test test/features/scan/`
Expected: all PASS; count is the previous scan total + the tests added in Tasks 1-3, no failures.

- [ ] **Step 9: Commit**

```bash
git add lib/features/scan/camera_screen.dart test/features/scan/camera_screen_auto_capture_test.dart
git commit -m "feat(scan): auto-fire shutter on steady detection; wire toggle + ring"
```

---

## Self-Review

**Spec coverage:**
- `AutoCaptureController` (frame-count stability, `update`/`reset`, constants) → Task 1. ✓
- Trigger = stable + confident, no coverage gate → Task 1 `update` (confidence floor + displacement). ✓
- Countdown ring + toggle (default ON, manual always works) → Task 2 (ring/toggle widgets) + Task 3 (`_autoCaptureEnabled = true`, reuse `_onShutter`, manual shutter untouched). ✓
- Feed tracker in `_onFrame`, reset in `_stopSampling`, auto-fire via `_onShutter` → Task 3. ✓
- Post-capture → existing review screen (reuses `_onShutter`) → Task 3, asserted via `CaptureReviewScreen`. ✓
- Toggle per-session, not persisted → Task 3 (plain state field, no storage). ✓
- Host tests: pure controller (Task 1), widget ring/toggle (Task 2), N-stable-frames fire / toggle-off / manual-still-works (Task 3). ✓
- Out-of-scope (coverage gate, wall-clock/clock seam, persistence, sound/haptics, auto-accept) → not in any task. ✓
- Deferred on-device tuning of the three constants → noted in Global Constraints; not a task. ✓

**Placeholder scan:** No TBD/TODO/"add error handling". Every code step shows complete code.

**Type consistency:** `AutoCaptureState{progress,shouldFire}` and `AutoCaptureController({requiredStableFrames,maxCornerDelta,minConfidence}).update(DetectionResult?)/reset()` are defined in Task 1 and consumed identically in Task 3. `CameraPreviewView` params `autoCaptureEnabled`/`onAutoCaptureToggled`/`autoCaptureProgress` are defined in Task 2 and passed with matching names/types in Task 3 (`bool`/`VoidCallback`/`double`). Keys `scan-auto-capture-toggle` and `scan-auto-capture-ring` match between Task 2 (definition) and Task 3 (usage). `_onShutter()` (existing) is reused unchanged.
