# A3 — Capture Photo → Review Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the camera-ready state, tapping a **shutter** captures one still JPEG to a temporary file and opens a **review screen** where the user can **Retake** (back to the live preview) or **Accept** (back to the Documents home).

**Architecture:** Capture extends the existing A2 seam: a `capture()` method is added to the `CameraPreviewController` interface (the same object that already wraps the plugin's single `CameraController`, which owns `takePicture()`), so the fake-injection seam used by the on-device gate stays intact. `ScanController` gains a `capture()` method and a transient `capturing` flag (double-tap guard + dispose-safety, mirroring the b81da16 `start()` fix). A new stateless `CaptureReviewScreen` renders the captured file; `CameraScreen` wires shutter → review → Retake/Accept navigation. No persistence, no multi-page, no crop/warp/enhance.

**Tech Stack:** Flutter (Dart 3, Material 3), `camera`, `flutter_test`, `integration_test`, `bdd_widget_test` + `build_runner`. Nx target wrappers (`pnpm nx run mobile:test|analyze`). Verify harness `scripts/verify/lib.sh`.

## Global Constraints

Copied verbatim from `../specs/00-overview-roadmap.md` and `../specs/features/01-document-scanning.md` — every task's requirements implicitly include these:

- **TDD/BDD first, always.** Write the failing test before the implementation. Every feature, class, component, and function must be **SOLID, KISS, DRY**.
- **Privacy spine:** documents never leave the device. No cloud, no network calls. A3 writes the capture to the app's **temporary directory only** (the `camera` plugin's default `takePicture()` location). No new networking.
- **Capture quality (Feature 01):** "Highest available still, capped (~12 MP) — fixed/automatic, not a user setting (KISS)"; "Output format: JPEG, q≈90". A3 uses the plugin's `ResolutionPreset.high` already configured in A2's `PluginCameraPreviewController` and the plugin's default JPEG output — **do not add a resolution/format user setting** (YAGNI).
- **Capture output is temp file paths (Feature 01 "Output"):** "One or more raw captured images (file paths in temp storage)." A3 produces exactly this and hands it to the review screen. **Durable persistence is B1 — do NOT save/record the document here.**
- **Graceful errors, no crash (Feature 01):** capture failure must not crash; surface a non-fatal message and stay on the preview.
- **Definition of Done (binding):** a step is done only when every acceptance criterion maps to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and **observed green**, quality gates pass, and the work is reviewed and double-checked. "Looks right"/"should pass" is **not** done.
- **Verification harness (binding):** the step ships `scripts/verify/a3.sh` (built on `scripts/verify/lib.sh`) encoding each acceptance criterion as an assert — exact command + success marker, exit-code check, caches disabled (`--skip-nx-cache`), **silence = FAIL**. The gate is that script exiting 0, observed by an **independent adversarial verifier** from a clean state.
- **On-device UI is authoritative via `integration_test`, not screenshots.** The UI ships a BDD `.feature` → generated `integration_test/a3_capture_review_test.dart` that pumps the real app on each device and asserts the rendered widget tree (run via `verify_integration_{android,ios}`), **mutation-checked once**.
- **BDD-from-.feature standard (from A3 onwards):** scenarios authored as `.feature` (Gherkin) under `apps/mobile/integration_test/`, generated via `bdd_widget_test` + `build_runner`; step defs in `apps/mobile/test/step/` (shared); generated `*_test.dart` committed. The gate runs the committed generated test, NOT `build_runner`.

**App identifiers (already configured — do not change):** Android `applicationId`/`namespace` = `com.camscannerlight.mobile`; package name `mobile`.

**Out of scope (later steps — do NOT build):** durable save / document record (B1), multi-page / batch capture (Feature 06 / H1–H5), corner crop / perspective flatten (E), auto edge detection (F), enhancement filters (G), capture modes / torch / grid / tap-to-focus / auto-capture (later capture steps), EXIF/metadata scrubbing (cross-cutting, **designed in Feature 07**, applies when files are persisted/exported — **tracked deferred gap**, see "Known deferred gaps" at the end; do NOT implement a scrubber here).

---

## Scope (A3 only)

**In scope:** a shutter button in the camera-ready state; a single still capture to a temp JPEG via the existing preview seam; a `CaptureReviewScreen` showing the captured image with Retake/Accept; navigation (Retake → live preview, Accept → Documents home); a double-tap/in-flight guard and dispose-safety on capture; graceful capture-failure handling; the A3 BDD scenarios + verify gate; an **opt-in** `REAL_DEVICE=1` real-camera smoke lane.

## File Structure

Feature folder `apps/mobile/lib/features/scan/`:

| File | Change | Responsibility |
|---|---|---|
| `captured_image.dart` | **Create** | `CapturedImage` value type — the temp-file path of one capture. |
| `camera_preview_controller.dart` | **Modify** | Add `Future<CapturedImage> capture()` to the interface. |
| `camera_preview_controller_impl.dart` | **Modify** | Implement `capture()` via the plugin's `takePicture()`. |
| `scan_controller.dart` | **Modify** | Add `capture()` + `capturing` flag (guarded, dispose-safe). |
| `widgets/camera_preview_view.dart` | **Modify** | Add a shutter button (`Key('scan-shutter')`); progress + disabled while capturing. |
| `capture_review_screen.dart` | **Create** | Stateless review screen: image + Retake/Accept (parent owns navigation). |
| `camera_screen.dart` | **Modify** | Wire shutter → `capture()` → push review → Retake/Accept nav + failure SnackBar. |

