# A2 — Camera Preview + Permission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping **Scan** opens a camera screen that requests camera permission, shows a **live preview** when granted, and degrades gracefully (rationale + Open Settings, or "camera unavailable") otherwise.

**Architecture:** A `ScanController` (`ChangeNotifier`) orchestrates a small state machine (`checking → ready | permissionDenied | unavailable`) over two **interfaces** — `CameraPermissionService` (wraps `permission_handler`) and `CameraPreviewController` (wraps `camera`). The `CameraScreen` widget renders one view per state. Concrete plugin-backed implementations live in their own files; a `ScanDependencies` holder (the composition root) wires production defaults and lets tests inject fakes. This keeps all branch logic unit/widget-testable and makes the on-device integration tests deterministic (no real hardware/permission-dialog dependency), while still compiling and linking the real native plugins on each device.

**Tech Stack:** Flutter (Dart 3, Material 3), `camera`, `permission_handler`, `flutter_test`, `integration_test`. Nx target wrappers (`pnpm nx run mobile:test|analyze|run`).

## Global Constraints

Copied verbatim from `../specs/00-overview-roadmap.md` and `../specs/features/01-document-scanning.md` — every task's requirements implicitly include these:

- **TDD/BDD first, always.** Write the failing test before the implementation. Every feature, class, component, and function must be **SOLID, KISS, DRY**.
- **Privacy spine:** documents never leave the device. No cloud, no network calls. (A2 adds no networking.)
- **Definition of Done (binding):** a step is done only when every acceptance criterion maps to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and **observed green**, quality gates pass, and the work is reviewed and double-checked. "Looks right"/"should pass" is **not** done.
- **Verification harness (binding):** the step ships `scripts/verify/a2.sh` (built on `scripts/verify/lib.sh`) encoding each acceptance criterion as an assert — exact command + success marker, exit-code check, caches disabled (`--skip-nx-cache`), negative controls, **silence = FAIL**. The gate is that script exiting 0, observed by an **independent adversarial verifier** from a clean state.
- **On-device UI is authoritative via `integration_test`, not screenshots.** Any UI step ships `apps/mobile/integration_test/<step>_*.dart` that pumps the real app on each device and asserts the rendered widget tree (run via `verify_integration_{android,ios}`), **mutation-checked once**.
- **Resolution/format** (camera): highest available still capped ~12 MP, JPEG q≈90 — these belong to **capture (A3)**, not A2. A2 only shows the preview; do not implement capture here (YAGNI).
- **Capture modes, torch, grid, auto-capture, tap-to-focus** are later steps — **out of scope for A2** (YAGNI).

**App identifiers (already configured — do not change):** Android `applicationId`/`namespace` = `com.camscannerlight.mobile`; package name `mobile`.

---

## Scope (A2 only)

**In scope:** navigation Scan→camera screen; camera-permission request with rationale; live preview when granted; graceful permission-denied (with Open Settings) and no-camera/error states; the plugin + native config to make the above build and run on device.

**Explicitly out of scope (later steps, do NOT build):** the shutter / capturing an image (A3), capture modes, torch/grid/focus controls, auto-capture, settings toggles, persistence.

## File Structure

New feature folder `apps/mobile/lib/features/scan/`:

