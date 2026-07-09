# Strict Single-Shot ID Capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the OS multi-page scanner in the ID flow (and the in-document page-retake flow) with a single-shot camera + in-app Retake/Accept preview that auto-advances, enforcing exactly one photo per side on both Android and iOS.

**Architecture:** A new injectable `PhotoCamera` seam (backed by `image_picker`'s camera) plus a `CameraPermission` seam (backed by `permission_handler`) feed a per-side capture→review loop. Each side reuses the existing `CaptureReviewScreen` (auto edge-detect + crop overlay + Retake/Accept + filters). Save/persist logic is unchanged.

**Tech Stack:** Flutter, Dart 3 (sealed classes, switch expressions), `image_picker`, `permission_handler` (new), `opencv_dart` (existing edge detector), `bdd_widget_test`, `drift`.

**Spec:** `docs/superpowers/specs/2026-07-09-strict-single-shot-id-capture-design.md`

## Global Constraints

- All Flutter commands run from `apps/mobile/`, never the repo root.
- TDD: write the failing test first, watch it fail, then implement. BDD: user-facing behavior gets a `.feature` scenario + generated `*_test.dart` + steps in `test/step/`.
- Zero-warning bar: `flutter analyze` must be clean after every task.
- `dart format lib test` before every commit.
- Const-constructible DI: thread every collaborator through the `*Dependencies` class; never `new` it inline.
- Image bytes on disk, DB stores relative paths only (unchanged here — we reuse the existing repository).
- Host widget tests must pass NON-LOADABLE image paths (e.g. `/nonexistent/front.jpg`) so `FilterPickerStrip` does not deadlock generating thumbnails under `FakeAsync`.
- `git add` only named paths (never `-A`) — the working tree carries a long-lived WIP pile.
- Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi
  ```
- Definition of done includes a real Android device AND a real iOS device run (Task 8). Host-green is not done.

---

### Task 1: `PhotoCamera` seam + `FakePhotoCamera` + DI wiring

**Files:**
- Create: `lib/features/scan/photo_camera.dart`
- Modify: `lib/features/scan/scan_dependencies.dart`
- Modify: `test/support/fake_scan.dart` (add `FakePhotoCamera`)
- Test: `test/features/scan/scan_dependencies_test.dart`, `test/features/scan/photo_camera_fake_test.dart`

**Interfaces:**
- Produces: `abstract interface class PhotoCamera { Future<CapturedImage?> capture(); }`, `class ImagePickerPhotoCamera implements PhotoCamera`, `typedef PhotoCameraFactory = PhotoCamera Function();`, `ScanDependencies.createPhotoCamera` (default `ImagePickerPhotoCamera`), and test double `class FakePhotoCamera implements PhotoCamera { int captureCount; FakePhotoCamera(List<String?> paths); }` (null entry = user cancelled).

- [ ] **Step 1: Write the failing DI test**

Add to `test/features/scan/scan_dependencies_test.dart` (inside `main()`), and add the import `import 'package:mobile/features/scan/photo_camera.dart';` at the top:

```dart
  test('createPhotoCamera defaults to ImagePickerPhotoCamera', () {
    expect(const ScanDependencies().createPhotoCamera(),
        isA<ImagePickerPhotoCamera>());
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/scan_dependencies_test.dart`
Expected: FAIL — `photo_camera.dart` and `createPhotoCamera` do not exist (compile error).

- [ ] **Step 3: Create `photo_camera.dart`**

```dart
import 'package:image_picker/image_picker.dart';

import 'captured_image.dart';

/// Captures a single photo from the device camera. Injectable (DIP) so widget
/// and BDD tests use a fake instead of the platform camera. Parallel to
/// [GalleryPicker].
abstract interface class PhotoCamera {
  /// Returns the captured photo as a [CapturedImage], or null if the user
  /// cancelled. Never throws.
  Future<CapturedImage?> capture();
}

/// Production camera backed by image_picker. One shot per call on both
/// platforms — nothing leaves the device. Thin adapter (not host-testable — the
/// native camera UI is out of Flutter's reach); the flow is tested through
/// [PhotoCamera] with a fake.
class ImagePickerPhotoCamera implements PhotoCamera {
  const ImagePickerPhotoCamera();
  @override
  Future<CapturedImage?> capture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera);
    return x == null ? null : CapturedImage(x.path);
  }
}
```

- [ ] **Step 4: Wire `createPhotoCamera` into `ScanDependencies`**

In `lib/features/scan/scan_dependencies.dart`, add the import, the typedef, the default factory, and the field. Full edited file:

```dart
import 'cunning_document_scanner_service.dart';
import 'document_scanner_service.dart';
import 'edge_detector.dart';
import 'gallery_picker.dart';
import 'opencv_edge_detector.dart';
import 'photo_camera.dart';

typedef DocumentScannerServiceFactory = DocumentScannerService Function();
typedef EdgeDetectorFactory = EdgeDetector Function();
typedef GalleryPickerFactory = GalleryPicker Function();
typedef PhotoCameraFactory = PhotoCamera Function();

DocumentScannerService _defaultDocumentScanner() =>
    const CunningDocumentScannerService();

EdgeDetector _defaultEdgeDetector() => const OpenCvEdgeDetector();

GalleryPicker _defaultGalleryPicker() => const ImagePickerGalleryPicker();

PhotoCamera _defaultPhotoCamera() => const ImagePickerPhotoCamera();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
class ScanDependencies {
  final DocumentScannerServiceFactory createDocumentScanner;
  final EdgeDetectorFactory createEdgeDetector;
  final GalleryPickerFactory createGalleryPicker;
  final PhotoCameraFactory createPhotoCamera;

  const ScanDependencies({
    this.createDocumentScanner = _defaultDocumentScanner,
    this.createEdgeDetector = _defaultEdgeDetector,
    this.createGalleryPicker = _defaultGalleryPicker,
    this.createPhotoCamera = _defaultPhotoCamera,
  });
}
```

- [ ] **Step 5: Run DI test to verify it passes**

Run: `flutter test test/features/scan/scan_dependencies_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 6: Add `FakePhotoCamera` + a test for it**

Append to `test/support/fake_scan.dart` (and add `import 'package:mobile/features/scan/photo_camera.dart';` to its imports):

```dart
/// Fake [PhotoCamera] for host tests. The i-th `capture()` returns
/// `paths[i]` wrapped in a [CapturedImage] (a null entry = user cancelled);
/// returns null once exhausted. Pass NON-LOADABLE paths in host widget tests so
/// the review screen's FilterPickerStrip does not generate thumbnails. Exposes
/// [captureCount] to assert exactly one photo per side (and retake = one more).
class FakePhotoCamera implements PhotoCamera {
  final List<String?> paths;
  int captureCount = 0;
  FakePhotoCamera(this.paths);

  @override
  Future<CapturedImage?> capture() async {
    final i = captureCount;
    captureCount++;
    final p = i < paths.length ? paths[i] : null;
    return p == null ? null : CapturedImage(p);
  }
}
```

Create `test/features/scan/photo_camera_fake_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_scan.dart';

void main() {
  test('FakePhotoCamera returns sequential shots then null; counts calls',
      () async {
    final cam = FakePhotoCamera(['/nonexistent/a.jpg', null]);
    final first = await cam.capture();
    final second = await cam.capture();
    final third = await cam.capture();
    expect(first?.path, '/nonexistent/a.jpg');
    expect(second, isNull); // explicit cancel entry
    expect(third, isNull); // exhausted
    expect(cam.captureCount, 3);
  });
}
```

- [ ] **Step 7: Run the fake test + analyze**

Run: `flutter test test/features/scan/photo_camera_fake_test.dart && flutter analyze`
Expected: PASS; analyze clean.

- [ ] **Step 8: Format + commit**

```bash
dart format lib test
git add lib/features/scan/photo_camera.dart lib/features/scan/scan_dependencies.dart test/support/fake_scan.dart test/features/scan/scan_dependencies_test.dart test/features/scan/photo_camera_fake_test.dart
git commit -m "feat(scan): PhotoCamera seam + FakePhotoCamera for single-shot capture

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 2: `CameraPermission` seam + `permission_handler` + DI

**Files:**
- Modify: `pubspec.yaml` (add `permission_handler` via `flutter pub add`)
- Create: `lib/features/scan/camera_permission.dart`
- Modify: `lib/features/scan/scan_dependencies.dart`
- Modify: `ios/Podfile` (permission_handler macros — camera only)
- Modify: `test/support/fake_scan.dart` (add `FakeCameraPermission`)
- Test: `test/features/scan/scan_dependencies_test.dart`, `test/features/scan/camera_permission_fake_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `abstract interface class CameraPermission { Future<bool> ensure(); }`, `class PermissionHandlerCameraPermission implements CameraPermission`, `typedef CameraPermissionFactory = CameraPermission Function();`, `ScanDependencies.createCameraPermission` (default `PermissionHandlerCameraPermission`), and test double `class FakeCameraPermission implements CameraPermission { int calls; FakeCameraPermission({bool granted}); }`.

**Why:** `image_picker`'s camera is a first-time code path in this app; the merged Android manifest declares `android.permission.CAMERA`, so `pickImage(source: camera)` requires a runtime grant or it fails. There is no `permission_handler` or runtime request today. iOS also gets a deterministic grant/deny via the same seam (`NSCameraUsageDescription` already present).

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add permission_handler`
Expected: `pubspec.yaml` gains a `permission_handler` line; `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing DI test**

Add to `test/features/scan/scan_dependencies_test.dart` and add `import 'package:mobile/features/scan/camera_permission.dart';`:

```dart
  test('createCameraPermission defaults to PermissionHandlerCameraPermission',
      () {
    expect(const ScanDependencies().createCameraPermission(),
        isA<PermissionHandlerCameraPermission>());
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/scan/scan_dependencies_test.dart`
Expected: FAIL — `camera_permission.dart` / `createCameraPermission` missing.

- [ ] **Step 4: Create `camera_permission.dart`**

```dart
import 'package:permission_handler/permission_handler.dart';

/// Ensures runtime camera access before a [PhotoCamera] capture. Injectable
/// (DIP) so host tests never touch platform channels.
abstract interface class CameraPermission {
  /// Requests/checks camera permission. Returns true when the camera is
  /// usable, false when denied. Never throws.
  Future<bool> ensure();
}

/// Production gate backed by permission_handler. Required because the Android
/// manifest declares CAMERA, which image_picker's camera then requires at
/// runtime; iOS resolves against NSCameraUsageDescription.
class PermissionHandlerCameraPermission implements CameraPermission {
  const PermissionHandlerCameraPermission();
  @override
  Future<bool> ensure() async {
    try {
      final status = await Permission.camera.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 5: Wire `createCameraPermission` into `ScanDependencies`**

In `lib/features/scan/scan_dependencies.dart` add `import 'camera_permission.dart';`, the typedef `typedef CameraPermissionFactory = CameraPermission Function();`, the default:

```dart
CameraPermission _defaultCameraPermission() =>
    const PermissionHandlerCameraPermission();
```

and add the field + constructor default (place alongside the others):

```dart
  final CameraPermissionFactory createCameraPermission;
```
```dart
    this.createCameraPermission = _defaultCameraPermission,
```

- [ ] **Step 6: Run DI test to verify it passes**

Run: `flutter test test/features/scan/scan_dependencies_test.dart`
Expected: PASS.

- [ ] **Step 7: Add `FakeCameraPermission` + a test**

Append to `test/support/fake_scan.dart` (add `import 'package:mobile/features/scan/camera_permission.dart';`):

```dart
/// Fake [CameraPermission] for host tests. Returns [granted] and counts calls.
class FakeCameraPermission implements CameraPermission {
  final bool granted;
  int calls = 0;
  FakeCameraPermission({this.granted = true});

  @override
  Future<bool> ensure() async {
    calls++;
    return granted;
  }
}
```

Create `test/features/scan/camera_permission_fake_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_scan.dart';

void main() {
  test('FakeCameraPermission returns configured value and counts calls',
      () async {
    final denied = FakeCameraPermission(granted: false);
    expect(await denied.ensure(), isFalse);
    expect(denied.calls, 1);
    final granted = FakeCameraPermission();
    expect(await granted.ensure(), isTrue);
  });
}
```

- [ ] **Step 8: Configure iOS Podfile (camera-only permission macros)**

The app ships to the App Store, so strip unused permission_handler permissions and enable only camera. In `ios/Podfile`, replace the existing `post_install` block with:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        # permission_handler: enable ONLY camera; disable everything else.
        'PERMISSION_CAMERA=1',
        'PERMISSION_EVENTS=0',
        'PERMISSION_EVENTS_FULL_ACCESS=0',
        'PERMISSION_REMINDERS=0',
        'PERMISSION_CONTACTS=0',
        'PERMISSION_MICROPHONE=0',
        'PERMISSION_SPEECH_RECOGNIZER=0',
        'PERMISSION_PHOTOS=0',
        'PERMISSION_NOTIFICATIONS=0',
        'PERMISSION_MEDIA_LIBRARY=0',
        'PERMISSION_SENSORS=0',
        'PERMISSION_BLUETOOTH=0',
        'PERMISSION_APP_TRACKING_TRANSPARENCY=0',
        'PERMISSION_CRITICAL_ALERTS=0',
        'PERMISSION_ASSISTANT=0',
        'PERMISSION_LOCATION=0',
      ]
    end
  end
end
```

- [ ] **Step 9: Run tests + analyze**

Run: `flutter test test/features/scan/camera_permission_fake_test.dart test/features/scan/scan_dependencies_test.dart && flutter analyze`
Expected: PASS; analyze clean.

- [ ] **Step 10: Format + commit**

```bash
dart format lib test
git add pubspec.yaml pubspec.lock lib/features/scan/camera_permission.dart lib/features/scan/scan_dependencies.dart ios/Podfile test/support/fake_scan.dart test/features/scan/camera_permission_fake_test.dart test/features/scan/scan_dependencies_test.dart
git commit -m "feat(scan): CameraPermission seam (permission_handler) for camera runtime grant

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 3: `CaptureReviewScreen` — `title`, `acceptLabel`, `initialMode` params

**Files:**
- Modify: `lib/features/scan/capture_review_screen.dart`
- Test: `test/features/scan/capture_review_params_test.dart`

**Interfaces:**
- Consumes: existing `CaptureReviewScreen` (keys `review-accept`, `review-retake`; `EnhancerMode` from `../library/enhancer_mode.dart`; `NoneEnhancer` from `../library/image_enhancer.dart`).
- Produces: `CaptureReviewScreen({..., String title = 'Review', String acceptLabel = 'Accept', EnhancerMode initialMode = EnhancerMode.auto})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/scan/capture_review_params_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

void main() {
  testWidgets('renders custom title + acceptLabel and starts in initialMode',
      (tester) async {
    ImageEnhancer? accepted;
    await tester.pumpWidget(MaterialApp(
      home: CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/front.jpg'),
        title: 'Front of ID',
        acceptLabel: 'Use',
        initialMode: EnhancerMode.none,
        enableCrop: true,
        onRetake: () {},
        onAccept: (_, enhancer) => accepted = enhancer,
      ),
    ));
    await tester.pump();

    expect(find.text('Front of ID'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump();
    expect(accepted, isA<NoneEnhancer>()); // initialMode none, untouched
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/capture_review_params_test.dart`
Expected: FAIL — named params `title` / `acceptLabel` / `initialMode` don't exist.

- [ ] **Step 3: Add the params**

In `lib/features/scan/capture_review_screen.dart`:

Add three fields to the `StatefulWidget` (after `edgeDetector`):
```dart
  final String title;             // NEW
  final String acceptLabel;       // NEW
  final EnhancerMode initialMode; // NEW
```
Add to the constructor (after `this.edgeDetector,`):
```dart
    this.title = 'Review',
    this.acceptLabel = 'Accept',
    this.initialMode = EnhancerMode.auto,
```
In the state, replace the field initializer `EnhancerMode _mode = EnhancerMode.auto;` with `late EnhancerMode _mode;` and set it in `initState` (as the first line of the existing `initState`, before `super.initState()` is not allowed — put it right after `super.initState();`):
```dart
    _mode = widget.initialMode;
```
Replace the AppBar `title: const Text('Review'),` with `title: Text(widget.title),`.
Replace the accept button's `label: const Text('Accept'),` with `label: Text(widget.acceptLabel),`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/scan/capture_review_params_test.dart`
Expected: PASS.

- [ ] **Step 5: Guard against regressions + analyze**

Run: `flutter test test/features/scan/ && flutter analyze`
Expected: All existing capture-review tests still PASS (defaults unchanged); analyze clean.

- [ ] **Step 6: Format + commit**

```bash
dart format lib test
git add lib/features/scan/capture_review_screen.dart test/features/scan/capture_review_params_test.dart
git commit -m "feat(scan): optional title/acceptLabel/initialMode on CaptureReviewScreen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 4: Rewrite `IdScanScreen` as capture→review→save loop

**Files:**
- Modify: `lib/features/scan/id_scan_screen.dart` (full rewrite)
- Test: `test/features/scan/id_scan_screen_test.dart` (rewrite)

**Interfaces:**
- Consumes: `ScanDependencies.createPhotoCamera` (Task 1), `.createCameraPermission` (Task 2), `.createEdgeDetector` (existing); `CaptureReviewScreen(title, acceptLabel, initialMode, enableCrop, edgeDetector, onRetake, onAccept)` (Task 3); `SaveController.save/addPage`, `DocumentRepository.markAsIdCard` (existing).
- Produces: unchanged public `IdScanScreen({dependencies, repository})`.

- [ ] **Step 1: Rewrite the widget tests first (they will fail to compile/run)**

Replace the entire body of `test/features/scan/id_scan_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/id_scan_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

Widget _host(IdScanScreen screen) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

/// Deps with a sequential fake camera (null = cancel), a granted permission,
/// and a null-returning edge detector (nonexistent paths never reach detect()).
ScanDependencies _deps(
  List<String?> shots, {
  bool granted = true,
}) =>
    ScanDependencies(
      createPhotoCamera: () => FakePhotoCamera(shots),
      createCameraPermission: () => FakeCameraPermission(granted: granted),
      createEdgeDetector: () => FakeEdgeDetector(),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _accept(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}

Future<void> _retake(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-retake')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accept front then back saves a 2-page id-card document',
      (tester) async {
    final repo = FakeDocumentRepository();
    final deps = _deps(const ['/nonexistent/front.jpg', '/nonexistent/back.jpg']);
    await tester.pumpWidget(_host(
        IdScanScreen(dependencies: deps, repository: repo)));
    await _open(tester); // permission → capture front → review appears
    await _accept(tester); // advance to back → capture → review appears
    await _accept(tester); // save + pop

    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 1);
    expect(repo.markIdCardCalls.length, 1);
    expect(find.byType(IdScanScreen), findsNothing); // popped
  });

  testWidgets('retaking the front captures again; still one 2-page doc',
      (tester) async {
    final repo = FakeDocumentRepository();
    final cam = FakePhotoCamera(
        const ['/nonexistent/front1.jpg', '/nonexistent/front2.jpg', '/nonexistent/back.jpg']);
    final deps = ScanDependencies(
      createPhotoCamera: () => cam,
      createCameraPermission: () => FakeCameraPermission(),
      createEdgeDetector: () => FakeEdgeDetector(),
    );
    // Inject the SAME camera instance so captureCount survives.
    await tester.pumpWidget(_host(
        IdScanScreen(dependencies: deps, repository: repo)));
    await _open(tester); // capture front1 → review
    await _retake(tester); // capture front2 → review
    await _accept(tester); // front accepted → capture back → review
    await _accept(tester); // save + pop

    expect(cam.captureCount, 3);
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 1);
  });

  testWidgets('cancel on front saves nothing and pops', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(_host(IdScanScreen(
        dependencies: _deps(const [null]), repository: repo)));
    await _open(tester);
    expect(repo.createCalls, 0);
    expect(find.byType(IdScanScreen), findsNothing);
  });

  testWidgets('permission denied saves nothing, never opens camera',
      (tester) async {
    final repo = FakeDocumentRepository();
    final cam = FakePhotoCamera(const ['/nonexistent/front.jpg']);
    final deps = ScanDependencies(
      createPhotoCamera: () => cam,
      createCameraPermission: () => FakeCameraPermission(granted: false),
      createEdgeDetector: () => FakeEdgeDetector(),
    );
    await tester.pumpWidget(_host(
        IdScanScreen(dependencies: deps, repository: repo)));
    await _open(tester);
    expect(cam.captureCount, 0);
    expect(repo.createCalls, 0);
    expect(find.byType(IdScanScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/scan/id_scan_screen_test.dart`
Expected: FAIL — the current `IdScanScreen` uses the scanner, ignores the camera/permission deps, and has no review step, so `review-accept` is never found.

- [ ] **Step 3: Rewrite `id_scan_screen.dart`**

Full replacement:

```dart
import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/enhancer_mode.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'camera_permission.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'photo_camera.dart';
import 'scan_dependencies.dart';

/// Guided 2-step ID capture: shoot the front, review (Retake/Use) — accepting
/// auto-advances — then the back, then save both as a single ID-card document
/// (front = page 1, back = page 2). Exactly one photo per side; auto-cropped via
/// the edge detector with a full-frame fallback.
class IdScanScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;

  const IdScanScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
  });

  @override
  State<IdScanScreen> createState() => _IdScanScreenState();
}

enum _Step { front, back, saving }

/// One accepted side: the photo plus its reviewed crop + filter.
class _SideResult {
  final CapturedImage image;
  final CropCorners corners;
  final ImageEnhancer enhancer;
  const _SideResult(this.image, this.corners, this.enhancer);
}

/// Outcome of one review screen.
sealed class _ReviewOutcome {}

class _Accepted extends _ReviewOutcome {
  final CropCorners corners;
  final ImageEnhancer enhancer;
  _Accepted(this.corners, this.enhancer);
}

class _Retake extends _ReviewOutcome {}

class _IdScanScreenState extends State<IdScanScreen> {
  late final PhotoCamera _camera;
  late final CameraPermission _permission;
  late final EdgeDetector _detector;
  late final SaveController _saveController;
  _Step _step = _Step.front;

  @override
  void initState() {
    super.initState();
    _camera = widget.dependencies.createPhotoCamera();
    _permission = widget.dependencies.createCameraPermission();
    _detector = widget.dependencies.createEdgeDetector();
    _saveController = SaveController(repository: widget.repository);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!await _permission.ensure()) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Camera permission is needed to scan an ID.')));
      navigator.pop();
      return;
    }

    final front = await _captureSide('Front of ID');
    if (!mounted) return;
    if (front == null) {
      navigator.pop();
      return;
    }

    setState(() => _step = _Step.back);
    final back = await _captureSide('Back of ID');
    if (!mounted) return;
    if (back == null) {
      navigator.pop();
      return;
    }

    setState(() => _step = _Step.saving);
    final doc = await _saveController.save(front.image,
        corners: front.corners, enhancer: front.enhancer);
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save the ID. Try again.")),
      );
      navigator.pop();
      return;
    }
    final pos = await _saveController.addPage(back.image, doc.id,
        corners: back.corners, enhancer: back.enhancer);
    if (!mounted) return;
    if (pos == null) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text("Saved the front, but the back failed. Retake it "
                "from the document.")),
      );
      navigator.pop();
      return;
    }
    try {
      await widget.repository.markAsIdCard(doc.id);
    } catch (_) {
      // Non-fatal: the doc is saved; it just exports with the default layout.
    }
    if (mounted) navigator.pop();
  }

  /// Captures one side: single photo → review, looping on Retake. Returns the
  /// accepted result, or null if the user cancelled (camera-cancel or
  /// system-back on the review).
  Future<_SideResult?> _captureSide(String title) async {
    while (true) {
      final photo = await _camera.capture();
      if (!mounted || photo == null) return null;
      final outcome = await _review(photo, title);
      if (!mounted) return null;
      switch (outcome) {
        case _Accepted(:final corners, :final enhancer):
          return _SideResult(photo, corners, enhancer);
        case _Retake():
          continue;
        case null:
          return null; // system back
      }
    }
  }

  Future<_ReviewOutcome?> _review(CapturedImage photo, String title) {
    return Navigator.of(context).push<_ReviewOutcome>(
      MaterialPageRoute<_ReviewOutcome>(
        builder: (context) => CaptureReviewScreen(
          image: photo,
          title: title,
          acceptLabel: 'Use',
          enableCrop: true,
          edgeDetector: _detector,
          initialMode: EnhancerMode.none,
          onRetake: () => Navigator.of(context).pop(_Retake()),
          onAccept: (corners, enhancer) =>
              Navigator.of(context).pop(_Accepted(corners, enhancer)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_step) {
      _Step.front => 'Scan the FRONT of the ID',
      _Step.back => 'Scan the BACK of the ID',
      _Step.saving => 'Saving…',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ID')),
      body: Center(
        key: const Key('id-scan-status'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/scan/id_scan_screen_test.dart`
Expected: PASS (all four).

- [ ] **Step 5: Analyze + full scan-feature suite**

Run: `flutter analyze && flutter test test/features/scan/`
Expected: analyze clean; all scan tests PASS.

- [ ] **Step 6: Format + commit**

```bash
dart format lib test
git add lib/features/scan/id_scan_screen.dart test/features/scan/id_scan_screen_test.dart
git commit -m "feat(scan): strict single-shot ID capture with Retake/Use auto-advance

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 5: Switch in-document page retake to single-shot camera

**Files:**
- Modify: `lib/features/scan/scan_screen.dart` (retake branch only)
- Test: `test/features/scan/scan_screen_retake_test.dart` (create; if a retake test already exists elsewhere, update it instead)

**Interfaces:**
- Consumes: `ScanDependencies.createPhotoCamera`, `.createCameraPermission`, `.createEdgeDetector`; `CaptureReviewScreen` (crop-enabled); `ScanScreen.onCapture(CapturedImage, CropCorners, ImageEnhancer) → Future<bool>` (existing signature, unchanged).
- Produces: retake branch now sources one photo from the camera and passes the reviewed (non-fullFrame) corners to `onCapture`. The non-retake batch branch is untouched (still the OS scanner).

- [ ] **Step 1: Write the failing test**

Create `test/features/scan/scan_screen_retake_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  testWidgets('retake mode captures from the camera and calls onCapture',
      (tester) async {
    CapturedImage? captured;
    final deps = ScanDependencies(
      createPhotoCamera: () => FakePhotoCamera(const ['/nonexistent/retake.jpg']),
      createCameraPermission: () => FakeCameraPermission(),
      createEdgeDetector: () => FakeEdgeDetector(),
    );
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        dependencies: deps,
        repository: FakeDocumentRepository(),
        onCapture: (image, corners, enhancer) async {
          captured = image;
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle(); // permission → capture → review appears
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(captured?.path, '/nonexistent/retake.jpg');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scan/scan_screen_retake_test.dart`
Expected: FAIL — current retake branch uses the scanner and a filter-only review; the injected camera is never called.

- [ ] **Step 3: Modify the retake branch in `scan_screen.dart`**

Add imports at the top of `lib/features/scan/scan_screen.dart`:
```dart
import 'camera_permission.dart';
import 'capture_review_screen.dart';
import 'edge_detector.dart';
import 'photo_camera.dart';
```
Add fields to `_ScanScreenState` (after `late final SaveController _saveController;`):
```dart
  late final PhotoCamera _camera;
  late final CameraPermission _permission;
  late final EdgeDetector _detector;
```
In `initState`, after `_saveController = SaveController(...)`, add:
```dart
    _camera = widget.dependencies.createPhotoCamera();
    _permission = widget.dependencies.createCameraPermission();
    _detector = widget.dependencies.createEdgeDetector();
```
Replace the whole `_run()` method's retake branch. Change the top of `_run()` so retake short-circuits to a dedicated method BEFORE touching the scanner:

```dart
  Future<void> _run() async {
    if (widget.onCapture != null) {
      await _runRetake();
      return;
    }
    final navigator = Navigator.of(context);
    final pages = await _scanner.scan(pageLimit: null);
    if (!mounted) return;
    if (pages.isEmpty) {
      navigator.pop();
      return;
    }
    final enhancer = await _pickFilter(pages.first);
    if (!mounted) return;
    if (enhancer == null) {
      navigator.pop(); // review cancelled → discard batch
      return;
    }
    setState(() {
      _pages = pages;
      _enhancer = enhancer;
    });
    await _saveAll(pages, enhancer);
    if (mounted && !_saveFailed) navigator.pop();
  }

  /// Single-shot camera + crop-enabled review, looping on Retake, then hands the
  /// reviewed page to [onCapture].
  Future<void> _runRetake() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _permission.ensure()) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Camera permission is needed to retake a page.')));
      navigator.pop();
      return;
    }
    while (true) {
      final photo = await _camera.capture();
      if (!mounted) return;
      if (photo == null) {
        navigator.pop();
        return;
      }
      final outcome = await _reviewRetake(photo);
      if (!mounted) return;
      if (outcome == null) {
        navigator.pop(); // system back → cancel
        return;
      }
      if (outcome is _RetakeAgain) {
        continue;
      }
      final accepted = outcome as _AcceptedPage;
      final success =
          await widget.onCapture!(photo, accepted.corners, accepted.enhancer);
      if (!mounted) return;
      if (!success) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't replace page. Try again.")),
        );
      }
      navigator.pop();
      return;
    }
  }

  Future<_RetakeReview?> _reviewRetake(CapturedImage photo) {
    return Navigator.of(context).push<_RetakeReview>(
      MaterialPageRoute<_RetakeReview>(
        builder: (context) => CaptureReviewScreen(
          image: photo,
          title: 'Retake page',
          acceptLabel: 'Use',
          enableCrop: true,
          edgeDetector: _detector,
          onRetake: () => Navigator.of(context).pop(_RetakeAgain()),
          onAccept: (corners, enhancer) =>
              Navigator.of(context).pop(_AcceptedPage(corners, enhancer)),
        ),
      ),
    );
  }
```

Delete the now-unused `_pickFilter`'s retake usage is fine (it stays for the batch branch). Add the outcome types at the bottom of the file (top-level, after the class):

```dart
sealed class _RetakeReview {}

class _AcceptedPage extends _RetakeReview {
  final CropCorners corners;
  final ImageEnhancer enhancer;
  _AcceptedPage(this.corners, this.enhancer);
}

class _RetakeAgain extends _RetakeReview {}
```

> Note: the batch (`onCapture == null`) path keeps `_pickFilter` (filter-only, `enableCrop: false`) and `_saveAll` exactly as before — only the retake branch changed. Verify `_pickFilter` is still referenced by the batch path; if analyze reports it unused, that means the batch path was accidentally altered — revert to the code above.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/scan/scan_screen_retake_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full ScanScreen + scan suite + analyze**

Run: `flutter analyze && flutter test test/features/scan/`
Expected: analyze clean (no unused `_pickFilter`), all scan tests PASS (batch-scan tests unaffected).

- [ ] **Step 6: Format + commit**

```bash
dart format lib test
git add lib/features/scan/scan_screen.dart test/features/scan/scan_screen_retake_test.dart
git commit -m "feat(scan): in-document page retake uses single-shot camera + crop review

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 6: BDD `.feature` — fake-camera launch + explicit accept/retake steps

**Files:**
- Modify: `integration_test/id_scan.feature`
- Create step: `test/step/the_app_is_launched_with_a_fake_id_camera_returning_a_front_and_a_back.dart`
- Create step: `test/step/i_accept_the_captured_front.dart`
- Create step: `test/step/i_accept_the_captured_back.dart`
- Create step: `test/step/i_retake_the_front.dart`
- Modify step: `test/step/an_id_card_document_with2_pages_is_saved.dart` (import path → new launch step)
- Delete: `test/step/the_app_is_launched_with_a_fake_id_scanner_returning_a_front_and_a_back.dart`
- Regenerate: `integration_test/id_scan_test.dart` (via build_runner)

**Interfaces:**
- Consumes: `app.runCamScannerApp(scanDependencies, libraryDependencies)`, `FakePhotoCamera`, `FakeCameraPermission`, `fakeLibraryDependencies`, shared `idScanRepo`.
- Produces: a `.feature` whose scenarios drive the review steps explicitly.

- [ ] **Step 1: Rewrite `id_scan.feature`**

```gherkin
Feature: Scan an ID card

  Scenario: Accepting front and back saves a 2-page ID document
    Given the app is launched with a fake ID camera returning a front and a back
    When I open the ID scanner
    And I accept the captured front
    And I accept the captured back
    Then an ID card document with 2 pages is saved

  Scenario: Retaking the front then accepting still saves a 2-page ID document
    Given the app is launched with a fake ID camera returning a front and a back
    When I open the ID scanner
    And I retake the front
    And I accept the captured front
    And I accept the captured back
    Then an ID card document with 2 pages is saved
```

> Note: for the retake scenario the fake camera must have a spare front shot. The launch step below seeds three shots (front, front, back); the happy-path scenario simply never taps Retake, so the third shot is consumed as the back.

- [ ] **Step 2: Create the new launch step**

`test/step/the_app_is_launched_with_a_fake_id_camera_returning_a_front_and_a_back.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Shared repository instance — set by the Given step; read by the Then step.
FakeDocumentRepository idScanRepo = FakeDocumentRepository();

/// Usage: the app is launched with a fake ID camera returning a front and a back
Future<void> theAppIsLaunchedWithAFakeIdCameraReturningAFrontAndABack(
    WidgetTester tester) async {
  idScanRepo = FakeDocumentRepository();
  app.runCamScannerApp(
    scanDependencies: ScanDependencies(
      createPhotoCamera: () => FakePhotoCamera(const [
        '/nonexistent/id_front.jpg',
        '/nonexistent/id_front_retake.jpg',
        '/nonexistent/id_back.jpg',
      ]),
      createCameraPermission: () => FakeCameraPermission(),
      createEdgeDetector: () => FakeEdgeDetector(),
    ),
    libraryDependencies: fakeLibraryDependencies(idScanRepo),
  );
  await tester.pumpAndSettle();
}
```

- [ ] **Step 3: Create the accept/retake steps**

`test/step/i_accept_the_captured_front.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I accept the captured front
Future<void> iAcceptTheCapturedFront(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}
```

`test/step/i_accept_the_captured_back.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I accept the captured back
Future<void> iAcceptTheCapturedBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}
```

`test/step/i_retake_the_front.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I retake the front
Future<void> iRetakeTheFront(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-retake')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 4: Repoint the assertion step's import**

In `test/step/an_id_card_document_with2_pages_is_saved.dart`, change the import line
```dart
import 'the_app_is_launched_with_a_fake_id_scanner_returning_a_front_and_a_back.dart';
```
to
```dart
import 'the_app_is_launched_with_a_fake_id_camera_returning_a_front_and_a_back.dart';
```
(The body — reading `idScanRepo` — is unchanged.)

- [ ] **Step 5: Delete the stale scanner launch step + regenerate**

```bash
rm test/step/the_app_is_launched_with_a_fake_id_scanner_returning_a_front_and_a_back.dart
dart run build_runner build --delete-conflicting-outputs
```
Expected: `integration_test/id_scan_test.dart` regenerated with both scenarios and imports for the new steps; no leftover reference to the deleted step.

- [ ] **Step 6: Run the ID BDD as a host widget test**

The generated test uses fakes only (no real native), so it runs host-side:

Run: `flutter test integration_test/id_scan_test.dart`
Expected: PASS — both scenarios. (Nonexistent paths: decode fails gracefully, detection → fullFrame, `review-accept` still tappable.)

- [ ] **Step 7: Analyze + commit**

```bash
flutter analyze
dart format lib test integration_test
git add integration_test/id_scan.feature integration_test/id_scan_test.dart test/step/i_accept_the_captured_front.dart test/step/i_accept_the_captured_back.dart test/step/i_retake_the_front.dart test/step/the_app_is_launched_with_a_fake_id_camera_returning_a_front_and_a_back.dart test/step/an_id_card_document_with2_pages_is_saved.dart
git rm test/step/the_app_is_launched_with_a_fake_id_scanner_returning_a_front_and_a_back.dart
git commit -m "test(scan): BDD ID flow drives single-shot camera + Retake/Use steps

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 7: Full host suite + analyze gate

**Files:** none (verification task).

- [ ] **Step 1: Run the entire host suite**

Run: `flutter test`
Expected: PASS. If any pre-existing OpenCV host test fails, confirm it is the known environmental `libdartcv` gap (see CLAUDE.md), not a regression from this change.

- [ ] **Step 2: Analyze + format check**

Run: `flutter analyze && dart format --set-exit-if-changed lib test integration_test`
Expected: analyze clean; formatting already applied (exit 0).

- [ ] **Step 3: Commit any residual formatting only (if needed)**

```bash
git add -p   # stage only formatting hunks in files this plan touched
git commit -m "chore(scan): formatting for single-shot ID capture

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi"
```

---

### Task 8: Device verification — Android AND iOS (mandatory)

**Files:** none (manual on-device verification; this is part of the definition of done per CLAUDE.md).

**Rationale:** the native camera UI cannot be driven by `integration_test` (same limit as `ImagePickerGalleryPicker`), so the seam is proven host-side with fakes and the real flow is proven by hand on both platforms.

- [ ] **Step 1: Build + install Release on a real Android device**

```bash
flutter build apk --release && flutter install -d <android-device-id>
```

- [ ] **Step 2: Android — verify the ID flow**

Fresh-permission check first: on a device where camera was never granted (or after clearing the app's permissions), tap **Scan ID** and confirm the runtime permission prompt appears and, if granted, the camera opens. Then verify:
- Exactly ONE photo is taken for the front (no multi-page "Save" UI).
- The review shows the captured card with the crop overlay (auto-detected corners or full-frame fallback), Retake and **Use** buttons.
- **Use** advances straight to the back; **Retake** re-opens the camera for the same side.
- After accepting the back, a 2-page ID document is saved and marked as ID card (check PDF export layout).
- Denying the permission shows the SnackBar and returns to Home with no partial document.
- In-document **Retake page** (open a saved page → Retake) opens the single-shot camera + crop review and replaces the page.

- [ ] **Step 3: Build + install Release on a real iOS device**

```bash
flutter build ios --release && flutter install -d <ios-device-id>
```
Verify the artifact is Release (multi-MB `App.framework/App`, no `kernel_blob.bin`) per CLAUDE.md before trusting it.

- [ ] **Step 4: iOS — verify the same checklist as Step 2**

Additionally confirm: the OS camera permission prompt appears on first use; the saved ID page is a valid JPEG (not a rejected HEIC). If a HEIC ever fails to save, add `imageQuality: 100` to `ImagePickerPhotoCamera.capture()` to force JPEG re-encode, add a regression note, and re-verify.

- [ ] **Step 5: Record evidence**

In the final report, paste/summarize the exact build+install commands and the observed result per platform (one-shot, preview, auto-crop, 2-page save, permission-denied path, in-document retake). Name any gap explicitly — do not silently downgrade the definition of done.

---

## Self-Review

**Spec coverage:**
- Single-shot camera seam → Task 1. ✅
- Android runtime camera permission (+ denied failure mode) → Task 2 + Task 4 Step 1/3. ✅
- `CaptureReviewScreen` title/acceptLabel/initialMode → Task 3. ✅
- `IdScanScreen` capture→review→auto-advance loop, ID filter default None → Task 4. ✅
- In-document retake → single-shot → Task 5. ✅
- BDD scenarios (accept + retake) → Task 6. ✅
- Format/orientation via existing `ensureJpegBytes` → no task needed (reused, verified in spec). ✅
- HEIC residual → Task 8 Step 4 (device checkpoint + mitigation). ✅
- Both-platform device verification → Task 8. ✅
- Double-preview UX trade-off → accepted (spec); no task. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result.

**Type consistency:** `PhotoCamera.capture()`, `CameraPermission.ensure()`, `ScanDependencies.createPhotoCamera` / `.createCameraPermission`, `CaptureReviewScreen(title/acceptLabel/initialMode)`, `_SideResult`, `_ReviewOutcome`/`_Accepted`/`_Retake` (IdScanScreen), `_RetakeReview`/`_AcceptedPage`/`_RetakeAgain` (ScanScreen — deliberately distinct names to avoid cross-file private clashes), `SaveController.save/addPage`, `DocumentRepository.markAsIdCard`, `onCapture(CapturedImage, CropCorners, ImageEnhancer) → Future<bool>` — all consistent across tasks.