Test/support:

| File | Change | Responsibility |
|---|---|---|
| `apps/mobile/test/support/fake_scan.dart` | **Modify** | Fake `capture()` writes a real 1×1 JPEG to temp; expose `kFakeJpegBytes`, `captureCalled`, `captureError`. |
| `apps/mobile/test/features/scan/captured_image_test.dart` | **Create** | Unit: fake capture produces a non-empty JPEG file. |
| `apps/mobile/test/features/scan/scan_controller_capture_test.dart` | **Create** | Unit: `capture()` success / double-tap guard / failure / dispose-safe. |
| `apps/mobile/test/features/scan/capture_review_screen_test.dart` | **Create** | Widget: review shows image + Retake/Accept; callbacks fire. |
| `apps/mobile/test/features/scan/camera_screen_capture_test.dart` | **Create** | Widget: shutter present in ready; shutter → review; Retake → preview; failure → SnackBar. |
| `apps/mobile/test/features/scan/scan_controller_test.dart` | **Modify** | Update the test-local `_GatedPreviewController` to implement `capture()` (interface grew). |
| `apps/mobile/test/features/scan/camera_screen_test.dart` | **Modify** | Existing granted test now needs the shutter present (no behavior change beyond that). |
| `apps/mobile/integration_test/a3_capture_review.feature` | **Create** | 3 BDD scenarios (shutter→review, Retake, Accept). |
| `apps/mobile/integration_test/a3_capture_review_test.dart` | **Create (generated, committed)** | Generated from the `.feature`. |
| `apps/mobile/test/step/i_tap_the_shutter.dart` | **Create** | Step: tap `Key('scan-shutter')`. |
| `apps/mobile/test/step/i_see_the_capture_review_screen.dart` | **Create** | Step: assert review keys. |
| `apps/mobile/test/step/i_tap_retake.dart` | **Create** | Step: tap `Key('review-retake')`. |
| `apps/mobile/test/step/i_tap_accept.dart` | **Create** | Step: tap `Key('review-accept')`. |
| `apps/mobile/test/step/i_see_the_documents_home.dart` | **Create** | Step: assert AppBar 'Documents' + Scan FAB. |
| `scripts/verify/a3.sh` | **Create** | The A3 gate (analyze + coverage floor + BDD on Android & iOS + opt-in real-device lane). |

**Interfaces produced by A3 (exact signatures later tasks/steps rely on):**
- `class CapturedImage { final String path; const CapturedImage(this.path); }`
- `CameraPreviewController.capture() → Future<CapturedImage>` (throws `CameraUnavailableException`)
- `ScanController.capture() → Future<CapturedImage?>` (null = not-ready / already-capturing / disposed / failed)
- `ScanController.capturing → bool`
- Widget keys: `scan-shutter`, `scan-shutter-busy`, `review-image`, `review-image-error`, `review-retake`, `review-accept`

---

### Task 1: `CapturedImage` + `capture()` on the preview seam

Adds the capture method to the interface, the plugin implementation, and the fake. Because the interface grows, **every** implementer must gain `capture()` in the same task or the suite won't compile — that includes `FakeCameraPreviewController` and the test-local `_GatedPreviewController` in `scan_controller_test.dart`.

**Files:**
- Create: `apps/mobile/lib/features/scan/captured_image.dart`
- Modify: `apps/mobile/lib/features/scan/camera_preview_controller.dart`
- Modify: `apps/mobile/lib/features/scan/camera_preview_controller_impl.dart`
- Modify: `apps/mobile/test/support/fake_scan.dart`
- Modify: `apps/mobile/test/features/scan/scan_controller_test.dart` (compile-fix only)
- Test: `apps/mobile/test/features/scan/captured_image_test.dart`

**Interfaces:**
- Consumes: A2's `CameraPreviewController`, `CameraUnavailableException`, `PluginCameraPreviewController`, `FakeCameraPreviewController`.
- Produces: `CapturedImage`, `CameraPreviewController.capture()`, `kFakeJpegBytes`, fake `captureCalled`/`captureError`.

- [ ] **Step 1: Create the value type**

`apps/mobile/lib/features/scan/captured_image.dart`:
```dart
/// One captured page: the path to its image file in temporary storage.
///
/// A3 produces this and hands it to the review screen. Persistence (B1) and
/// multi-page grouping (Feature 06) consume it later. Holds no bytes — the file
/// at [path] is the source of truth.
class CapturedImage {
  final String path;
  const CapturedImage(this.path);
}
```

- [ ] **Step 2: Add `capture()` to the interface**

In `apps/mobile/lib/features/scan/camera_preview_controller.dart`, add the import below the existing `package:flutter/widgets.dart` import:
```dart
import 'captured_image.dart';
```
Add this method to the `CameraPreviewController` interface (after `buildPreview()`):
```dart
  /// Captures a still image to a temporary file. Only valid after [initialize]
  /// succeeds. Throws [CameraUnavailableException] if capture fails.
  Future<CapturedImage> capture();
```

- [ ] **Step 3: Write the failing fake/unit test**