| File | Responsibility |
|---|---|
| `scan_view_state.dart` | `ScanStatus` enum (the state machine's states). |
| `camera_permission_service.dart` | `CameraPermissionService` **interface** + `CameraPermissionStatus` enum. No plugin import. |
| `camera_preview_controller.dart` | `CameraPreviewController` **interface** + `CameraUnavailableException`. No plugin import. |
| `camera_permission_service_impl.dart` | `PermissionHandlerCameraPermissionService` — concrete, wraps `permission_handler`. |
| `camera_preview_controller_impl.dart` | `PluginCameraPreviewController` — concrete, wraps `camera`. |
| `scan_dependencies.dart` | `ScanDependencies` composition root: factories with production defaults; const-constructible. |
| `scan_controller.dart` | `ScanController extends ChangeNotifier` — orchestration state machine. |
| `camera_screen.dart` | `CameraScreen` widget: builds `ScanController`, renders a view per `ScanStatus`. |
| `widgets/camera_preview_view.dart` | Frames `controller.buildPreview()`. |
| `widgets/permission_denied_view.dart` | Rationale + Open Settings button. |
| `widgets/camera_unavailable_view.dart` | Graceful "camera unavailable" message. |

Modified: `apps/mobile/lib/main.dart` (entrypoint accepts deps), `apps/mobile/lib/features/library/home_screen.dart` (FAB navigates), `apps/mobile/pubspec.yaml` (plugins), `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/ios/Runner/Info.plist`.

Tests: `apps/mobile/test/support/fake_scan.dart` (shared fakes), `apps/mobile/test/features/scan/scan_controller_test.dart`, `.../camera_screen_test.dart`, `.../scan_dependencies_test.dart`, updated `apps/mobile/test/features/library/home_screen_test.dart`, `apps/mobile/integration_test/a2_camera_denied_test.dart`, `apps/mobile/integration_test/a2_camera_ready_test.dart`, `scripts/verify/a2.sh`.

---

## Task 1: Add camera + permission plugins and native permission config

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (via `flutter pub add`)
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `apps/mobile/ios/Runner/Info.plist`

**Interfaces:**
- Consumes: nothing.
- Produces: the `camera` and `permission_handler` packages on the dependency path; Android `CAMERA` permission; iOS `NSCameraUsageDescription`.

This is a dependency/config task (no Dart logic), so its "tests" are: the resolver succeeds, `analyze` stays clean, and the native markers are present. Those are gated in `scripts/verify/a2.sh` (Task 6) and re-checked here.

- [ ] **Step 1: Add the plugins (let the resolver pick compatible versions)**

Run:
```bash
cd apps/mobile && flutter pub add camera permission_handler
```
Expected: command exits 0 and `pubspec.yaml` now lists `camera:` and `permission_handler:` under `dependencies:`. Do **not** hand-pin versions — use whatever the resolver selects against SDK `^3.12.2`.

- [ ] **Step 2: Verify resolution and analyzer are clean**

Run:
```bash
cd apps/mobile && flutter pub get && flutter analyze
```
Expected: `Got dependencies` and `No issues found!`.

- [ ] **Step 3: Add the Android camera permission**

In `apps/mobile/android/app/src/main/AndroidManifest.xml`, add these two lines as direct children of `<manifest>`, immediately **before** the `<application>` tag:

```xml
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
```

(`required="false"` so the app still installs on camera-less devices; A2 handles "no camera" gracefully.)

- [ ] **Step 4: Add the iOS camera usage description**

In `apps/mobile/ios/Runner/Info.plist`, add this key/value pair inside the top-level `<dict>` (e.g. immediately after the `CADisableMinimumFrameDurationOnPhone` `<true/>`):

```xml
	<key>NSCameraUsageDescription</key>
	<string>CamScanner-light uses the camera to scan documents. Images stay on your device.</string>
```

(Required — iOS crashes at runtime on a camera-permission request without it.)

- [ ] **Step 5: Confirm native markers present**

Run:
```bash
grep -q 'android.permission.CAMERA' apps/mobile/android/app/src/main/AndroidManifest.xml && echo ANDROID_OK
grep -q 'NSCameraUsageDescription' apps/mobile/ios/Runner/Info.plist && echo IOS_OK
grep -Eq '^\s*camera:' apps/mobile/pubspec.yaml && grep -Eq '^\s*permission_handler:' apps/mobile/pubspec.yaml && echo DEPS_OK
```
Expected: `ANDROID_OK`, `IOS_OK`, `DEPS_OK`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/android/app/src/main/AndroidManifest.xml apps/mobile/ios/Runner/Info.plist
git commit -m "feat(a2): add camera + permission_handler plugins and native permission config"
```

---

## Task 2: State machine — interfaces, `ScanController`, and unit tests

**Files:**
- Create: `apps/mobile/lib/features/scan/scan_view_state.dart`
- Create: `apps/mobile/lib/features/scan/camera_permission_service.dart`
- Create: `apps/mobile/lib/features/scan/camera_preview_controller.dart`
- Create: `apps/mobile/lib/features/scan/scan_controller.dart`
- Create: `apps/mobile/test/support/fake_scan.dart`
- Test: `apps/mobile/test/features/scan/scan_controller_test.dart`

**Interfaces:**
- Consumes: nothing (defines the abstractions).
- Produces:
  - `enum ScanStatus { checking, ready, permissionDenied, unavailable }`
  - `enum CameraPermissionStatus { granted, denied, permanentlyDenied }`
  - `abstract interface class CameraPermissionService { Future<CameraPermissionStatus> request(); Future<bool> openSettings(); }`
  - `abstract interface class CameraPreviewController { Future<void> initialize(); Widget buildPreview(); Future<void> dispose(); }` + `class CameraUnavailableException implements Exception { const CameraUnavailableException(String message); }`
  - `class ScanController extends ChangeNotifier` with `ScanController({required CameraPermissionService permission, required CameraPreviewController preview})`, getters `ScanStatus get status`, `bool get permanentlyDenied`, `CameraPreviewController get preview`, methods `Future<void> start()`, `Future<void> openSettings()`.
  - Test fakes in `test/support/fake_scan.dart`: `FakeCameraPermissionService`, `FakeCameraPreviewController`, and helpers `grantedScanDependencies()`, `deniedScanDependencies({bool permanently})`, `unavailableScanDependencies()` (the helpers are used in Tasks 4–6; the fakes are used here).

- [ ] **Step 1: Write the interface + state files**

`apps/mobile/lib/features/scan/scan_view_state.dart`:
```dart
/// The states of the camera (Scan) screen. The screen renders exactly one
/// view per status; [ScanController] drives the transitions.
enum ScanStatus {
  /// Permission/camera are being resolved (transient, on entry).
  checking,

  /// Permission granted and the camera initialized — show the live preview.
  ready,

  /// Permission was denied — show the rationale and an Open Settings action.
  permissionDenied,

  /// No camera, or the camera failed to initialize — show a graceful message.
  unavailable,
}
```

`apps/mobile/lib/features/scan/camera_permission_service.dart`:
```dart
/// Result of asking for camera permission. [permanentlyDenied] means the OS
/// will not show a dialog again, so the only path forward is system Settings.
enum CameraPermissionStatus { granted, denied, permanentlyDenied }

/// Abstraction over the OS camera-permission flow (DIP). Production wires
/// `permission_handler`; tests inject a fake. The interface has no plugin
/// import, so widget/unit tests need no native bindings.
abstract interface class CameraPermissionService {
  /// Requests camera permission, returning the resolved status.
  Future<CameraPermissionStatus> request();

  /// Opens the OS app-settings page. Returns true if it was opened.
  Future<bool> openSettings();
}
```

`apps/mobile/lib/features/scan/camera_preview_controller.dart`:
```dart
import 'package:flutter/widgets.dart';

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

  /// Releases the camera.
  Future<void> dispose();
}
```

- [ ] **Step 2: Write the failing unit test**

`apps/mobile/test/features/scan/scan_controller_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/scan_controller.dart';
import 'package:mobile/features/scan/scan_view_state.dart';

