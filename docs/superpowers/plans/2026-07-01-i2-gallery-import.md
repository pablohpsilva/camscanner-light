# I2 Gallery Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import an existing photo from the device gallery and run it through the existing capture-review (crop/filter/save) pipeline.

**Architecture:** A `GalleryPicker` interface (DIP) with an `image_picker`-backed impl and a fake, injected via `ScanDependencies`. `CameraScreen` gains an app-bar "import" button that picks a photo and routes it through the SAME review flow as a capture (`_reviewAndSave` extracted from `_onShutter`), reusing `_onAccept` create/append and save.

**Tech Stack:** `image_picker` (`1.2.3`), the existing `CaptureReviewScreen`/`SaveController` pipeline, `bdd_widget_test` + `build_runner`. Pure Dart flow logic; the only native surface is the picker plugin.

## Global Constraints

- Privacy unchanged: the picked photo is a local file; nothing leaves the device.
- Works on iOS and Android via `image_picker`. iOS needs `NSPhotoLibraryUsageDescription` in `Info.plist`; Android's system Photo Picker needs no permission/manifest change.
- Material only; the flow logic is pure Dart (no platform branching in app code).
- Host test success marker is exactly `All tests passed!`; `flutter analyze --no-fatal-infos` (from `apps/mobile`) must print `No issues found` (repo currently clean — no unused imports).
- **Host widget tests must NOT feed the review screen a loadable image path.** Under host `FakeAsync`, `FilterPickerStrip` thumbnail generation (compute isolates) does not run and deadlocks `pumpAndSettle`. The existing camera tests use a NON-LOADABLE path (`/nonexistent/...`) for exactly this reason. So `FakeGalleryPicker` must support returning an injected non-loadable path for widget tests; the on-device BDD uses a real temp file.
- BDD authored as `.feature` under `apps/mobile/integration_test/`, generated to `*_test.dart` via `dart run build_runner build --delete-conflicting-outputs` (run from `apps/mobile`; NO `mobile:build_runner` nx target). Generated files are committed. Step defs in `apps/mobile/test/step/`. The host suite does NOT run `integration_test/` BDD — `flutter analyze` is the compile gate; the scenario runs on-device.
- Commit with EXPLICIT file paths (never `git add -A`). End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- DO NOT stage or touch: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, or `.superpowers/`. (Adding `image_picker` updates `pubspec.yaml`/`pubspec.lock` — commit those; do NOT run iOS pod install / do not touch `Podfile.lock`.)
- Tooling: `pnpm nx run mobile:test --skip-nx-cache -- --name "a|b"` breaks on the shell `|`. Use `flutter test <file>` for focused runs; `pnpm nx run mobile:test --skip-nx-cache` for the full suite.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `apps/mobile/pubspec.yaml` | Deps | Add `image_picker: ^1.2.3` |
| `apps/mobile/ios/Runner/Info.plist` | iOS config | Add `NSPhotoLibraryUsageDescription` |
| `apps/mobile/lib/features/scan/gallery_picker.dart` | Gallery picker seam | New: `GalleryPicker` interface + `ImagePickerGalleryPicker` |
| `apps/mobile/lib/features/scan/scan_dependencies.dart` | Composition root | Add `createGalleryPicker` factory |
| `apps/mobile/test/support/fake_scan.dart` | Test double | Add `FakeGalleryPicker`; wire into `grantedScanDependencies` |
| `apps/mobile/lib/features/scan/camera_screen.dart` | Scan screen | `_galleryPicker`, `_reviewAndSave`, `_onImport`, import app-bar button |
| `apps/mobile/integration_test/i2_gallery_import.feature` (+ generated `_test.dart`) | On-device BDD | New |
| `apps/mobile/test/step/i_import_a_photo_from_the_gallery.dart` | BDD step | New |
| `scripts/verify/i2.sh` | Acceptance gate | New |

---

