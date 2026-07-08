# Platform Document Scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom OpenCV camera + live/still detection with the OS document scanners (Android ML Kit, iOS VisionKit) via `cunning_document_scanner`, keeping the app's filter/OCR/PDF/library pipeline.

**Architecture:** Add an injectable `DocumentScannerService` seam to `ScanDependencies`. A thin `ScanScreen` replaces `CameraScreen`: it launches the native scanner, shows ONE filter review for the batch, and saves every returned (already-cropped) page through the existing `SaveController`/repository. `CaptureReviewScreen` gains a crop-less "filter-only" mode. Gallery import and the still `detect()` path stay. Live-camera + auto-capture code is deleted.

**Tech Stack:** Flutter, `cunning_document_scanner` (ML Kit + VisionKit), Drift, `bdd_widget_test`, existing `image_enhancer`/OCR/PDF.

## Global Constraints

- Run all Flutter commands from `apps/mobile/`.
- TDD: failing test first, watch it fail, minimal code to pass. BDD `.feature` for user-facing behavior.
- `flutter analyze` must report **zero** issues on touched files.
- Do NOT run blanket `dart format lib test` — the local formatter drifts against the repo style and churns unrelated lines. Match surrounding style by hand; format only files you fully rewrote, and review the diff.
- Native scanner UI is not host-testable → the native flow is a **required, named device-verification gap** (real Android AND real iOS) before "done". Never silently skip it.
- Image bytes live on disk; DB stores relative paths only. Never persist absolute paths. (Unchanged here — save pipeline untouched.)
- Host widget tests that reach `CaptureReviewScreen` MUST use **non-loadable** image paths (e.g. `/nonexistent/scan_1.jpg`) so `FilterPickerStrip` doesn't try to generate thumbnails (deadlocks under FakeAsync). Pattern: see `test/support/fake_scan.dart` `FakeGalleryPicker` docstring.
- Plugin facts (verify after `pub get` against the installed version): `CunningDocumentScanner.getPictures({bool asPdf, ScannerSource scannerSource, int noOfPages, ...})` returns `List<String>?` of image paths (null/empty on cancel). iOS deployment target ≥13 (repo is 15.5 ✓), `NSCameraUsageDescription` present ✓. Android minSdk ≥21 ✓ (ML Kit OCR already requires it). Plugin manages camera permission itself.

---

### Task 1: Add the `cunning_document_scanner` dependency

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (dependencies section, near `image_picker`)

- [ ] **Step 1: Add the dependency**

In `apps/mobile/pubspec.yaml`, under `dependencies:` add (keep alphabetical-ish grouping near the other scan deps):

```yaml
  cunning_document_scanner: ^2.5.0
```

- [ ] **Step 2: Resolve and verify the API**

Run: `cd apps/mobile && flutter pub get`
Expected: resolves without version conflicts.

Then open the installed plugin to confirm the exact `getPictures` signature and the `ScannerSource` enum name used in Task 2:
Run: `find ~/.pub-cache -path '*cunning_document_scanner*/lib/cunning_document_scanner.dart' | head -1 | xargs sed -n '1,60p'`
Expected: shows `static Future<List<String>?> getPictures({... int noOfPages ..., ScannerSource scannerSource ...})`. Note the real parameter names for Task 2.

- [ ] **Step 3: Commit**

```bash
cd apps/mobile && git add pubspec.yaml pubspec.lock
git commit -m "build: add cunning_document_scanner dependency"
```

---

### Task 2: `DocumentScannerService` interface + wrapper impl

**Files:**
- Create: `apps/mobile/lib/features/scan/document_scanner_service.dart`
- Create: `apps/mobile/lib/features/scan/cunning_document_scanner_service.dart`
- Test: `apps/mobile/test/features/scan/cunning_document_scanner_service_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class DocumentScannerService { Future<List<CapturedImage>> scan({int? pageLimit}); }`
  - `class CunningDocumentScannerService implements DocumentScannerService` with a test seam:
    `typedef ScannerLauncher = Future<List<String>?> Function({int? noOfPages});`
    and constructor `const CunningDocumentScannerService({ScannerLauncher launch = _pluginLaunch})`.

- [ ] **Step 1: Write the interface**

Create `apps/mobile/lib/features/scan/document_scanner_service.dart`:

```dart
import 'captured_image.dart';

/// Launches the platform document scanner (Android ML Kit / iOS VisionKit) and
/// returns the captured, already-cropped page images.
abstract interface class DocumentScannerService {
  /// Returns the scanned page images in order, or an empty list if the user
  /// cancelled or scanning failed. NEVER throws.
  ///
  /// [pageLimit] caps the number of pages (honoured on Android; iOS VisionKit
  /// is inherently multi-page and ignores it). Null means "no practical cap".
  Future<List<CapturedImage>> scan({int? pageLimit});
}
```