import '../../support/fake_scan.dart';

void main() {
  group('ScanController.start()', () {
    test('granted + camera available → ready', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: FakeCameraPreviewController(),
      );
      await c.start();
      expect(c.status, ScanStatus.ready);
      expect(c.permanentlyDenied, isFalse);
    });

    test('granted but no camera → unavailable', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: FakeCameraPreviewController(unavailable: true),
      );
      await c.start();
      expect(c.status, ScanStatus.unavailable);
    });

    test('denied → permissionDenied, not permanent', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.denied),
        preview: FakeCameraPreviewController(),
      );
      await c.start();
      expect(c.status, ScanStatus.permissionDenied);
      expect(c.permanentlyDenied, isFalse);
    });

    test('permanentlyDenied → permissionDenied, permanent flag set', () async {
      final c = ScanController(
        permission:
            FakeCameraPermissionService(CameraPermissionStatus.permanentlyDenied),
        preview: FakeCameraPreviewController(),
      );
      await c.start();
      expect(c.status, ScanStatus.permissionDenied);
      expect(c.permanentlyDenied, isTrue);
    });

    test('notifies listeners on transition', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: FakeCameraPreviewController(),
      );
      var notifications = 0;
      c.addListener(() => notifications++);
      await c.start();
      expect(notifications, greaterThan(0));
    });

    test('openSettings() delegates to the permission service', () async {
      final perm = FakeCameraPermissionService(CameraPermissionStatus.denied);
      final c = ScanController(permission: perm, preview: FakeCameraPreviewController());
      final opened = await c.openSettings();
      expect(opened, isTrue);
      expect(perm.openSettingsCalled, isTrue);
    });
  });
}
```

Also create the fakes the test imports — `apps/mobile/test/support/fake_scan.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

/// In-memory fake of [CameraPermissionService] — returns a fixed status.
class FakeCameraPermissionService implements CameraPermissionService {
  final CameraPermissionStatus status;
  bool openSettingsCalled = false;

  FakeCameraPermissionService(this.status);

  @override
  Future<CameraPermissionStatus> request() async => status;

  @override
  Future<bool> openSettings() async {
    openSettingsCalled = true;
    return true;
  }
}

/// Fake [CameraPreviewController] that paints a deterministic placeholder
/// instead of real camera frames, so on-device tests need no hardware.
class FakeCameraPreviewController implements CameraPreviewController {
  final bool unavailable;
  bool disposed = false;

  FakeCameraPreviewController({this.unavailable = false});

  @override
  Future<void> initialize() async {
    if (unavailable) {
      throw const CameraUnavailableException('fake: no camera');
    }
  }