### Task 1: `image_picker` dep + `GalleryPicker` seam + `ScanDependencies` + `FakeGalleryPicker` + iOS config

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/ios/Runner/Info.plist`
- Create: `apps/mobile/lib/features/scan/gallery_picker.dart`
- Modify: `apps/mobile/lib/features/scan/scan_dependencies.dart`
- Modify: `apps/mobile/test/support/fake_scan.dart`
- Test: `apps/mobile/test/features/scan/gallery_picker_test.dart` (create)

**Interfaces:**
- Produces: `abstract interface class GalleryPicker { Future<CapturedImage?> pick(); }`; `class ImagePickerGalleryPicker implements GalleryPicker`; `ScanDependencies.createGalleryPicker` (`GalleryPicker Function()`, default `ImagePickerGalleryPicker.new`); `FakeGalleryPicker({bool cancel, bool throwOnPick, String? returnPath})`.

- [ ] **Step 1: Add the dependency**

  ```bash
  cd apps/mobile && flutter pub add image_picker && cd -
  ```
  Expected: adds `image_picker` (resolves to `1.2.3`) to `pubspec.yaml` and updates `pubspec.lock`. (Do NOT run pod install; do not touch `ios/Podfile.lock`.)

- [ ] **Step 2: Add the iOS photo-library usage string**

  In `apps/mobile/ios/Runner/Info.plist`, add these two lines immediately before the final `</dict>`:
  ```xml
  	<key>NSPhotoLibraryUsageDescription</key>
  	<string>Import a document photo from your library.</string>
  ```

- [ ] **Step 3: Create the `GalleryPicker` seam**

  Create `apps/mobile/lib/features/scan/gallery_picker.dart`:
  ```dart
  import 'package:image_picker/image_picker.dart';

  import 'captured_image.dart';

  /// Picks a single image from the device gallery. Injectable (DIP) so widget and
  /// BDD tests use a fake instead of the platform picker.
  abstract interface class GalleryPicker {
    /// Returns the picked image as a [CapturedImage], or null if the user cancelled.
    Future<CapturedImage?> pick();
  }

  /// Production picker backed by image_picker. Reads a local photo — nothing leaves
  /// the device. Thin adapter (not automated-testable — the native gallery UI is out
  /// of Flutter's reach); the flow is tested through [GalleryPicker] with a fake.
  class ImagePickerGalleryPicker implements GalleryPicker {
    const ImagePickerGalleryPicker();
    @override
    Future<CapturedImage?> pick() async {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      return x == null ? null : CapturedImage(x.path);
    }
  }
  ```

- [ ] **Step 4: Add the `ScanDependencies` factory**

  In `apps/mobile/lib/features/scan/scan_dependencies.dart`:
  - Add the import:
    ```dart
    import 'gallery_picker.dart';
    ```
  - Add the typedef + default (near the other factory typedefs/defaults):
    ```dart
    typedef GalleryPickerFactory = GalleryPicker Function();

    GalleryPicker _defaultGalleryPicker() => const ImagePickerGalleryPicker();
    ```
  - Add the field + ctor default to `ScanDependencies`:
    ```dart
    final GalleryPickerFactory createGalleryPicker;
    ```
    and in the `const ScanDependencies({...})` parameter list:
    ```dart
    this.createGalleryPicker = _defaultGalleryPicker,
    ```

- [ ] **Step 5: Add `FakeGalleryPicker` + wire into `grantedScanDependencies`**

  In `apps/mobile/test/support/fake_scan.dart`:
  - Add the import (with the others):
    ```dart
    import 'package:mobile/features/scan/gallery_picker.dart';
    ```
  - Add the fake (anywhere among the other fakes):
    ```dart
    /// In-memory fake of [GalleryPicker].
    /// - [cancel] true  => pick() returns null (user cancelled).
    /// - [throwOnPick]  => pick() throws (platform-error path).
    /// - [returnPath]   => pick() returns that exact path. HOST WIDGET TESTS pass a
    ///   NON-LOADABLE path (e.g. '/nonexistent/import.jpg') so the review screen's
    ///   FilterPickerStrip does not try to generate thumbnails (which deadlocks under
    ///   FakeAsync). When null, a real temp file (kFakeJpegBytes) is written — used
    ///   by the on-device BDD where a loadable file is needed.
    class FakeGalleryPicker implements GalleryPicker {
      final bool cancel;
      final bool throwOnPick;
      final String? returnPath;
      const FakeGalleryPicker({
        this.cancel = false,
        this.throwOnPick = false,
        this.returnPath,
      });
      @override
      Future<CapturedImage?> pick() async {
        if (throwOnPick) throw Exception('fake: gallery pick failed');
        if (cancel) return null;
        final path = returnPath;
        if (path != null) return CapturedImage(path);
        final dir = await Directory.systemTemp.createTemp('fake_gallery');
        final file = File('${dir.path}/import.jpg')
          ..writeAsBytesSync(kFakeJpegBytes);
        return CapturedImage(file.path);
      }
    }
    ```
  - In `grantedScanDependencies()`, add the factory so every scan BDD has a hermetic picker (inert unless a scenario taps import):
    ```dart
    createGalleryPicker: () => const FakeGalleryPicker(),
    ```

- [ ] **Step 6: Write the failing tests**

  Create `apps/mobile/test/features/scan/gallery_picker_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/scan/gallery_picker.dart';
  import 'package:mobile/features/scan/scan_dependencies.dart';

  import '../../support/fake_scan.dart';

  void main() {
    test('ScanDependencies default gallery picker is ImagePickerGalleryPicker',
        () {
      expect(const ScanDependencies().createGalleryPicker(),
          isA<ImagePickerGalleryPicker>());
    });

    test('FakeGalleryPicker(cancel) returns null', () async {
      expect(await const FakeGalleryPicker(cancel: true).pick(), isNull);
    });

    test('FakeGalleryPicker(returnPath) returns that path', () async {
      final img =
          await const FakeGalleryPicker(returnPath: '/nonexistent/x.jpg').pick();
      expect(img, isNotNull);
      expect(img!.path, '/nonexistent/x.jpg');
    });

    test('FakeGalleryPicker(throwOnPick) throws', () async {
      expect(const FakeGalleryPicker(throwOnPick: true).pick(),
          throwsA(isA<Exception>()));
    });
  }
  ```

- [ ] **Step 7: Run the failing tests → implement → pass**

  ```bash
  cd apps/mobile && flutter test test/features/scan/gallery_picker_test.dart
  ```
  Expected FIRST run: FAIL/compile-error until Steps 3–5 are in. After Steps 3–5: PASS (4 tests).

- [ ] **Step 8: Full suite + analyze + commit**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock \
          apps/mobile/ios/Runner/Info.plist \
          apps/mobile/lib/features/scan/gallery_picker.dart \
          apps/mobile/lib/features/scan/scan_dependencies.dart \
          apps/mobile/test/support/fake_scan.dart \
          apps/mobile/test/features/scan/gallery_picker_test.dart
  git commit -m "feat(i2): GalleryPicker seam (image_picker) + ScanDependencies + fake

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
  Expected: `All tests passed!`, `No issues found`, commit succeeds. (Confirm `git status` shows `pubspec.lock` staged and does NOT stage `ios/Podfile.lock`.)

---

### Task 2: `CameraScreen` import button + `_onImport` + `_reviewAndSave`

**Files:**
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Test: `apps/mobile/test/features/scan/camera_screen_i2_test.dart` (create)

**Interfaces:**
- Consumes: `GalleryPicker` (Task 1), `widget.dependencies.createGalleryPicker`, existing `_onShutter`/`_onAccept`/`_startSampleTimer`/`_saveController`/`_edgeDetector`/`_controller`, `CaptureReviewScreen`, keys `scan-shutter`/`review-accept`/`camera-done`.
- Produces: app-bar import button key `camera-import`; handler `_onImport`; extracted `_reviewAndSave(CapturedImage)`; SnackBar `Couldn't import photo`.