`apps/mobile/test/features/scan/captured_image_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_scan.dart';

void main() {
  test('fake capture() writes a non-empty JPEG file to a temp path', () async {
    final fake = FakeCameraPreviewController();
    final image = await fake.capture();

    final file = File(image.path);
    expect(file.existsSync(), isTrue, reason: 'capture must produce a real file');
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(2));
    // JPEG SOI marker 0xFFD8 … EOI marker 0xFFD9 (proves real JPEG bytes).
    expect([bytes[0], bytes[1]], [0xFF, 0xD8]);
    expect([bytes[bytes.length - 2], bytes[bytes.length - 1]], [0xFF, 0xD9]);
    expect(fake.captureCalled, isTrue);
  });

  test('fake capture() throws when captureError is set', () async {
    final fake = FakeCameraPreviewController()
      ..captureError = const CameraUnavailableException('fake: capture failed');
    expect(fake.capture(), throwsA(isA<CameraUnavailableException>()));
  });
}
```
The `CameraUnavailableException` import is re-exported through `fake_scan.dart`'s imports; if the analyzer complains it's undefined, add `import 'package:mobile/features/scan/camera_preview_controller.dart';` to the test.

- [ ] **Step 4: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/captured_image_test.dart`
Expected: FAIL — `FakeCameraPreviewController` has no `capture()`/`captureCalled`/`captureError` yet (compile error).

- [ ] **Step 5: Implement the plugin `capture()`**

In `apps/mobile/lib/features/scan/camera_preview_controller_impl.dart`, add the import:
```dart
import 'captured_image.dart';
```
Add this method to `PluginCameraPreviewController` (after `buildPreview()`):
```dart
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
```

- [ ] **Step 6: Implement the fake `capture()` + the JPEG constant**

In `apps/mobile/test/support/fake_scan.dart`, add these imports at the top:
```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mobile/features/scan/captured_image.dart';
```
Add this top-level constant (above the classes):
```dart
/// A minimal valid 1×1 JPEG (SOI … EOI). The fake writes this so the review
/// screen renders a real, decodable image in tests without camera hardware.
final Uint8List kFakeJpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
  'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
  'AAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q==',
);
```
In `FakeCameraPreviewController`, add these fields and method (alongside `disposed`):
```dart
  bool captureCalled = false;
  CameraUnavailableException? captureError;

  @override
  Future<CapturedImage> capture() async {
    captureCalled = true;
    final err = captureError;
    if (err != null) throw err;
    final dir = await Directory.systemTemp.createTemp('fake_capture');
    final file = File('${dir.path}/page.jpg');
    await file.writeAsBytes(kFakeJpegBytes);
    return CapturedImage(file.path);
  }
```

- [ ] **Step 7: Compile-fix the gated controller in `scan_controller_test.dart`**

The interface grew, so the test-local `_GatedPreviewController` must implement `capture()`. Add this method to it (it is never called by the existing `start()` tests, but is required to satisfy the interface):
```dart
  @override
  Future<CapturedImage> capture() async =>
      throw const CameraUnavailableException('gated: capture not used');
```
Add the import at the top of `scan_controller_test.dart`:
```dart
import 'package:mobile/features/scan/captured_image.dart';
```

- [ ] **Step 8: Run the tests to verify green**

Run: `cd apps/mobile && flutter test test/features/scan/captured_image_test.dart test/features/scan/scan_controller_test.dart`
Expected: PASS (all tests).

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/scan/captured_image.dart \
        apps/mobile/lib/features/scan/camera_preview_controller.dart \
        apps/mobile/lib/features/scan/camera_preview_controller_impl.dart \
        apps/mobile/test/support/fake_scan.dart \
        apps/mobile/test/features/scan/captured_image_test.dart \
        apps/mobile/test/features/scan/scan_controller_test.dart
git commit -m "feat(a3): add CapturedImage + capture() to the camera preview seam"
```

---

### Task 2: `ScanController.capture()` + `capturing` flag

The capture orchestration: guarded against double-tap, dispose-safe, failure-tolerant. `capturing` is modelled as a **bool attribute of the ready state** (like `permanentlyDenied`), not a new `ScanStatus` — so the screen's exhaustive switch is unchanged.

**Files:**
- Modify: `apps/mobile/lib/features/scan/scan_controller.dart`
- Test: `apps/mobile/test/features/scan/scan_controller_capture_test.dart`

**Interfaces:**
- Consumes: `CameraPreviewController.capture()`, `CapturedImage` (Task 1); existing `ScanStatus`, `_disposed`, `_set`.
- Produces: `ScanController.capture() → Future<CapturedImage?>`, `ScanController.capturing → bool`.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/features/scan/scan_controller_capture_test.dart`:
```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_controller.dart';
import 'package:mobile/features/scan/scan_view_state.dart';

import '../../support/fake_scan.dart';