  @override
  Widget buildPreview() => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('FAKE PREVIEW', key: Key('fake-preview')),
        ),
      );

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Dependency presets used by widget + integration tests to drive each state.
ScanDependencies grantedScanDependencies() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController(),
    );

ScanDependencies deniedScanDependencies({bool permanently = false}) =>
    ScanDependencies(
      createPermissionService: () => FakeCameraPermissionService(permanently
          ? CameraPermissionStatus.permanentlyDenied
          : CameraPermissionStatus.denied),
      createPreviewController: () => FakeCameraPreviewController(),
    );

ScanDependencies unavailableScanDependencies() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () =>
          FakeCameraPreviewController(unavailable: true),
    );
```

> Note: `fake_scan.dart` imports `scan_dependencies.dart`, which is created in **Task 3**. The `ScanController` unit test in this task only uses the two fake **classes** (not the preset helpers), so it compiles once Task 3 exists. To keep this task self-contained and green on its own, implement Task 3's `scan_dependencies.dart` **before** running this task's suite — or run only `scan_controller_test.dart` here and the full suite after Task 3. The implementer should create `scan_dependencies.dart` (Task 3 Step 1's content) if it is not yet present, so the import resolves.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/scan_controller_test.dart`
Expected: FAIL — `ScanController` is not defined.

- [ ] **Step 4: Implement `ScanController`**

`apps/mobile/lib/features/scan/scan_controller.dart`:
```dart
import 'package:flutter/foundation.dart';

import 'camera_permission_service.dart';
import 'camera_preview_controller.dart';
import 'scan_view_state.dart';

/// Orchestrates the Scan screen's state machine:
/// `checking → ready | permissionDenied | unavailable`.
///
/// Holds no widgets — it is unit-testable with fakes. The screen listens to it
/// and renders one view per [status].
class ScanController extends ChangeNotifier {
  final CameraPermissionService _permission;
  final CameraPreviewController _preview;

  ScanController({
    required CameraPermissionService permission,
    required CameraPreviewController preview,
  })  : _permission = permission,
        _preview = preview;

  ScanStatus _status = ScanStatus.checking;
  ScanStatus get status => _status;

  bool _permanentlyDenied = false;
  bool get permanentlyDenied => _permanentlyDenied;

  /// The preview controller, valid for [ScanStatus.ready].
  CameraPreviewController get preview => _preview;

  /// Requests permission and initializes the camera, resolving [status].
  Future<void> start() async {
    _set(ScanStatus.checking);
    final permission = await _permission.request();
    if (permission == CameraPermissionStatus.granted) {
      try {
        await _preview.initialize();
        _set(ScanStatus.ready);
      } on CameraUnavailableException {
        _set(ScanStatus.unavailable);
      }
    } else {
      _permanentlyDenied =
          permission == CameraPermissionStatus.permanentlyDenied;
      _set(ScanStatus.permissionDenied);
    }
  }

  /// Opens the OS settings page (for the denied state).
  Future<bool> openSettings() => _permission.openSettings();

  void _set(ScanStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/scan/scan_controller_test.dart`
Expected: PASS (all 6 tests). *(Requires `scan_dependencies.dart` from Task 3 to exist for the import — create it now if absent.)*

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/scan_view_state.dart \
        apps/mobile/lib/features/scan/camera_permission_service.dart \
        apps/mobile/lib/features/scan/camera_preview_controller.dart \
        apps/mobile/lib/features/scan/scan_controller.dart \
        apps/mobile/test/support/fake_scan.dart \
        apps/mobile/test/features/scan/scan_controller_test.dart
git commit -m "feat(a2): scan state machine (ScanController) + interfaces, unit-tested"
```

---

## Task 3: Concrete plugin-backed implementations + `ScanDependencies` (composition root)

**Files:**
- Create: `apps/mobile/lib/features/scan/camera_permission_service_impl.dart`
- Create: `apps/mobile/lib/features/scan/camera_preview_controller_impl.dart`
- Create: `apps/mobile/lib/features/scan/scan_dependencies.dart`
- Test: `apps/mobile/test/features/scan/scan_dependencies_test.dart`

**Interfaces:**
- Consumes: `CameraPermissionService`, `CameraPreviewController`, `CameraUnavailableException` (Task 2); the `camera` and `permission_handler` packages (Task 1).
- Produces:
  - `class PermissionHandlerCameraPermissionService implements CameraPermissionService`
  - `class PluginCameraPreviewController implements CameraPreviewController`
  - `typedef CameraPermissionServiceFactory = CameraPermissionService Function();`
  - `typedef CameraPreviewControllerFactory = CameraPreviewController Function();`
  - `class ScanDependencies` with `const ScanDependencies({CameraPermissionServiceFactory createPermissionService, CameraPreviewControllerFactory createPreviewController})` defaulting to the concrete implementations, and fields `createPermissionService`, `createPreviewController`.

- [ ] **Step 1: Implement the composition root and concrete services**

`apps/mobile/lib/features/scan/camera_permission_service_impl.dart`:
```dart
import 'package:permission_handler/permission_handler.dart' as ph;