- [ ] **Step 2: Write the failing test (normalization via injected launcher)**

Create `apps/mobile/test/features/scan/cunning_document_scanner_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/cunning_document_scanner_service.dart';

void main() {
  test('maps returned paths to CapturedImage in order', () async {
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async => ['/a.jpg', '/b.jpg'],
    );
    final pages = await service.scan();
    expect(pages.map((p) => p.path).toList(), ['/a.jpg', '/b.jpg']);
  });

  test('null result (cancel) → empty list', () async {
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async => null,
    );
    expect(await service.scan(), isEmpty);
  });

  test('launcher throwing → empty list (never throws)', () async {
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async => throw Exception('boom'),
    );
    expect(await service.scan(), isEmpty);
  });

  test('pageLimit is forwarded as noOfPages', () async {
    int? seen;
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async {
        seen = noOfPages;
        return const <String>[];
      },
    );
    await service.scan(pageLimit: 1);
    expect(seen, 1);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/cunning_document_scanner_service_test.dart`
Expected: FAIL — `cunning_document_scanner_service.dart` does not exist / `CunningDocumentScannerService` undefined.

- [ ] **Step 4: Write the impl**

Create `apps/mobile/lib/features/scan/cunning_document_scanner_service.dart`. Adjust the `getPictures` call in `_pluginLaunch` to the exact param names confirmed in Task 1 Step 2:

```dart
import 'package:cunning_document_scanner/cunning_document_scanner.dart';

import 'captured_image.dart';
import 'document_scanner_service.dart';

/// Injectable launcher seam so normalization is testable without the plugin.
typedef ScannerLauncher = Future<List<String>?> Function({int? noOfPages});

/// Default launcher: the real plugin call. `noOfPages` null → a high cap
/// (effectively "no practical limit"); camera source only (gallery import
/// stays on the existing image_picker path).
Future<List<String>?> _pluginLaunch({int? noOfPages}) =>
    CunningDocumentScanner.getPictures(
      noOfPages: noOfPages ?? 100,
      scannerSource: ScannerSource.camera,
    );

class CunningDocumentScannerService implements DocumentScannerService {
  final ScannerLauncher _launch;
  const CunningDocumentScannerService({ScannerLauncher launch = _pluginLaunch})
      : _launch = launch;

  @override
  Future<List<CapturedImage>> scan({int? pageLimit}) async {
    try {
      final paths = await _launch(noOfPages: pageLimit);
      if (paths == null) return const [];
      return paths.map(CapturedImage.new).toList();
    } catch (_) {
      return const [];
    }
  }
}
```

- [ ] **Step 5: Run tests + analyze**

Run: `cd apps/mobile && flutter test test/features/scan/cunning_document_scanner_service_test.dart && flutter analyze lib/features/scan/document_scanner_service.dart lib/features/scan/cunning_document_scanner_service.dart test/features/scan/cunning_document_scanner_service_test.dart`
Expected: all tests PASS; "No issues found!".

- [ ] **Step 6: Commit**

```bash
cd apps/mobile && git add lib/features/scan/document_scanner_service.dart lib/features/scan/cunning_document_scanner_service.dart test/features/scan/cunning_document_scanner_service_test.dart
git commit -m "feat(scan): DocumentScannerService seam + cunning wrapper"
```

---

### Task 2b: Add `FakeDocumentScannerService` to test support

**Files:**
- Modify: `apps/mobile/test/support/fake_scan.dart` (append at end)

**Interfaces:**
- Produces: `class FakeDocumentScannerService implements DocumentScannerService { FakeDocumentScannerService(this.pages); final List<CapturedImage> pages; int? lastPageLimit; int scanCalls; }`

- [ ] **Step 1: Append the fake**

At the end of `apps/mobile/test/support/fake_scan.dart`, add (and add the import `import 'package:mobile/features/scan/document_scanner_service.dart';` to the import block at the top):

```dart
/// In-memory fake of [DocumentScannerService]. Returns [pages] (use NON-LOADABLE
/// paths in host widget tests so FilterPickerStrip does not generate thumbnails).
/// An empty [pages] simulates a cancelled scan.
class FakeDocumentScannerService implements DocumentScannerService {
  final List<CapturedImage> pages;
  int scanCalls = 0;
  int? lastPageLimit;
  FakeDocumentScannerService(this.pages);

  @override
  Future<List<CapturedImage>> scan({int? pageLimit}) async {
    scanCalls++;
    lastPageLimit = pageLimit;
    return pages;
  }
}
```