/// Preview controller whose [capture] blocks until [gate] resolves, for
/// deterministic double-tap and dispose-mid-capture tests.
class _GatedCapture implements CameraPreviewController {
  final Completer<void> gate = Completer<void>();
  int captureCount = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<CapturedImage> capture() async {
    captureCount++;
    await gate.future;
    return const CapturedImage('/tmp/gated.jpg');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Future<ScanController> _ready(CameraPreviewController preview) async {
  final c = ScanController(
    permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
    preview: preview,
  );
  await c.start();
  expect(c.status, ScanStatus.ready);
  return c;
}

void main() {
  test('capture() returns the image and toggles capturing on then off',
      () async {
    final fake = FakeCameraPreviewController();
    final c = await _ready(fake);

    final states = <bool>[];
    c.addListener(() => states.add(c.capturing));

    final image = await c.capture();

    expect(image, isNotNull);
    expect(fake.captureCalled, isTrue);
    expect(c.capturing, isFalse);
    expect(states, containsAllInOrder([true, false]));
  });

  test('capture() ignores a second tap while one is in flight', () async {
    final gated = _GatedCapture();
    final c = await _ready(gated);

    final first = c.capture();
    final second = await c.capture(); // in-flight → ignored immediately
    expect(second, isNull);
    expect(gated.captureCount, 1);

    gated.gate.complete();
    expect(await first, isNotNull);
    expect(c.capturing, isFalse);
  });

  test('capture() returns null and does not crash when capture fails', () async {
    final fake = FakeCameraPreviewController()
      ..captureError = const CameraUnavailableException('boom');
    final c = await _ready(fake);

    final image = await c.capture();
    expect(image, isNull);
    expect(c.capturing, isFalse);
  });

  test('capture() returns null when not in the ready state', () async {
    final c = ScanController(
      permission: FakeCameraPermissionService(CameraPermissionStatus.denied),
      preview: FakeCameraPreviewController(),
    );
    await c.start(); // → permissionDenied
    expect(await c.capture(), isNull);
  });

  test('disposing mid-capture does not notify after dispose', () async {
    final gated = _GatedCapture();
    final c = await _ready(gated);

    var notifyCount = 0;
    c.addListener(() => notifyCount++);

    // ignore: unawaited_futures
    c.capture();
    await Future<void>.value(); // progress into capture()'s await

    final countAtDispose = notifyCount;
    c.dispose();
    gated.gate.complete();
    await Future<void>.value();

    expect(notifyCount, equals(countAtDispose),
        reason: 'no notifyListeners() after dispose');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/scan_controller_capture_test.dart`
Expected: FAIL — `capture()` / `capturing` not defined on `ScanController`.

- [ ] **Step 3: Implement `capture()` + `capturing`**

In `apps/mobile/lib/features/scan/scan_controller.dart`, add the import:
```dart
import 'captured_image.dart';
```
Add the flag (next to `_permanentlyDenied`):
```dart
  bool _capturing = false;
  bool get capturing => _capturing;
```
Add the method (after `openSettings()`):
```dart
  /// Captures a still image in the ready state. Returns null if not ready,
  /// already capturing, disposed, or capture failed (the screen surfaces
  /// failure). Sets [capturing] true→false around the in-flight capture.
  Future<CapturedImage?> capture() async {
    if (_disposed || _status != ScanStatus.ready || _capturing) return null;
    _capturing = true;
    notifyListeners();
    try {
      final image = await _preview.capture();
      if (_disposed) return null;
      return image;
    } on CameraUnavailableException {
      return null;
    } finally {
      if (!_disposed) {
        _capturing = false;
        notifyListeners();
      }
    }
  }
```

- [ ] **Step 4: Run to verify green**

Run: `cd apps/mobile && flutter test test/features/scan/scan_controller_capture_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/scan_controller.dart \
        apps/mobile/test/features/scan/scan_controller_capture_test.dart
git commit -m "feat(a3): ScanController.capture() with double-tap guard + dispose-safety"
```

---

### Task 3: `CaptureReviewScreen` widget

A stateless screen that shows the captured file and two actions. It owns **no** navigation — the parent passes `onRetake`/`onAccept`. `Image.file` gets an `errorBuilder` so a missing/corrupt file degrades to an icon instead of crashing.

**Files:**
- Create: `apps/mobile/lib/features/scan/capture_review_screen.dart`
- Test: `apps/mobile/test/features/scan/capture_review_screen_test.dart`

**Interfaces:**
- Consumes: `CapturedImage` (Task 1), `kFakeJpegBytes` (Task 1).
- Produces: `CaptureReviewScreen({required CapturedImage image, required VoidCallback onRetake, required VoidCallback onAccept})`; keys `review-image`, `review-image-error`, `review-retake`, `review-accept`.

- [ ] **Step 1: Write the failing widget test**

`apps/mobile/test/features/scan/capture_review_screen_test.dart`:
```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_scan.dart';

void main() {
  testWidgets('shows the captured image and Retake/Accept; callbacks fire',
      (tester) async {
    final dir = await Directory.systemTemp.createTemp('review_test');
    final file = File('${dir.path}/page.jpg');
    await file.writeAsBytes(kFakeJpegBytes);

    var retook = false;
    var accepted = false;

    await tester.pumpWidget(MaterialApp(
      home: CaptureReviewScreen(
        image: CapturedImage(file.path),
        onRetake: () => retook = true,
        onAccept: () => accepted = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Review'), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retake'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-retake')));
    await tester.tap(find.byKey(const Key('review-accept')));
    expect(retook, isTrue);
    expect(accepted, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_test.dart`
Expected: FAIL — `capture_review_screen.dart` does not exist.

- [ ] **Step 3: Implement the screen**

`apps/mobile/lib/features/scan/capture_review_screen.dart`:
```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'captured_image.dart';

/// Shows a freshly captured [image] with Retake / Accept actions. Stateless —
/// the parent decides what Retake and Accept do (navigation). A3: Retake
/// returns to the live preview; Accept returns to the Documents home (no save
/// yet — persistence is B1).
class CaptureReviewScreen extends StatelessWidget {
  final CapturedImage image;
  final VoidCallback onRetake;
  final VoidCallback onAccept;

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.file(
            File(image.path),
            key: const Key('review-image'),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(
              Icons.broken_image_outlined,
              key: Key('review-image-error'),
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                key: const Key('review-retake'),
                onPressed: onRetake,
                icon: const Icon(Icons.replay),
                label: const Text('Retake'),
              ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: onAccept,
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify green**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/capture_review_screen.dart \
        apps/mobile/test/features/scan/capture_review_screen_test.dart
git commit -m "feat(a3): CaptureReviewScreen with Retake/Accept"
```

---

### Task 4: Shutter button + `CameraScreen` wiring

Add the shutter to the preview view and wire the capture→review→nav flow with graceful failure. The existing granted widget test must keep passing (it asserts the preview is shown — the shutter is additive).

**Files:**
- Modify: `apps/mobile/lib/features/scan/widgets/camera_preview_view.dart`
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Modify: `apps/mobile/test/features/scan/camera_screen_test.dart` (the granted test now provides a shutter; no assertion change required, but verify it still passes)
- Test: `apps/mobile/test/features/scan/camera_screen_capture_test.dart`

**Interfaces:**
- Consumes: `ScanController.capture()`/`capturing` (Task 2), `CaptureReviewScreen` (Task 3), existing `CameraPreviewView`.
- Produces: `CameraPreviewView({required controller, required VoidCallback onShutter, bool capturing})`; keys `scan-shutter`, `scan-shutter-busy`.

- [ ] **Step 1: Write the failing widget tests**

`apps/mobile/test/features/scan/camera_screen_capture_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';

import '../../support/fake_scan.dart';

ScanDependencies _grantedWithCaptureError() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController()
        ..captureError = const CameraUnavailableException('boom'),
    );

void main() {
  testWidgets('ready state shows the shutter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: grantedScanDependencies())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });

  testWidgets('tapping the shutter opens the review screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: grantedScanDependencies())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-image')), findsOneWidget);
    expect(find.byKey(const Key('review-retake')), findsOneWidget);
    expect(find.byKey(const Key('review-accept')), findsOneWidget);
  });

  testWidgets('Retake returns to the live preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: grantedScanDependencies())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-retake')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsNothing);
  });

  testWidgets('capture failure shows a SnackBar and stays on preview',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: _grantedWithCaptureError())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump(); // let the SnackBar appear
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not capture photo. Try again.'), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsNothing);
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/camera_screen_capture_test.dart`
Expected: FAIL — `CameraPreviewView` has no `onShutter`/`capturing`; no `scan-shutter` key.

- [ ] **Step 3: Add the shutter to `CameraPreviewView`**

Replace the contents of `apps/mobile/lib/features/scan/widgets/camera_preview_view.dart`:
```dart
import 'package:flutter/material.dart';

import '../camera_preview_controller.dart';

/// Frames the live preview with a shutter button. [onShutter] fires on tap;
/// while [capturing] is true the button shows progress and is disabled.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;
  final VoidCallback onShutter;
  final bool capturing;

  const CameraPreviewView({
    super.key,
    required this.controller,
    required this.onShutter,
    this.capturing = false,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: controller.buildPreview()),
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
**Do not remove the `heroTag: 'scan-shutter'`.** The Documents-home Scan button is also a `FloatingActionButton` (default hero tag); during the Home→Camera route transition both FABs are mounted at once, and two FABs sharing the default tag throw "multiple heroes share the same tag". The explicit tag keeps them distinct.

- [ ] **Step 4: Wire capture→review→nav in `CameraScreen`**

In `apps/mobile/lib/features/scan/camera_screen.dart`, add the import:
```dart
import 'capture_review_screen.dart';
```
Replace the `ScanStatus.ready` case body with:
```dart
            case ScanStatus.ready:
              return CameraPreviewView(
                key: const Key('scan-preview'),
                controller: _controller.preview,
                capturing: _controller.capturing,
                onShutter: _onShutter,
              );
```
Add this method to `_CameraScreenState` (after `dispose()`). **Capture `navigator`/`messenger` BEFORE the `await`** — using `context` after an await trips the `use_build_context_synchronously` lint (active via `flutter_lints`), which would fail the `analyze` gate:
```dart
  Future<void> _onShutter() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final image = await _controller.capture();
    if (!mounted) return;
    if (image == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Try again.')),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureReviewScreen(
          image: image,
          onRetake: navigator.pop,
          onAccept: () => navigator.popUntil((route) => route.isFirst),
        ),
      ),
    );
  }
```
Update the class doc comment line 10–11 ("Capture (shutter) arrives in A3.") to: `/// Capture (shutter) → review screen lives here (A3).`

- [ ] **Step 5: Run the capture tests + the existing scan widget tests**

Run: `cd apps/mobile && flutter test test/features/scan/camera_screen_capture_test.dart test/features/scan/camera_screen_test.dart`
Expected: PASS (both files). If the existing `camera_screen_test.dart` granted test fails to compile because `CameraPreviewView` now requires `onShutter`, that view is only constructed inside `CameraScreen` (not directly by that test), so no change is needed — confirm it passes.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/widgets/camera_preview_view.dart \
        apps/mobile/lib/features/scan/camera_screen.dart \
        apps/mobile/test/features/scan/camera_screen_capture_test.dart
git commit -m "feat(a3): shutter button + capture→review navigation with failure SnackBar"
```

---

### Task 5: BDD scenarios + A3 verify gate + real-device lane

Author the `.feature`, generate and commit the on-device test, add the step defs, write `scripts/verify/a3.sh`, mutation-check the new device test, and update the ledger/index. This is the gate task.

**Files:**
- Create: `apps/mobile/integration_test/a3_capture_review.feature`
- Create (generated, committed): `apps/mobile/integration_test/a3_capture_review_test.dart`
- Create: `apps/mobile/test/step/i_tap_the_shutter.dart`, `i_see_the_capture_review_screen.dart`, `i_tap_retake.dart`, `i_tap_accept.dart`, `i_see_the_documents_home.dart`
- Create: `scripts/verify/a3.sh`
- Modify: `.superpowers/sdd/progress.md`, `docs/superpowers/plans/00-plans-index.md`

**Interfaces:**
- Consumes: the shutter + review keys (Tasks 3–4); existing steps `the app is launched with camera permission granted`, `I tap the Scan button`, `I see the camera preview`; `verify_integration_{android,ios}`, `assert_cmd`, `assert_coverage_floor`, `require_tool` from `lib.sh`.
- Produces: the A3 gate `scripts/verify/a3.sh`.

- [ ] **Step 1: Author the `.feature`**

`apps/mobile/integration_test/a3_capture_review.feature`:
```gherkin
Feature: Capture a photo and review it

  Scenario: Tapping the shutter shows the review screen
    Given the app is launched with camera permission granted
    When I tap the Scan button
    And I tap the shutter
    Then I see the capture review screen

  Scenario: Retake returns to the live preview
    Given the app is launched with camera permission granted
    When I tap the Scan button
    And I tap the shutter
    And I tap Retake
    Then I see the camera preview

  Scenario: Accept returns to the Documents home
    Given the app is launched with camera permission granted
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    Then I see the Documents home
```
The `Given …granted`, `I tap the Scan button`, and `I see the camera preview` steps already exist in `test/step/` — reused (DRY).

- [ ] **Step 2: Write the new step definitions**

`apps/mobile/test/step/i_tap_the_shutter.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the shutter
Future<void> iTapTheShutter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scan-shutter')));
  await tester.pumpAndSettle();
}
```
`apps/mobile/test/step/i_see_the_capture_review_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the capture review screen
Future<void> iSeeTheCaptureReviewScreen(WidgetTester tester) async {
  expect(find.byKey(const Key('review-image')), findsOneWidget);
  expect(find.byKey(const Key('review-retake')), findsOneWidget);
  expect(find.byKey(const Key('review-accept')), findsOneWidget);
}
```
`apps/mobile/test/step/i_tap_retake.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap Retake
Future<void> iTapRetake(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-retake')));
  await tester.pumpAndSettle();
}
```
`apps/mobile/test/step/i_tap_accept.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap Accept
Future<void> iTapAccept(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}
```
`apps/mobile/test/step/i_see_the_documents_home.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the Documents home
Future<void> iSeeTheDocumentsHome(WidgetTester tester) async {
  expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
}
```

- [ ] **Step 3: Generate the on-device test and commit it**

First record the current step files so you can detect unexpected new stubs:
`ls apps/mobile/test/step/ > /tmp/step_before.txt`

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: writes `integration_test/a3_capture_review_test.dart` importing the five step files above plus the three reused ones. Open it and confirm it contains `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` and one `testWidgets` per scenario.

**Then verify NO new step stub files appeared:** `ls apps/mobile/test/step/ | diff /tmp/step_before.txt -` (run from repo root, adjusting the path). `bdd_widget_test` auto-generates a **stub** step file (with an `UnimplementedError` body) for any step whose function name it can't match to an existing file — so a brand-new file here means one of your step **names did not match** what the generator derived from the Gherkin text. If a stub appears, rename your hand-written step file/function to match the generator's name (do not keep both), then re-run build_runner. A silent name mismatch would otherwise make the device test throw at that step.

- [ ] **Step 4: Verify the generated test runs on a device (and mutation-check it)**

Run (Android emulator must be booted): `cd apps/mobile && flutter test integration_test/a3_capture_review_test.dart -d emulator-5554`
Expected: `All tests passed!`

Mutation check (rule: non-vacuous) — temporarily change `i_see_the_capture_review_screen.dart` to assert `find.byKey(const Key('review-image-DOES-NOT-EXIST'))`, rerun the above, confirm it **FAILS**, then revert and confirm it passes again. Note the result in the task report.

- [ ] **Step 5: Write the A3 gate**

`scripts/verify/a3.sh`:
```bash
#!/usr/bin/env bash
# Verify A3 (capture photo → review screen) acceptance criteria.
# Run from anywhere: bash scripts/verify/a3.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip device launches — skipping is reported as
# a FAIL, never silent. Opt-in REAL_DEVICE=1 adds a real-camera smoke lane.
# Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== A3 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "CapturedImage value type exists" \
  "apps/mobile/lib/features/scan/captured_image.dart" "class CapturedImage"
assert_file_has "preview seam exposes capture()" \
  "apps/mobile/lib/features/scan/camera_preview_controller.dart" "Future<CapturedImage> capture()"
assert_file_has "ScanController exposes capture()" \
  "apps/mobile/lib/features/scan/scan_controller.dart" "Future<CapturedImage?> capture()"
assert_file_has "review screen exists" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" "class CaptureReviewScreen"
assert_file_has "shutter button key present" \
  "apps/mobile/lib/features/scan/widgets/camera_preview_view.dart" "scan-shutter"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "a3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration tests) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

# BDD-generated integration test (from integration_test/a3_capture_review.feature
# via bdd_widget_test + build_runner; the generated *_test.dart is committed).
# Injects fakes → deterministic; the real camera native code is compiled+linked
# into the device build. Real *runtime* capture is the opt-in REAL_DEVICE lane
# below + manual on iOS (see VERIFICATION.md #5).
verify_integration_android a3_capture_review_test.dart
verify_integration_ios a3_capture_review_test.dart

# ---- Opt-in real-device smoke lane (REAL_DEVICE=1) ----
# Proves the REAL camera plugin produces a REAL non-empty JPEG on hardware.
# Android: install debuggable + pre-grant CAMERA (bypasses the dialog), tap the
# shutter, then read the app's private storage via run-as and assert a non-empty
# JPEG was written. iOS real camera = MANUAL "Allow once" (no simulator camera).
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device/emulator connected"
  else
    apk="apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    ( cd apps/mobile && flutter build apk --debug ) >/dev/null 2>&1 \
      || fail "REAL_DEVICE: debug APK build failed"
    "$ADB" -s "$rdev" install -r -g "$apk" >/dev/null 2>&1 \
      && pass "REAL_DEVICE: installed with CAMERA pre-granted" \
      || fail "REAL_DEVICE: adb install -g failed"
    "$ADB" -s "$rdev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null
    # Clear any stale captures so the assertion proves THIS run (negative control).
    "$ADB" -s "$rdev" shell "run-as $APP_ID find . -iname '*.jpg' -delete" 2>/dev/null
    "$ADB" -s "$rdev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 6
    size="$("$ADB" -s "$rdev" shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
    w="${size%x*}"; h="${size#*x}"
    # Open Scan (extended FAB ~84% width, ~93.5% height), then the shutter
    # (bottom-center ~50% width, ~88% height — see CameraPreviewView).
    "$ADB" -s "$rdev" shell input tap "$(( w * 84 / 100 ))" "$(( h * 935 / 1000 ))" >/dev/null 2>&1
    sleep 5
    "$ADB" -s "$rdev" shell input tap "$(( w * 50 / 100 ))" "$(( h * 88 / 100 ))" >/dev/null 2>&1
    sleep 4
    found="$("$ADB" -s "$rdev" shell "run-as $APP_ID find . -iname '*.jpg' -size +0c" 2>/dev/null | tr -d '\r')"
    if [ -n "$found" ]; then
      pass "REAL_DEVICE: real camera produced a non-empty JPEG ($found)"
    else
      fail "REAL_DEVICE: no non-empty JPEG produced by the real camera [silence=fail]"
    fi
    shot="$EVIDENCE_DIR/real-device-review.png"
    "$ADB" -s "$rdev" exec-out screencap -p > "$shot" 2>/dev/null
    echo "REAL_DEVICE: screenshot → $shot"
  fi
  echo "REAL_DEVICE (iOS): MANUAL — run the app on a physical iPhone, tap Scan →"
  echo "  Allow → shutter, and confirm the review screen shows the captured photo."
fi

verify_summary
```
Make it executable: `chmod +x scripts/verify/a3.sh`.

- [ ] **Step 6: Run the full gate and observe it green**

Run (Android emulator + iOS simulator booted): `bash scripts/verify/a3.sh`
Expected: ends with `GATE: PASS` and exit 0. Confirm the on-device lines read `android: on-device integration test asserts UI (a3_capture_review_test.dart)` and the iOS equivalent.

Negative control (rule 5): `VERIFY_SKIP_DEVICE=1 bash scripts/verify/a3.sh` → must end `GATE: FAIL`, exit 1.

- [ ] **Step 7: Update the ledger and the plans index**

In `.superpowers/sdd/progress.md`, change the final line to mark A3 complete (commit range filled at execution time) and set Next to B1. Add an A3 entry mirroring the A2 format, including the line: `Known deferred gap: EXIF/metadata scrubbing applies when files are persisted/exported — designed in Feature 07, tracked for B1 (capture is temp-only in A3).`

In `docs/superpowers/plans/00-plans-index.md`, set the A3 row Status to `✅ built & gated` and fill the plan filename `2026-06-27-a3-capture-review.md`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/a3_capture_review.feature \
        apps/mobile/integration_test/a3_capture_review_test.dart \
        apps/mobile/test/step/i_tap_the_shutter.dart \
        apps/mobile/test/step/i_see_the_capture_review_screen.dart \
        apps/mobile/test/step/i_tap_retake.dart \
        apps/mobile/test/step/i_tap_accept.dart \
        apps/mobile/test/step/i_see_the_documents_home.dart \
        scripts/verify/a3.sh \
        .superpowers/sdd/progress.md \
        docs/superpowers/plans/00-plans-index.md
git commit -m "test(a3): BDD capture→review scenarios + a3 verify gate + real-device lane"
```

---

## Acceptance criteria (Feature 01 subset realized by A3)

Each is closed only by a passing test named beside it; the gate (`scripts/verify/a3.sh` → `GATE: PASS`, exit 0) is the binding check, reproduced by an independent verifier.

- [ ] Tapping the shutter in the ready state captures one JPEG to a temp file — *unit: `scan_controller_capture_test`, `captured_image_test`*
- [ ] The captured image is shown on a review screen with Retake and Accept — *widget: `capture_review_screen_test`, `camera_screen_capture_test`; BDD: shutter→review*
- [ ] Retake returns to the live preview — *widget + BDD: Retake*
- [ ] Accept returns to the Documents home (no save in A3) — *BDD: Accept*
- [ ] A second shutter tap during capture is ignored (no double capture) — *unit: double-tap guard*
- [ ] Capture failure is graceful (SnackBar, no crash, stays on preview) — *widget: failure SnackBar*
- [ ] Disposing mid-capture never notifies after dispose — *unit: dispose-safe*
- [ ] On-device widget tree asserted on Android + iOS — *BDD integration on both, mutation-checked*
- [ ] (Opt-in) Real camera produces a real non-empty JPEG on Android hardware — *`REAL_DEVICE=1` lane*

## Known deferred gaps (surfaced, not hidden — per the "no done with open gaps" rule)

1. **EXIF / metadata scrubbing is NOT applied in A3.** The always-on scrubber is *designed in Feature 07* and applies when files are **persisted or exported**. A3 writes only to the temporary directory and persists nothing, so scrubbing is correctly out of A3's scope — but it is a real requirement for the captured bytes once they are saved. **Tracked: close at B1 (first persistence) / Feature 07.** Do not mark the capture pipeline "done" end-to-end until scrubbing covers persisted captures.
2. **Real iOS camera capture is verified MANUALLY only** (no simulator camera; the `REAL_DEVICE` lane automates Android only). The iOS simulator path is exercised by the BDD test with fakes (compile+link of the real plugin), per VERIFICATION.md #5.
3. **Single capture only.** Multi-page batch (capture several pages into one document) is Feature 06 / H1–H5, intentionally later; the `CapturedImage` shape is additive toward it.
4. **Permission re-check on resume / camera lifecycle on pause-resume is NOT added** (carried-over A2 Minors; the A2 ledger flagged "address opportunistically as capture lengthens the lifecycle window"). A3's review route does not background the app, so the lifecycle window is not materially lengthened here — **explicitly deferred, not silently dropped.** Revisit when a flow can background the app between grant and use (e.g. settings round-trip, or B-step persistence that survives backgrounding).
5. **`dart:io` (`Image.file`, temp-file write) makes the capture/review path mobile-only.** The roadmap is mobile-first ("Web later"); the gate builds Android + iOS only, so this is in-scope-correct, but a future Web target will need a conditional-import abstraction for image bytes. Tracked, not blocking.
6. **Temp captures are not cleaned up in A3.** Each shutter tap (incl. Retake re-captures) writes a new JPEG to the temp/cache dir; A3 neither deletes a discarded capture nor moves an accepted one. This is acceptable because the OS reclaims the cache dir and **B1 takes ownership of the file lifecycle** (move accepted captures to app-private storage, drop discarded ones). **Tracked: file lifecycle is owned by B1** — do not add ad-hoc deletion here (it would race B1's design).
7. **No new OS permission is introduced (intentional).** A3 captures with the camera grant already obtained in A2 and writes only to internal temp — it does **not** save to the system photo gallery, so no `NSPhotoLibraryAddUsageDescription` / `WRITE_EXTERNAL_STORAGE` is needed. This is consistent with the privacy spine (nothing leaves the app sandbox). If a future step offers "save to Photos", that permission lands there, not here.

**Watch-items for the implementer (not gaps — flag in the task report if they trip):**
- **Coverage floor (70%).** A3 adds untested plugin lines (`PluginCameraPreviewController.capture()` — real-hardware-only, like `initialize`/`buildPreview`) and the review screen's `errorBuilder` branch (not hit by the happy-path widget test). A2 measured 77% with the same impl-uncovered pattern, so 70% should hold — but if `assert_coverage_floor 70` fails, add a widget test that pumps `CaptureReviewScreen` with a non-existent path to cover `review-image-error`, rather than lowering the floor.
- **Real-device lane `run-as` path.** The lane asserts the JPEG via `run-as $APP_ID find .` over the app's **internal** data dir; the `camera` plugin's `takePicture()` writes to the internal cache dir, so it is reachable. If a plugin version writes to app-specific **external** storage instead, switch the find to `adb shell find /sdcard/Android/data/$APP_ID -iname '*.jpg'`. This lane is opt-in and separate from the always-on gate.

## Self-Review

- **Spec coverage (Feature 01):** A3 realizes the *Single, manual-shutter* slice — capture → review with graceful permission/error handling — and explicitly defers modes/torch/grid/focus/auto-capture/batch/ID-card (out of A3 scope per the roadmap atomization, recorded in Global Constraints). The "OCR-quality JPEG to next step" criterion is met via the plugin's `ResolutionPreset.high` (from A2) + default JPEG, output as a temp path.
- **Placeholder scan:** none — every code/command step carries concrete content; the only TODO-like items (commit ranges in the ledger, generated test filename) are produced at execution time by the named commands.
- **Type consistency:** `CapturedImage(this.path)` / `.path`, `capture()` return types (`Future<CapturedImage>` on the seam, `Future<CapturedImage?>` on the controller), and the widget keys (`scan-shutter`, `review-image`, `review-retake`, `review-accept`) are used identically across Tasks 1–5 and the gate's `assert_file_has` markers.