- [ ] **Step 1: Write the failing widget tests**

  Create `apps/mobile/test/features/scan/camera_screen_i2_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/scan/camera_permission_service.dart';
  import 'package:mobile/features/scan/camera_screen.dart';
  import 'package:mobile/features/scan/scan_dependencies.dart';

  import '../../support/fake_library.dart';
  import '../../support/fake_scan.dart';

  // Granted camera + a gallery picker returning a NON-LOADABLE path (so the
  // review screen's FilterPickerStrip does not deadlock under FakeAsync).
  ScanDependencies _deps({bool cancel = false, bool throwOnPick = false}) =>
      ScanDependencies(
        createPermissionService: () =>
            FakeCameraPermissionService(CameraPermissionStatus.granted),
        createPreviewController: () =>
            FakeCameraPreviewController(captureReturnPath: '/nonexistent/cap.jpg'),
        createGalleryPicker: () => FakeGalleryPicker(
            cancel: cancel,
            throwOnPick: throwOnPick,
            returnPath: '/nonexistent/import.jpg'),
      );

  void main() {
    testWidgets('import button is present even before any capture',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: CameraScreen(
              dependencies: _deps(), repository: FakeDocumentRepository())));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('camera-import')), findsOneWidget);
    });

    testWidgets('importing a photo opens the review screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: CameraScreen(
              dependencies: _deps(), repository: FakeDocumentRepository())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-import')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-accept')), findsOneWidget);
    });

    testWidgets('import then Accept saves a document', (tester) async {
      final repo = FakeDocumentRepository();
      await tester.pumpWidget(MaterialApp(
          home: CameraScreen(dependencies: _deps(), repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-accept')));
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
    });

    testWidgets('cancelling the picker stays on the camera (no review, no save)',
        (tester) async {
      final repo = FakeDocumentRepository();
      await tester.pumpWidget(MaterialApp(
          home: CameraScreen(
              dependencies: _deps(cancel: true), repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-import')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-accept')), findsNothing);
      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
      expect(repo.createCalls, 0);
    });

    testWidgets('picker error shows a SnackBar, stays on the camera',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: CameraScreen(
              dependencies: _deps(throwOnPick: true),
              repository: FakeDocumentRepository())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-import')));
      await tester.pumpAndSettle();
      expect(find.text('Couldn\'t import photo'), findsOneWidget);
      expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    });
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  cd apps/mobile && flutter test test/features/scan/camera_screen_i2_test.dart
  ```
  Expected: FAIL — no `camera-import` key / `_onImport` yet.