- [ ] **Step 2: Analyze (no dedicated test — exercised by Task 4/5)**

Run: `cd apps/mobile && flutter analyze test/support/fake_scan.dart`
Expected: "No issues found!" (it will show the unused-import warning ONLY if nothing references it yet — if so, proceed; Task 3 wires `createDocumentScanner` and Task 4 uses the fake. If analyze flags an unused import, defer the commit to Task 3.)

- [ ] **Step 3: Commit**

```bash
cd apps/mobile && git add test/support/fake_scan.dart
git commit -m "test(scan): FakeDocumentScannerService"
```

---

### Task 3: Wire `createDocumentScanner` into `ScanDependencies`

**Files:**
- Modify: `apps/mobile/lib/features/scan/scan_dependencies.dart`
- Test: `apps/mobile/test/features/scan/scan_dependencies_test.dart`

**Interfaces:**
- Produces: `ScanDependencies.createDocumentScanner` (`DocumentScannerServiceFactory`, default `CunningDocumentScannerService`).
- Note: `createPermissionService` and `createPreviewController` are removed in Task 8 (kept now so the existing `CameraScreen` still compiles until the switch).

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile/test/features/scan/scan_dependencies_test.dart` a test asserting the default:

```dart
test('createDocumentScanner defaults to CunningDocumentScannerService', () {
  const deps = ScanDependencies();
  expect(deps.createDocumentScanner(), isA<CunningDocumentScannerService>());
});
```

Add the import: `import 'package:mobile/features/scan/cunning_document_scanner_service.dart';`

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/scan_dependencies_test.dart`
Expected: FAIL — `createDocumentScanner` undefined.

- [ ] **Step 3: Add the factory**

In `apps/mobile/lib/features/scan/scan_dependencies.dart`:
- Add imports: `import 'cunning_document_scanner_service.dart';` and `import 'document_scanner_service.dart';`
- Add typedef + default + field + constructor param:

```dart
typedef DocumentScannerServiceFactory = DocumentScannerService Function();

DocumentScannerService _defaultDocumentScanner() =>
    const CunningDocumentScannerService();
```

Inside `class ScanDependencies` add the field `final DocumentScannerServiceFactory createDocumentScanner;` and in the const constructor add `this.createDocumentScanner = _defaultDocumentScanner,`.

- [ ] **Step 4: Run tests + analyze**

Run: `cd apps/mobile && flutter test test/features/scan/scan_dependencies_test.dart && flutter analyze lib/features/scan/scan_dependencies.dart`
Expected: PASS; "No issues found!".

- [ ] **Step 5: Commit**

```bash
cd apps/mobile && git add lib/features/scan/scan_dependencies.dart test/features/scan/scan_dependencies_test.dart test/support/fake_scan.dart
git commit -m "feat(scan): wire createDocumentScanner into ScanDependencies"
```

---

### Task 4: `CaptureReviewScreen` filter-only mode (`enableCrop`)

**Files:**
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart`
- Test: `apps/mobile/test/features/scan/capture_review_filter_only_test.dart`

**Interfaces:**
- Produces: `CaptureReviewScreen({... bool enableCrop = true})`. When `false`: no detection, no `CropOverlay`, no Reset button; `onAccept` returns `CropCorners.fullFrame` + the chosen enhancer.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/scan/capture_review_filter_only_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('filter-only mode hides crop overlay and Reset', (tester) async {
    await tester.pumpWidget(_host(CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/scan_1.jpg'),
      enableCrop: false,
      onRetake: () {},
      onAccept: (_, __) {},
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CropOverlay), findsNothing);
    expect(find.byKey(const Key('crop-reset')), findsNothing);
    expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget);
  });

  testWidgets('filter-only accept returns full-frame corners + enhancer',
      (tester) async {
    CropCorners? corners;
    ImageEnhancer? enhancer;
    await tester.pumpWidget(_host(CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/scan_1.jpg'),
      enableCrop: false,
      onRetake: () {},
      onAccept: (c, e) {
        corners = c;
        enhancer = e;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump();

    expect(corners, CropCorners.fullFrame);
    expect(enhancer, isA<AutoEnhancer>()); // default mode is auto
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_filter_only_test.dart`
Expected: FAIL — `enableCrop` is not a parameter.

- [ ] **Step 3: Implement `enableCrop`**

In `apps/mobile/lib/features/scan/capture_review_screen.dart`:

Add the field + constructor param (near the other fields, around line 45):

```dart
  final bool enableCrop; // NEW: false = filter-only (already-cropped scanner page)
```
```dart
    this.enableCrop = true, // in the const constructor
```