import 'camera_permission_service.dart';

/// Production [CameraPermissionService] backed by `permission_handler`.
class PermissionHandlerCameraPermissionService
    implements CameraPermissionService {
  const PermissionHandlerCameraPermissionService();

  @override
  Future<CameraPermissionStatus> request() async {
    final status = await ph.Permission.camera.request();
    if (status.isGranted || status.isLimited) {
      return CameraPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();
}
```

`apps/mobile/lib/features/scan/camera_preview_controller_impl.dart`:
```dart
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_preview_controller.dart';

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
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
```

`apps/mobile/lib/features/scan/scan_dependencies.dart`:
```dart
import 'camera_permission_service.dart';
import 'camera_permission_service_impl.dart';
import 'camera_preview_controller.dart';
import 'camera_preview_controller_impl.dart';

typedef CameraPermissionServiceFactory = CameraPermissionService Function();
typedef CameraPreviewControllerFactory = CameraPreviewController Function();

CameraPermissionService _defaultPermissionService() =>
    const PermissionHandlerCameraPermissionService();

CameraPreviewController _defaultPreviewController() =>
    PluginCameraPreviewController();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
class ScanDependencies {
  final CameraPermissionServiceFactory createPermissionService;
  final CameraPreviewControllerFactory createPreviewController;

  const ScanDependencies({
    this.createPermissionService = _defaultPermissionService,
    this.createPreviewController = _defaultPreviewController,
  });
}
```

- [ ] **Step 2: Write the failing test (composition root wires the right concrete types)**

`apps/mobile/test/features/scan/scan_dependencies_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service_impl.dart';
import 'package:mobile/features/scan/camera_preview_controller_impl.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

void main() {
  test('production ScanDependencies wires the plugin-backed implementations',
      () {
    const deps = ScanDependencies();
    expect(deps.createPermissionService(),
        isA<PermissionHandlerCameraPermissionService>());
    expect(deps.createPreviewController(),
        isA<PluginCameraPreviewController>());
  });
}
```

(Constructing these objects does **not** touch native code — the plugin is only called inside `request()`/`initialize()` — so this test is safe in the headless VM.)

- [ ] **Step 3: Run the test to verify it fails, then passes**

Run: `cd apps/mobile && flutter test test/features/scan/scan_dependencies_test.dart`
Expected: FAIL first (types undefined) if run before Step 1; after Step 1, PASS.

- [ ] **Step 4: Analyze clean**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/camera_permission_service_impl.dart \
        apps/mobile/lib/features/scan/camera_preview_controller_impl.dart \
        apps/mobile/lib/features/scan/scan_dependencies.dart \
        apps/mobile/test/features/scan/scan_dependencies_test.dart
git commit -m "feat(a2): plugin-backed camera/permission impls + ScanDependencies root"
```

---

## Task 4: `CameraScreen` + per-state views (widget tests)

**Files:**
- Create: `apps/mobile/lib/features/scan/camera_screen.dart`
- Create: `apps/mobile/lib/features/scan/widgets/camera_preview_view.dart`
- Create: `apps/mobile/lib/features/scan/widgets/permission_denied_view.dart`
- Create: `apps/mobile/lib/features/scan/widgets/camera_unavailable_view.dart`
- Test: `apps/mobile/test/features/scan/camera_screen_test.dart`

**Interfaces:**
- Consumes: `ScanController`, `ScanStatus`, `CameraPreviewController` (Task 2); `ScanDependencies` (Task 3); fakes/presets from `test/support/fake_scan.dart`.
- Produces: `class CameraScreen extends StatefulWidget` with `const CameraScreen({Key? key, ScanDependencies dependencies = const ScanDependencies()})`. AppBar title is the literal string `'Scan'`. Keyed anchors: checking spinner `Key('scan-checking')`, preview `Key('scan-preview')`. The rationale text is exactly `'Camera access is needed to scan documents'`; the settings button label is exactly `'Open Settings'`; the unavailable text is exactly `'Camera unavailable on this device'`.

- [ ] **Step 1: Write the per-state view widgets**

`apps/mobile/lib/features/scan/widgets/camera_preview_view.dart`:
```dart
import 'package:flutter/material.dart';

import '../camera_preview_controller.dart';

/// Frames the live preview produced by [controller] on a black backdrop.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;

  const CameraPreviewView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: controller.buildPreview()),
    );
  }
}
```

`apps/mobile/lib/features/scan/widgets/permission_denied_view.dart`:
```dart
import 'package:flutter/material.dart';

/// Shown when camera permission is denied: a rationale and an Open Settings
/// action. The single button keeps the flow KISS for both denied states.
class PermissionDeniedView extends StatelessWidget {
  final bool permanentlyDenied;
  final Future<bool> Function() onOpenSettings;

  const PermissionDeniedView({
    super.key,
    required this.permanentlyDenied,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Camera access is needed to scan documents',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onOpenSettings(),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/features/scan/widgets/camera_unavailable_view.dart`:
```dart
import 'package:flutter/material.dart';

/// Shown when the device has no usable camera, or it failed to initialize.
class CameraUnavailableView extends StatelessWidget {
  const CameraUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, size: 64),
            SizedBox(height: 16),
            Text(
              'Camera unavailable on this device',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Write the failing widget test**

`apps/mobile/test/features/scan/camera_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_screen.dart';

import '../../support/fake_scan.dart';

void main() {
  Widget host(child) => MaterialApp(home: child);

  testWidgets('granted → shows the live preview', (tester) async {
    await tester.pumpWidget(
      host(CameraScreen(dependencies: grantedScanDependencies())),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
  });

  testWidgets('denied → rationale + Open Settings; tap delegates', (tester) async {
    final deps = deniedScanDependencies();
    await tester.pumpWidget(host(CameraScreen(dependencies: deps)));
    await tester.pumpAndSettle();

    expect(find.text('Camera access is needed to scan documents'),
        findsOneWidget);
    final settingsButton = find.widgetWithText(FilledButton, 'Open Settings');
    expect(settingsButton, findsOneWidget);

    await tester.tap(settingsButton);
    await tester.pump();
    // The fake records the call; no crash on tap.
  });

  testWidgets('granted but no camera → unavailable message', (tester) async {
    await tester.pumpWidget(
      host(CameraScreen(dependencies: unavailableScanDependencies())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera unavailable on this device'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsNothing);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/camera_screen_test.dart`
Expected: FAIL — `CameraScreen` not defined.

- [ ] **Step 4: Implement `CameraScreen`**

`apps/mobile/lib/features/scan/camera_screen.dart`:
```dart
import 'package:flutter/material.dart';

import 'scan_controller.dart';
import 'scan_dependencies.dart';
import 'scan_view_state.dart';
import 'widgets/camera_preview_view.dart';
import 'widgets/camera_unavailable_view.dart';
import 'widgets/permission_denied_view.dart';

/// The Scan screen: requests camera permission and shows the live preview, or
/// a graceful fallback. Capture (shutter) arrives in A3.
class CameraScreen extends StatefulWidget {
  final ScanDependencies dependencies;

  const CameraScreen({super.key, this.dependencies = const ScanDependencies()});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final ScanController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScanController(
      permission: widget.dependencies.createPermissionService(),
      preview: widget.dependencies.createPreviewController(),
    );
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

- [ ] **Step 5: Run to verify it passes**

Run: `cd apps/mobile && flutter test test/features/scan/camera_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/scan/camera_screen.dart \
        apps/mobile/lib/features/scan/widgets/ \
        apps/mobile/test/features/scan/camera_screen_test.dart
git commit -m "feat(a2): CameraScreen + per-state views, widget-tested"
```

---

## Task 5: Wire navigation — Scan FAB opens the camera, deps flow through the app

**Files:**
- Modify: `apps/mobile/lib/main.dart`
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Test: `apps/mobile/test/features/library/home_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `CameraScreen`, `ScanDependencies`; fakes from `test/support/fake_scan.dart`.
- Produces:
  - `void runCamScannerApp({ScanDependencies scanDependencies = const ScanDependencies()})` (test entrypoint) in `main.dart`; `main()` calls it.
  - `CamScannerApp({Key? key, ScanDependencies scanDependencies = const ScanDependencies()})`.
  - `HomeScreen({Key? key, ScanDependencies dependencies = const ScanDependencies()})` whose Scan FAB pushes `CameraScreen(dependencies: dependencies)` via `MaterialPageRoute`.

- [ ] **Step 1: Write the failing navigation test (extend home_screen_test.dart)**

Add these imports and test to `apps/mobile/test/features/library/home_screen_test.dart` (keep the existing 3 tests):
```dart
import '../../support/fake_scan.dart';
// ... existing imports (material, flutter_test, home_screen) ...

// inside main():
  testWidgets('tapping Scan opens the camera screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(dependencies: grantedScanDependencies())),
    );

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/home_screen_test.dart`
Expected: FAIL — `HomeScreen` has no `dependencies` parameter / FAB does nothing.

- [ ] **Step 3: Wire the FAB and thread dependencies**

`apps/mobile/lib/features/library/home_screen.dart`:
```dart
import 'package:flutter/material.dart';

import '../scan/camera_screen.dart';
import '../scan/scan_dependencies.dart';
import 'widgets/empty_documents_view.dart';

/// The app's home: the document library. Shows the empty state and a Scan
/// button that opens the camera screen (A2).
class HomeScreen extends StatelessWidget {
  final ScanDependencies dependencies;

  const HomeScreen({super.key, this.dependencies = const ScanDependencies()});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: const EmptyDocumentsView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CameraScreen(dependencies: dependencies),
          ),
        ),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }
}
```

`apps/mobile/lib/main.dart`:
```dart
import 'package:flutter/material.dart';

import 'features/library/home_screen.dart';
import 'features/scan/scan_dependencies.dart';

void main() => runCamScannerApp();

/// App entrypoint that accepts injectable Scan dependencies, so integration
/// tests can drive deterministic camera states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
}) {
  runApp(CamScannerApp(scanDependencies: scanDependencies));
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamScanner-light',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: HomeScreen(dependencies: scanDependencies),
    );
  }
}
```

- [ ] **Step 4: Run the full suite (all unit + widget tests)**

Run: `cd apps/mobile && flutter test`
Expected: PASS — all tests across library + scan suites green.

- [ ] **Step 5: Analyze clean**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/main.dart apps/mobile/lib/features/library/home_screen.dart \
        apps/mobile/test/features/library/home_screen_test.dart
git commit -m "feat(a2): Scan FAB opens camera screen; inject deps through app entrypoint"
```

---

## Task 6: On-device integration tests + `scripts/verify/a2.sh`

**Files:**
- Create: `apps/mobile/integration_test/a2_camera_denied_test.dart`
- Create: `apps/mobile/integration_test/a2_camera_ready_test.dart`
- Create: `scripts/verify/a2.sh`

**Interfaces:**
- Consumes: `runCamScannerApp` (Task 5); `deniedScanDependencies`, `grantedScanDependencies` from `test/support/fake_scan.dart`; `verify_integration_{android,ios}`, `require_tool`, `assert_cmd`, `assert_file_has`, `verify_summary` from `scripts/verify/lib.sh`.
- Produces: two on-device tests + the A2 gate script.

> **Why fakes on-device:** the integration tests inject fake permission/preview so they assert the **rendered widget tree on a real device** deterministically — no native permission dialog (which the Flutter tester cannot tap) and no camera hardware (the iOS simulator has none). The **real** `camera`/`permission_handler` native code is still compiled and linked into the on-device build, so a broken manifest/plist/plugin version fails the integration build. Live camera frames and the real OS permission dialog are inherently manual and are exercised when capture (A3) runs on hardware; they are **not** A2 acceptance criteria.

- [ ] **Step 1: Write the denied-state on-device test**

`apps/mobile/integration_test/a2_camera_denied_test.dart`:
```dart
// On-device integration test for A2 (permission-denied path).
// Pumps the REAL app on the device with an injected denied-permission fake and
// asserts the rationale UI renders — proving navigation + state rendering on
// device. Run: flutter test integration_test/a2_camera_denied_test.dart -d <id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: denied permission shows rationale + Open Settings on device',
      (tester) async {
    app.runCamScannerApp(scanDependencies: deniedScanDependencies());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.text('Camera access is needed to scan documents'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open Settings'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Write the ready/preview on-device test**

`apps/mobile/integration_test/a2_camera_ready_test.dart`:
```dart
// On-device integration test for A2 (granted/preview path).
// Pumps the REAL app on the device with an injected granted-permission + fake
// preview and asserts the camera screen + preview render — proving the Scan
// FAB navigates and the ready state mounts on device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: granted permission shows the camera preview on device',
      (tester) async {
    app.runCamScannerApp(scanDependencies: grantedScanDependencies());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);

    // Sanity: we navigated away from the Documents home.
    expect(find.text('No documents yet'), findsNothing);
  });
}
```

- [ ] **Step 3: Run both integration tests on a device locally (sanity, before scripting)**

Run (Android emulator must be booted):
```bash
cd apps/mobile && flutter test integration_test/a2_camera_denied_test.dart integration_test/a2_camera_ready_test.dart -d emulator-5554
```
Expected: `All tests passed!` (substitute the actual emulator id from `adb devices`).

- [ ] **Step 4: Author `scripts/verify/a2.sh`**

`scripts/verify/a2.sh`:
```bash
#!/usr/bin/env bash
# Verify A2 (camera preview + permission) acceptance criteria.
# Run from anywhere: bash scripts/verify/a2.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip device launches — skipping is reported as
# a FAIL, never silent. Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== A2 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Native + dependency config (static asserts) ----
assert_file_has "android manifest declares CAMERA permission" \
  "apps/mobile/android/app/src/main/AndroidManifest.xml" "android.permission.CAMERA"
assert_file_has "ios Info.plist declares NSCameraUsageDescription" \
  "apps/mobile/ios/Runner/Info.plist" "NSCameraUsageDescription"
assert_file_has "pubspec depends on camera plugin" \
  "apps/mobile/pubspec.yaml" "camera:"
assert_file_has "pubspec depends on permission_handler" \
  "apps/mobile/pubspec.yaml" "permission_handler:"

# ---- Static criteria: unit + widget tests, analyze ----
# Covers ScanController state machine, ScanDependencies wiring, CameraScreen
# states, and Scan→camera navigation.
assert_cmd "a2 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

# ---- Device criteria: programmatic on-device UI (integration tests) ----
# Authoritative: pump the REAL app on each device and assert the camera screen's
# widget tree for the denied and granted/preview states. The real camera +
# permission_handler native code is compiled/linked into these device builds.
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android a2_camera_denied_test.dart
verify_integration_android a2_camera_ready_test.dart
verify_integration_ios a2_camera_denied_test.dart
verify_integration_ios a2_camera_ready_test.dart

verify_summary
```

- [ ] **Step 5: Make it executable and run the full gate**

Run:
```bash
chmod +x scripts/verify/a2.sh
bash scripts/verify/a2.sh
```
Expected: ends with `GATE: PASS` and a summary line with `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/integration_test/a2_camera_denied_test.dart \
        apps/mobile/integration_test/a2_camera_ready_test.dart \
        scripts/verify/a2.sh
git commit -m "test(a2): on-device integration tests + a2 verify gate"
```

---

## Definition of Done (gate)

A2 is done only when **all** hold (observed, not narrated):

1. `pnpm nx run mobile:test --skip-nx-cache` → `All tests passed!` (unit: `ScanController`, `ScanDependencies`; widget: `CameraScreen` states + Scan→camera navigation).
2. `pnpm nx run mobile:analyze --skip-nx-cache` → clean.
3. Native config present: Android `CAMERA` permission, iOS `NSCameraUsageDescription`; `camera` + `permission_handler` on the dependency path.
4. `scripts/verify/a2.sh` exits 0 (`GATE: PASS`) with the four on-device integration runs (denied + ready, on Android **and** iOS) reporting `All tests passed!`.
5. Each new integration test is **mutation-checked once** by the independent verifier (inject a guaranteed-false assertion → confirm the gate FAILS → revert).
6. An **independent adversarial verifier** runs `scripts/verify/a2.sh` from a clean state and agrees.

## Acceptance criteria → test mapping

- [ ] Tapping **Scan** opens the camera screen — *widget: home_screen_test "tapping Scan opens the camera screen"; on-device: both a2 integration tests*
- [ ] Camera permission **granted** → live preview shown — *unit: ScanController "granted → ready"; widget: camera_screen_test "granted → preview"; on-device: a2_camera_ready*
- [ ] Permission **denied** → rationale + Open Settings, no crash — *unit: ScanController denied cases; widget: camera_screen_test "denied"; on-device: a2_camera_denied*
- [ ] **No camera / init error** → graceful "camera unavailable", no crash — *unit: ScanController "no camera → unavailable"; widget: camera_screen_test "unavailable"*
- [ ] Real plugins compiled + linked on both devices — *the four on-device integration builds in a2.sh*

## Self-Review notes

- **Spec coverage:** A2 covers Feature 01's *permission & error handling* + *live preview* slice. Capture, modes, torch/grid/focus, auto-capture are deferred to later steps (A3+) per the roadmap — intentionally out of scope.
- **Type consistency:** `ScanStatus`, `CameraPermissionStatus`, the two interfaces, `CameraUnavailableException`, `ScanDependencies` factory names, and the exact UI strings/keys are defined once (Tasks 2–4) and referenced verbatim by tests.
- **DRY:** test fakes live once in `test/support/fake_scan.dart`; integration tests import them via the cross-tree relative path `../test/support/fake_scan.dart` (intentional — a single shared fake, not duplicated).
- **iOS permission_handler macros:** omitted deliberately. Without the Podfile `GCC_PREPROCESSOR_DEFINITIONS` block, all permission handlers compile in by default — camera permission still functions. Trimming to `PERMISSION_CAMERA=1` is App-Store-privacy hardening for a later packaging step, not an A2 functional requirement.