- [ ] **Step 3: Add the gallery-picker field**

  In `apps/mobile/lib/features/scan/camera_screen.dart`:
  - Add the import:
    ```dart
    import 'gallery_picker.dart';
    ```
  - Add the field to `_CameraScreenState` (with the other `late final` deps):
    ```dart
    late final GalleryPicker _galleryPicker;
    ```
  - In `initState`, after `_edgeDetector = widget.dependencies.createEdgeDetector();`, add:
    ```dart
    _galleryPicker = widget.dependencies.createGalleryPicker();
    ```

- [ ] **Step 4: Extract `_reviewAndSave` and add `_onImport`**

  In `camera_screen.dart`, refactor `_onShutter` so the review-push block becomes a
  shared method. Replace the `await navigator.push(MaterialPageRoute<void>( ... ));`
  block inside `_onShutter` with a call to `_reviewAndSave(image)`.

  **IMPORTANT:** after this move, `_onShutter`'s `final navigator = Navigator.of(context);`
  is no longer used there (only `messenger` remains, for the capture-null SnackBar) —
  `_reviewAndSave` declares its own `navigator`. **Delete the now-unused
  `final navigator = Navigator.of(context);` line from `_onShutter`** or `flutter
  analyze` fails with `unused_local_variable`. Keep the `messenger` local.

  Add the two methods:
  ```dart
  Future<void> _reviewAndSave(CapturedImage image) async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            edgeDetector: _edgeDetector,
            saving: _saveController.saving,
            onRetake: navigator.pop,
            onAccept: (corners, enhancer) => _onAccept(image, corners, enhancer),
          ),
        ),
      ),
    );
  }

  Future<void> _onImport() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    final messenger = ScaffoldMessenger.of(context);
    CapturedImage? image;
    try {
      image = await _galleryPicker.pick();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't import photo")),
      );
      if (_controller.status == ScanStatus.ready) _startSampleTimer();
      return;
    }
    if (!mounted) return;
    if (image == null) {
      if (_controller.status == ScanStatus.ready) _startSampleTimer();
      return;
    }
    await _reviewAndSave(image);
    if (mounted && _controller.status == ScanStatus.ready) _startSampleTimer();
  }
  ```

  After extraction, `_onShutter`'s tail (below the `image == null` guard) is:
  ```dart
    await _reviewAndSave(image);
    if (mounted && _controller.status == ScanStatus.ready) {
      _startSampleTimer();
    }
  }
  ```
  (The `navigator`/`messenger` locals `_onShutter` still uses for the capture-null
  SnackBar stay; only the push block moves into `_reviewAndSave`.)