Guard detection in `_runDetection()` (top of the method body, after `final detector = ...`):

```dart
    if (!widget.enableCrop) return;
```

In `build`, replace the crop-vs-plain rendering. Change:

```dart
                    child: size == null
                        ? Center(child: _imageWidget())
                        : CropOverlay( ... ),
```
to:
```dart
                    child: (!widget.enableCrop || size == null)
                        ? Center(child: _imageWidget())
                        : CropOverlay(
                            imageSize: size,
                            image: _imageWidget(),
                            corners: _corners,
                            enabled: !widget.saving,
                            highlightColor: _highlightColor,
                            onCornersChanged: (c) => setState(() {
                              _userInteracted = true;
                              _corners = c;
                            }),
                          ),
```

Hide the Reset button in filter-only mode. Wrap the existing `TextButton(key: Key('crop-reset'), ...)` so it only appears when cropping:

```dart
              if (widget.enableCrop)
                TextButton(
                  key: const Key('crop-reset'),
                  onPressed: canCrop
                      ? () => setState(() {
                            _userInteracted = true;
                            _corners = CropCorners.fullFrame;
                          })
                      : null,
                  child: const Text('Reset'),
                ),
```

(`_corners` stays `CropCorners.fullFrame` in filter-only mode since detection is skipped, so `onAccept(_corners, ...)` already returns full frame — no change to the Accept handler.)

- [ ] **Step 4: Run tests + analyze**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_filter_only_test.dart && flutter analyze lib/features/scan/capture_review_screen.dart`
Expected: PASS; "No issues found!".

- [ ] **Step 5: Run the existing review tests (no regression)**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_test.dart test/features/scan/capture_review_highlight_test.dart test/features/scan/capture_review_screen_g4_test.dart`
Expected: PASS (default `enableCrop: true` preserves current behavior).

- [ ] **Step 6: Commit**

```bash
cd apps/mobile && git add lib/features/scan/capture_review_screen.dart test/features/scan/capture_review_filter_only_test.dart
git commit -m "feat(scan): filter-only mode for CaptureReviewScreen"
```

---

### Task 5: `ScanScreen` — batch scan → one filter → save all

**Files:**
- Create: `apps/mobile/lib/features/scan/scan_screen.dart`
- Test: `apps/mobile/test/features/scan/scan_screen_test.dart`

**Interfaces:**
- Consumes: `DocumentScannerService` (via `ScanDependencies.createDocumentScanner`), `SaveController`, `CaptureReviewScreen(enableCrop:false)`, `FakeDocumentScannerService`, `FakeDocumentRepository`.
- Produces: `class ScanScreen extends StatefulWidget` with `ScanScreen({ScanDependencies dependencies, required DocumentRepository repository, Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)? onCapture})` — SAME shape as the old `CameraScreen` so Task 7 callers change only the type name.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/scan/scan_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

// Push ScanScreen from a host so its final pop() has somewhere to return to.
Widget _host(ScanScreen screen) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => screen),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

ScanDependencies _deps(List<String> paths) => ScanDependencies(
      createDocumentScanner: () =>
          FakeDocumentScannerService(paths.map(CapturedImage.new).toList()),
    );