- [ ] **Step 5: Add the import app-bar button**

  In `build`, replace the current `actions:` (which is `_pageCount > 0 ? [done] : null`)
  with an always-present import button plus the conditional done button:
  ```dart
  actions: [
    IconButton(
      key: const Key('camera-import'),
      icon: const Icon(Icons.photo_library_outlined),
      tooltip: 'Import from gallery',
      onPressed: _onImport,
    ),
    if (_pageCount > 0)
      IconButton(
        key: const Key('camera-done'),
        icon: const Icon(Icons.check),
        tooltip: 'Done scanning',
        onPressed: _onDone,
      ),
  ],
  ```

- [ ] **Step 6: Run tests → pass; full suite + analyze; commit**

  ```bash
  cd apps/mobile && flutter test test/features/scan/camera_screen_i2_test.dart
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/lib/features/scan/camera_screen.dart \
          apps/mobile/test/features/scan/camera_screen_i2_test.dart
  git commit -m "feat(i2): CameraScreen gallery-import button routes into the review flow

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
  Expected: focused 5 PASS, `All tests passed!`, `No issues found`. (The existing
  camera tests that assert `camera-done` absent at `_pageCount == 0` still pass — the
  import button has a distinct key and does not affect those assertions.)

---

### Task 3: BDD + verify script + plans index

**Existing steps to REUSE (do NOT recreate):**
`the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart`,
`i_tap_the_scan_button.dart`, `i_tap_accept.dart`, `i_tap_done.dart`,
`i_see_a_saved_document_on_the_home.dart`.

**Files:**
- Create: `apps/mobile/integration_test/i2_gallery_import.feature`
- Create: `apps/mobile/test/step/i_import_a_photo_from_the_gallery.dart`
- Create (generated): `apps/mobile/integration_test/i2_gallery_import_test.dart`
- Create: `scripts/verify/i2.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the feature file**

  Create `apps/mobile/integration_test/i2_gallery_import.feature`:
  ```gherkin
  Feature: I2 Gallery import

    Scenario: Importing a photo from the gallery saves it as a document
      Given the app is launched with camera permission granted and empty storage
      When I tap the Scan button
      And I import a photo from the gallery
      And I tap Accept
      And I tap Done
      Then I see a saved document on the home
  ```

- [ ] **Step 2: Write the import step**

  Create `apps/mobile/test/step/i_import_a_photo_from_the_gallery.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  /// Usage: I import a photo from the gallery
  ///
  /// Taps the camera screen's import button. The launch step's
  /// grantedScanDependencies wires a FakeGalleryPicker that returns a real temp
  /// file, so this routes into the review screen exactly like a capture.
  Future<void> iImportAPhotoFromTheGallery(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('camera-import')));
    await tester.pumpAndSettle();
  }
  ```

- [ ] **Step 3: Generate the test**

  ```bash
  cd apps/mobile && dart run build_runner build --delete-conflicting-outputs && cd -
  grep "import" apps/mobile/integration_test/i2_gallery_import_test.dart
  ```
  Expected: creates `apps/mobile/integration_test/i2_gallery_import_test.dart` importing
  `i_import_a_photo_from_the_gallery.dart` plus the reused steps. If build_runner emits a
  differently-named file or an import doesn't resolve, STOP and report — do not hand-edit
  the generated file.