void main() {
  testWidgets('cancelled scan (empty) pops without saving', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(_host(
        ScanScreen(dependencies: _deps(const []), repository: repo)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsNothing); // popped back to host
    expect(repo.createCalls, 0);
  });

  testWidgets('multi-page: one filter review, first creates doc, rest append',
      (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(_host(ScanScreen(
      dependencies: _deps(const [
        '/nonexistent/scan_1.jpg',
        '/nonexistent/scan_2.jpg',
        '/nonexistent/scan_3.jpg',
      ]),
      repository: repo,
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // scanner returns → review pushed

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle(); // save all → pop

    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 2);
    expect(repo.lastSavedCorners, CropCorners.fullFrame);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/scan/scan_screen_test.dart`
Expected: FAIL — `scan_screen.dart` / `ScanScreen` does not exist.

- [ ] **Step 3: Implement `ScanScreen`**

Create `apps/mobile/lib/features/scan/scan_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'document_scanner_service.dart';
import 'scan_dependencies.dart';

/// Launches the OS document scanner, applies one filter to the whole batch,
/// and saves every (already-cropped) page. Replaces the custom camera screen.
/// When [onCapture] is non-null the screen is in single-page retake mode.
class ScanScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;
  final Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)?
      onCapture;

  const ScanScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
    this.onCapture,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final DocumentScannerService _scanner;
  late final SaveController _saveController;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _scanner = widget.dependencies.createDocumentScanner();
    _saveController = SaveController(repository: widget.repository);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final navigator = Navigator.of(context);
    final retake = widget.onCapture != null;
    final pages = await _scanner.scan(pageLimit: retake ? 1 : null);
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
    if (retake) {
      await widget.onCapture!(pages.first, CropCorners.fullFrame, enhancer);
      if (mounted) navigator.pop();
      return;
    }
    await _saveAll(pages, enhancer);
    if (mounted) navigator.pop();
  }

  /// Shows one filter-only review on [image]; returns the chosen enhancer, or
  /// null if the user cancelled (Retake).
  Future<ImageEnhancer?> _pickFilter(CapturedImage image) async {
    ImageEnhancer? chosen;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            enableCrop: false,
            saving: _saveController.saving,
            onRetake: () => Navigator.of(context).pop(),
            onAccept: (_, enhancer) {
              chosen = enhancer;
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
    return chosen;
  }

  Future<void> _saveAll(
      List<CapturedImage> pages, ImageEnhancer enhancer) async {
    final messenger = ScaffoldMessenger.of(context);
    final doc = await _saveController.save(pages.first,
        corners: CropCorners.fullFrame, enhancer: enhancer);
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save document. Try again.")),
      );
      return;
    }
    setState(() => _pageCount = 1);
    for (var i = 1; i < pages.length; i++) {
      final pos = await _saveController.addPage(pages[i], doc.id,
          corners: CropCorners.fullFrame, enhancer: enhancer);
      if (!mounted) return;
      if (pos != null) setState(() => _pageCount = pos);
    }
  }

  @override
  void dispose() {
    _saveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _pageCount == 0
            ? const Text('Scan')
            : Text('$_pageCount page${_pageCount == 1 ? '' : 's'} saved'),
      ),
      body: const Center(
        key: Key('scan-opening'),
        child: CircularProgressIndicator(),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `cd apps/mobile && flutter test test/features/scan/scan_screen_test.dart && flutter analyze lib/features/scan/scan_screen.dart test/features/scan/scan_screen_test.dart`
Expected: both tests PASS; "No issues found!".

- [ ] **Step 5: Commit**

```bash
cd apps/mobile && git add lib/features/scan/scan_screen.dart test/features/scan/scan_screen_test.dart
git commit -m "feat(scan): ScanScreen batch flow (scan → filter → save all)"
```

---

### Task 6: `ScanScreen` retake mode (single page → onCapture)

**Files:**
- Modify: `apps/mobile/test/features/scan/scan_screen_test.dart` (add a test)

**Interfaces:**
- Consumes: the `onCapture` param already implemented in Task 5.

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile/test/features/scan/scan_screen_test.dart` (inside `main`):

```dart
  testWidgets('retake mode: single page → onCapture with enhancer, pageLimit 1',
      (tester) async {
    final repo = FakeDocumentRepository();
    final fakeScanner =
        FakeDocumentScannerService([const CapturedImage('/nonexistent/re.jpg')]);
    CapturedImage? captured;
    await tester.pumpWidget(_host(ScanScreen(
      dependencies: ScanDependencies(createDocumentScanner: () => fakeScanner),
      repository: repo,
      onCapture: (image, corners, enhancer) async {
        captured = image;
        return true;
      },
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(captured?.path, '/nonexistent/re.jpg');
    expect(fakeScanner.lastPageLimit, 1);
    expect(repo.createCalls, 0); // retake replaces, does not create
  });
```

- [ ] **Step 2: Run to verify it fails, then passes**

Run: `cd apps/mobile && flutter test test/features/scan/scan_screen_test.dart`
Expected: The new test PASSES immediately (retake logic already implemented in Task 5). If it fails, fix `ScanScreen._run` retake branch. This task exists to lock the retake contract with a test.

- [ ] **Step 3: Commit**

```bash
cd apps/mobile && git add test/features/scan/scan_screen_test.dart
git commit -m "test(scan): lock ScanScreen retake contract"
```

---

### Task 7: Switch callers (home + viewer) to `ScanScreen`

**Files:**
- Modify: `apps/mobile/lib/features/library/home_screen.dart` (`_openScan`, ~line 121-131; and the `CameraScreen` import)
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart` (`_retakePage`, ~line 314-338; and the `CameraScreen` import)
- Test: run existing home + viewer tests

- [ ] **Step 1: Update home `_openScan`**

In `apps/mobile/lib/features/library/home_screen.dart`, replace the `CameraScreen(...)` in `_openScan` with `ScanScreen(...)` (identical args), and update the import from `../scan/camera_screen.dart` to `../scan/scan_screen.dart`:

```dart
        builder: (_) =>
            ScanScreen(dependencies: widget.dependencies, repository: repo),
```

- [ ] **Step 2: Update viewer `_retakePage`**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`, replace `CameraScreen(...)` in `_retakePage` with `ScanScreen(...)` (identical args incl. the `onCapture` callback) and update the import to `../scan/scan_screen.dart`.

- [ ] **Step 3: Run to verify (analyze first)**

Run: `cd apps/mobile && flutter analyze lib/features/library/home_screen.dart lib/features/library/page_viewer_screen.dart`
Expected: "No issues found!" (both `CameraScreen` references gone).

- [ ] **Step 4: Run home + viewer host tests**

Run: `cd apps/mobile && flutter test test/features/library/`
Expected: PASS. If a home/viewer test injected camera fakes expecting `CameraScreen`/live preview, update it to inject `createDocumentScanner: () => FakeDocumentScannerService([...])` and expect `ScanScreen`. Fix each failure by swapping the widget type and scanner fake; do not change unrelated assertions.

- [ ] **Step 5: Commit**

```bash
cd apps/mobile && git add lib/features/library/home_screen.dart lib/features/library/page_viewer_screen.dart test/features/library/
git commit -m "feat(scan): launch ScanScreen from home and viewer retake"
```

---

### Task 8: Delete the live-camera + auto-capture code and its tests

**Files (delete):**
- `apps/mobile/lib/features/scan/camera_screen.dart`
- `apps/mobile/lib/features/scan/scan_controller.dart`
- `apps/mobile/lib/features/scan/camera_preview_controller.dart`
- `apps/mobile/lib/features/scan/camera_preview_controller_impl.dart`
- `apps/mobile/lib/features/scan/camera_permission_service.dart`
- `apps/mobile/lib/features/scan/camera_permission_service_impl.dart`
- `apps/mobile/lib/features/scan/widgets/camera_preview_view.dart`
- `apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart`
- `apps/mobile/lib/features/scan/auto_capture_controller.dart`
- `apps/mobile/lib/features/scan/frame_reducer.dart`
- `apps/mobile/lib/features/scan/gray_frame.dart`
- `apps/mobile/lib/features/scan/camera_frame.dart`
- `apps/mobile/lib/features/scan/scan_flash_mode.dart` (only used by the preview/camera screen — verify with grep before deleting)
- `apps/mobile/lib/features/scan/scan_view_state.dart` (verify with grep — delete only if unused after camera_screen is gone)

**Files (delete tests):** all under `apps/mobile/test/features/scan/` that reference the deleted units, e.g. `camera_screen*_test.dart`, `scan_controller*_test.dart`, `camera_preview_controller_f3_test.dart`, `camera_screen_auto_capture_test.dart`, `auto_capture_controller_test.dart`, `frame_reducer_test.dart`, `gray_frame_test.dart`, `camera_frame_test.dart`, `widgets/camera_preview_view_f3_test.dart`, `widgets/camera_preview_view_auto_capture_test.dart`, `widgets/live_quad_overlay_test.dart`, `opencv_edge_detector_detectframe_test.dart`, `opencv_edge_detector_yuv_test.dart`.
**Files (delete integration/feature):** `integration_test/a2_scan_permission*`, `integration_test/f3_live_overlay*`, `integration_test/f3_shadow_detection_test.dart` (live), and any `.feature` + generated `_test.dart` for live overlay / auto-capture / permission.

**Files (modify):**
- `apps/mobile/lib/features/scan/edge_detector.dart` — remove `detectFrame` from the interface and the `CameraFrame` import.
- `apps/mobile/lib/features/scan/opencv_edge_detector.dart` — remove `detectFrame`, `_segmentGrayFrame`, and imports of `camera_frame`/`frame_reducer`/`gray_frame`. Keep `detect()` and the still pipeline.
- `apps/mobile/lib/features/scan/scan_dependencies.dart` — remove `createPermissionService`, `createPreviewController`, their typedefs/defaults, and the now-dangling imports.
- `apps/mobile/test/support/fake_scan.dart` — remove `FakeCameraPermissionService`, `FakeCameraPreviewController`, `grantedScanDependencies`, `deniedScanDependencies`, `unavailableScanDependencies`, `liveDetectionScanDependencies`, `liveDetectionFakePreview`, `grantedScanDependenciesWithDetector`, and `FakeEdgeDetector.detectFrame` (drop the `detectFrame` override + `camera_frame` import; keep `detect`). Keep `FakeGalleryPicker`, `FakeEdgeDetector` (still), `FakeDocumentScannerService`, `kFakeJpegBytes`.

- [ ] **Step 1: Trim the EdgeDetector interface (TDD-adjacent: compile-drives)**

Edit `apps/mobile/lib/features/scan/edge_detector.dart`: delete the `detectFrame` method from `abstract interface class EdgeDetector` and remove `import 'camera_frame.dart';`.

Edit `apps/mobile/lib/features/scan/opencv_edge_detector.dart`: delete the `@override Future<DetectionResult?> detectFrame(...)` method, the top-level `_segmentGrayFrame`, `_kLiveDetectMaxSide`, and the imports `camera_frame.dart`, `frame_reducer.dart`, `gray_frame.dart`. Keep `detect`, `_runPipeline`, `_runPipelineOnMat`, `_segmentGray`.

- [ ] **Step 2: Delete the files**

```bash
cd apps/mobile && git rm \
  lib/features/scan/camera_screen.dart \
  lib/features/scan/scan_controller.dart \
  lib/features/scan/camera_preview_controller.dart \
  lib/features/scan/camera_preview_controller_impl.dart \
  lib/features/scan/camera_permission_service.dart \
  lib/features/scan/camera_permission_service_impl.dart \
  lib/features/scan/widgets/camera_preview_view.dart \
  lib/features/scan/widgets/live_quad_overlay.dart \
  lib/features/scan/auto_capture_controller.dart \
  lib/features/scan/frame_reducer.dart \
  lib/features/scan/gray_frame.dart \
  lib/features/scan/camera_frame.dart
```

Then, gated on grep (delete only if the grep prints nothing):
```bash
grep -rl scan_flash_mode lib/ | grep -v scan_flash_mode.dart   # if empty → git rm lib/features/scan/scan_flash_mode.dart
grep -rl scan_view_state lib/ | grep -v scan_view_state.dart   # if empty → git rm lib/features/scan/scan_view_state.dart
```

- [ ] **Step 3: Remove the DI factories + fix fake_scan**

Apply the `scan_dependencies.dart` and `fake_scan.dart` edits listed in **Files (modify)** above.

- [ ] **Step 4: Delete the dead tests**

Remove every scan test that imports a deleted unit:
```bash
cd apps/mobile
# find them first:
grep -rl -E "camera_screen|scan_controller|camera_preview_controller|camera_permission|live_quad|camera_preview_view|auto_capture|frame_reducer|gray_frame|camera_frame|detectFrame" test/features/scan/ integration_test/
# git rm each file the grep lists (host + integration + matching .feature + generated _test.dart)
```
Delete each listed file with `git rm`. For BDD pairs, remove BOTH the `.feature` and its generated `*_test.dart`.

- [ ] **Step 5: Analyze the whole app + run the scan/library suites**

Run: `cd apps/mobile && flutter analyze 2>&1 | tail -5`
Expected: "No issues found!" (fix any dangling import/reference the deletions exposed).

Run: `cd apps/mobile && flutter test test/features/scan/ test/features/library/ 2>&1 | tail -5`
Expected: all pass EXCEPT the known-environmental `opencv_edge_detector_test.dart` failures (native libdartcv not loaded on host — `detect()` returns null; documented in CLAUDE.md). No other failures.

- [ ] **Step 6: Commit**

```bash
cd apps/mobile && git add -A lib/features/scan test/features/scan integration_test test/support/fake_scan.dart lib/features/library
git commit -m "refactor(scan): remove live camera + auto-capture; keep still detect() for gallery"
```
(Scope the `git add` to these paths — do NOT `git add -A` from repo root; the working tree may carry unrelated WIP.)

---

### Task 9: Remove unused native dependencies (grep-gated)

**Files:**
- Modify: `apps/mobile/pubspec.yaml`

- [ ] **Step 1: Confirm nothing else uses them**

Run:
```bash
cd apps/mobile && echo "camera:" && grep -rl "package:camera/" lib/ test/ || echo NONE
echo "permission_handler:" && grep -rl "package:permission_handler" lib/ test/ || echo NONE
```
Expected: both print `NONE`. If either lists a file, KEEP that dependency and note why in the commit.

- [ ] **Step 2: Remove the confirmed-unused deps**

In `apps/mobile/pubspec.yaml` delete the `camera:` line, and `permission_handler:` if Step 1 showed NONE.

Run: `cd apps/mobile && flutter pub get`
Expected: resolves cleanly.

- [ ] **Step 3: Analyze + full host suite**

Run: `cd apps/mobile && flutter analyze 2>&1 | tail -3 && flutter test 2>&1 | tail -8`
Expected: "No issues found!"; suite green except the documented environmental `opencv_edge_detector_test.dart` failures.

- [ ] **Step 4: Commit**

```bash
cd apps/mobile && git add pubspec.yaml pubspec.lock
git commit -m "build: drop unused camera + permission_handler deps"
```

---

### Task 10: BDD `.feature` for the new scan flow

**Files:**
- Create: `apps/mobile/integration_test/scan_platform.feature`
- Create/Modify: step definitions under `apps/mobile/test/step/` (reuse existing steps where possible)
- Generated: `apps/mobile/integration_test/scan_platform_test.dart` (via build_runner)

- [ ] **Step 1: Write the feature**

Create `apps/mobile/integration_test/scan_platform.feature`:

```gherkin
Feature: Platform document scanner

  Scenario: Scanning pages saves a document with the chosen filter
    Given the app is launched with a fake scanner returning 2 pages
    When I open the scanner
    And I accept the review
    Then a document with 2 pages is saved

  Scenario: Cancelling the scanner returns to the library
    Given the app is launched with a fake scanner returning 0 pages
    When I open the scanner
    Then no document is saved
```

- [ ] **Step 2: Regenerate + implement steps**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: generates `integration_test/scan_platform_test.dart` and stub step files under `test/step/`.

Implement the generated step stubs using `FakeDocumentScannerService` + `FakeDocumentRepository` (mirror `scan_screen_test.dart`). Each step must pump the app / drive `ScanScreen` and assert on `FakeDocumentRepository.createCalls` / `addPageCalls`. (Remember the BDD-seed rule: a step that seeds state must be followed by a step that launches the UI reading that state — see memory `bdd-seed-needs-app-launch-step`.)

- [ ] **Step 3: Run the widget-mode BDD + analyze**

Run: `cd apps/mobile && flutter test integration_test/scan_platform_test.dart && flutter analyze integration_test/scan_platform_test.dart`
Expected: PASS; "No issues found!".

- [ ] **Step 4: Commit**

```bash
cd apps/mobile && git add integration_test/scan_platform.feature integration_test/scan_platform_test.dart test/step/
git commit -m "test(scan): BDD feature for platform scanner flow"
```

---

### Task 11: Device verification (real Android AND real iOS) — REQUIRED

This closes the named native gap. The plugin's scanner UI, real capture, crop, and multi-page cannot be host-tested.

- [ ] **Step 1: Build + install Release on a real Android device**

Run: `cd apps/mobile && flutter build apk --release && flutter install -d <android-device-id>`
(Build first — `flutter install` never compiles; see CLAUDE.md.)

- [ ] **Step 2: Manually verify on Android**

Scan a real page on a light desk: confirm (a) the OS scanner opens, (b) auto-detect + crop hug the page, (c) multi-page works, (d) cancel returns to the library, (e) the filter review then saves, (f) the saved page appears in the library with OCR text. Record the result.

- [ ] **Step 3: Build + install Release on a real iOS device**

Run: `cd apps/mobile && flutter build ios --release && flutter install -d <ios-device-id>`
Verify `build/ios/iphoneos/Runner.app/Frameworks/App.framework/App` is multi-MB (Release), not a ~34KB Debug stub (CLAUDE.md).

- [ ] **Step 4: Manually verify on iOS**

Repeat Step 2's checks with VisionKit. Confirm the same-day white-paper-on-light-desk case that motivated this change now detects tightly. Record the result.

- [ ] **Step 5: Document results**

Append a short "Device verification" note (device models, OS versions, pass/fail per check) to the design spec `docs/superpowers/specs/2026-07-07-platform-document-scanner-design.md`, and commit:

```bash
cd /path/to/repo && git add docs/superpowers/specs/2026-07-07-platform-document-scanner-design.md
git commit -m "docs: record device verification for platform scanner"
```

---

## Self-Review Notes

- **Spec coverage:** service seam (T2), DI (T3), filter-only review (T4), ScanScreen batch one-filter-per-batch (T5), retake single page (T6), caller switch (T7), removals incl. detectFrame + deps (T8/T9), gallery import untouched (no task modifies it — kept by construction), platform config (already satisfied; T1 verifies), host tests (T2/T4/T5/T6), BDD (T10), device verification named + required (T11). Covered.
- **Cancel semantics:** wrapper normalizes null/empty/throw → `[]` (T2), and `ScanScreen` pops on empty (T5).
- **One filter per batch:** T5 shows a single review on `pages.first` and applies its enhancer to every save.
- **Type consistency:** `DocumentScannerService.scan({int? pageLimit})`, `CunningDocumentScannerService({ScannerLauncher launch})`, `ScanDependencies.createDocumentScanner`, `CaptureReviewScreen(enableCrop:)`, `ScanScreen({dependencies, repository, onCapture})` — used consistently across tasks.
</content>