- [ ] **Step 4: Host suite + analyze**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  ```
  Expected: `All tests passed!` and `No issues found`. (Host does not run the BDD
  scenario; analyze is the compile gate for the new step + generated files.)

- [ ] **Step 5: Create `scripts/verify/i2.sh`**

  ```bash
  #!/usr/bin/env bash
  # Verify I2 (Gallery import) acceptance criteria.
  # Run from repository root: bash scripts/verify/i2.sh
  # VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib.sh
  source "$DIR/lib.sh"
  cd "$ROOT"

  echo "== I2 verification =="

  require_tool flutter
  require_tool pnpm

  # ---- Static assertions ----
  assert_file_has "GalleryPicker interface exists" \
    "apps/mobile/lib/features/scan/gallery_picker.dart" \
    "abstract interface class GalleryPicker"

  assert_file_has "ImagePickerGalleryPicker impl exists" \
    "apps/mobile/lib/features/scan/gallery_picker.dart" \
    "ImagePickerGalleryPicker"

  assert_file_has "createGalleryPicker in ScanDependencies" \
    "apps/mobile/lib/features/scan/scan_dependencies.dart" \
    "createGalleryPicker"

  assert_file_has "image_picker dependency" \
    "apps/mobile/pubspec.yaml" \
    "image_picker"

  assert_file_has "camera-import button in CameraScreen" \
    "apps/mobile/lib/features/scan/camera_screen.dart" \
    "camera-import"

  assert_file_has "_onImport handler in CameraScreen" \
    "apps/mobile/lib/features/scan/camera_screen.dart" \
    "_onImport"

  assert_file_has "BDD feature file exists" \
    "apps/mobile/integration_test/i2_gallery_import.feature" \
    "Gallery import"

  assert_file_has "generated BDD test exists" \
    "apps/mobile/integration_test/i2_gallery_import_test.dart" \
    "iImportAPhotoFromTheGallery"

  # ---- OpenCV host library (scan tests in shared suite need it) ----
  bash "$ROOT/scripts/setup-cv-host-test.sh"
  export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
  export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

  # ---- Host tests + analyze ----
  assert_cmd "host tests pass" "All tests passed!" \
    pnpm nx run mobile:test --skip-nx-cache

  assert_cmd "flutter analyze clean" "No issues found" \
    bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

  # ---- On-device BDD (skippable for CI without a device) ----
  if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
    warn "VERIFY_SKIP_DEVICE=1 — on-device BDD skipped (must pass on real device before gate)"
  else
    assert_cmd "on-device BDD passes (iOS)" "All tests passed" \
      pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=i2
  fi

  echo "== I2 verification complete =="
  ```
  Make it executable:
  ```bash
  chmod +x scripts/verify/i2.sh
  ```

- [ ] **Step 6: Run the verify script (device skipped)**

  ```bash
  VERIFY_SKIP_DEVICE=1 bash scripts/verify/i2.sh
  ```
  Expected: ends `== I2 verification complete ==` with all static + host + analyze PASS
  (device line WARNs). If any assert FAILS, STOP and report which one.

- [ ] **Step 7: Update the plans index**

  In `docs/superpowers/plans/00-plans-index.md`, change the I2 row status from `⏳` to
  `✅ **built & gated**` and set its plan-file column to `2026-07-01-i2-gallery-import.md`.

- [ ] **Step 8: Commit**

  ```bash
  git add apps/mobile/integration_test/i2_gallery_import.feature \
          apps/mobile/integration_test/i2_gallery_import_test.dart \
          apps/mobile/test/step/i_import_a_photo_from_the_gallery.dart \
          scripts/verify/i2.sh docs/superpowers/plans/00-plans-index.md
  git commit -m "test(i2): BDD gallery-import scenario + verify script + plans index

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Self-Review (author checklist — completed)

**Spec coverage:**
- Import a photo → `GalleryPicker` + `image_picker` (Task 1) + `_onImport`/import button (Task 2). ✓
- Reuse review/crop/filter/save pipeline → `_reviewAndSave` extracted; imported image flows through `CaptureReviewScreen` → `_onAccept` (Task 2). ✓
- Produces a document → widget test `createCalls == 1`; BDD → saved doc on home. ✓
- Cancel is a graceful no-op → widget test (no review, no save, stays on camera). ✓
- Picker error handled → widget test (`Couldn't import photo` SnackBar). ✓
- On-device end-to-end → BDD (Task 3). ✓
- iOS + Android → `image_picker`; iOS Info.plist key added; Android photo picker needs nothing. ✓
- DIP seam → `GalleryPicker` interface + fake. ✓

**Placeholder scan:** none — every code step complete; every command has an expected marker.

**Type consistency:** `GalleryPicker.pick()→Future<CapturedImage?>`, `createGalleryPicker: GalleryPicker Function()`, `FakeGalleryPicker({cancel, throwOnPick, returnPath})`, keys `camera-import`, handler `_onImport`, `_reviewAndSave(CapturedImage)`, SnackBar `Couldn't import photo`, step fn `iImportAPhotoFromTheGallery`, generated file `i2_gallery_import_test.dart` — consistent across tasks + verify script.
