# Build-Time Feature Flags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate every user-facing capability of the app behind a build-time environment variable, all defaulting on except `fax`, with a disabled feature's control hidden entirely.

**Architecture:** A single injectable `FeatureFlags` value object (one `bool` per capability, each defaulting from `const bool.fromEnvironment('FEATURE_X', …)`) is threaded through `LibraryDependencies.features` — mirroring how `FeedbackConfig` rides `FeedbackDependencies`. Screens (`HomeScreen`, `PageViewerScreen`) and the `EditorToolbar` widget read the flags and conditionally *build* each control, so an off flag removes the widget rather than greying it. Tests inject a `FeatureFlags` override; production reads the compile-time env.

**Tech Stack:** Flutter, Dart `bool.fromEnvironment` (compile-time constants via `--dart-define` / `--dart-define-from-file`), `flutter_test` widget tests, `bdd_widget_test` for BDD.

## Global Constraints

- Env var names are exactly `FEATURE_<SCREAMING_SNAKE>` per the flag table below (e.g. `FEATURE_PROTECT_WITH_PASSWORD`).
- Every flag defaults `true` **except `FEATURE_FAX`, which defaults `false`**.
- Disabled ⇒ control **hidden entirely** (the widget is not built) — never greyed/disabled.
- `FeatureFlags` is **injectable**: const default reads `bool.fromEnvironment`, overridable in tests. It is NEVER referenced as a bare global/static const inside a widget (that would be untestable, since `fromEnvironment` is a compile-time constant).
- Thread the flags through `LibraryDependencies.features`; do NOT add a new top-level parameter to `runCamScannerApp`.
- The Share toolbar button is shown iff `share == true` AND at least one of its seven sub-flags is true (never open an empty share sheet).
- The overflow (⋯) menu button is hidden entirely when all four of its items (rename/merge/split/deleteDocument) are off.
- All Flutter commands run from `apps/mobile/`.
- TDD: write the failing test first, watch it fail, then implement. Commit per task.
- Nothing is "done" until host TDD + BDD are green AND the BDD scenario runs green on a real Android device AND a real iOS device.

### Flag table (field ⇒ env var ⇒ default ⇒ gated control key)

| Field (Dart) | Env var | Default | Control key |
| --- | --- | --- | --- |
| `crop` | `FEATURE_CROP` | true | `page-viewer-edit` |
| `rotate` | `FEATURE_ROTATE` | true | `page-viewer-rotate` |
| `filter` | `FEATURE_FILTER` | true | `page-viewer-filter` |
| `viewText` | `FEATURE_VIEW_TEXT` | true | `page-viewer-view-text` |
| `retake` | `FEATURE_RETAKE` | true | `page-viewer-retake` |
| `share` | `FEATURE_SHARE` | true | `page-viewer-share` (umbrella) |
| `deletePage` | `FEATURE_DELETE_PAGE` | true | `page-viewer-delete-page` |
| `rename` | `FEATURE_RENAME` | true | `page-viewer-rename` |
| `merge` | `FEATURE_MERGE` | true | `page-viewer-merge` |
| `split` | `FEATURE_SPLIT` | true | `page-viewer-split` |
| `deleteDocument` | `FEATURE_DELETE_DOCUMENT` | true | `page-viewer-delete` |
| `exportPdf` | `FEATURE_EXPORT_PDF` | true | `page-viewer-export` |
| `shareImage` | `FEATURE_SHARE_IMAGE` | true | `page-viewer-export-image` |
| `exportAllImages` | `FEATURE_EXPORT_ALL_IMAGES` | true | `page-viewer-export-all-images` |
| `print` | `FEATURE_PRINT` | true | `page-viewer-print` |
| `protectWithPassword` | `FEATURE_PROTECT_WITH_PASSWORD` | true | `page-viewer-protect` |
| `shareLink` | `FEATURE_SHARE_LINK` | true | `page-viewer-share-link` |
| `fax` | `FEATURE_FAX` | **false** | `page-viewer-fax` |
| `idCard` | `FEATURE_ID_CARD` | true | `home-scan-id` |
| `scan` | `FEATURE_SCAN` | true | `home-scan` |
| `import` | `FEATURE_IMPORT` | true | `home-import` |

Note: `print` and `import` are valid Dart field/parameter names (verified with `dart analyze`), despite `import` being a built-in identifier.

## File Structure

- **Create** `lib/features/library/feature_flags.dart` — the `FeatureFlags` value object. One responsibility: hold the 21 build-time booleans.
- **Modify** `lib/features/library/library_dependencies.dart` — add `final FeatureFlags features` (default `const FeatureFlags()`).
- **Modify** `lib/features/library/widgets/editor_toolbar.dart` — add seven `show*` booleans (default `true`); build only the enabled buttons.
- **Modify** `lib/features/library/page_viewer_screen.dart` — add `final FeatureFlags features` constructor field; gate toolbar buttons, Share-button visibility, share-sheet tiles, and overflow-menu items.
- **Modify** `lib/features/library/home_screen.dart` — gate the scan / id-card / import buttons; pass `features` into `PageViewerScreen`.
- **Modify** `test/support/fake_library.dart` — let `fakeLibraryDependencies` and `persistentLibraryDependencies` accept a `FeatureFlags` override.
- **Create** test files per task (listed below).
- **Create** `integration_test/f1_feature_flags.feature` + steps in `test/step/` + regenerated `integration_test/f1_feature_flags_test.dart`.

---

### Task 1: `FeatureFlags` value object + thread through `LibraryDependencies`

**Files:**
- Create: `lib/features/library/feature_flags.dart`
- Modify: `lib/features/library/library_dependencies.dart:28-43`
- Test: `test/features/library/feature_flags_test.dart`

**Interfaces:**
- Produces: `class FeatureFlags` with const constructor and 21 `bool` fields named exactly as the flag table's "Field" column. Also `LibraryDependencies.features` (type `FeatureFlags`, default `const FeatureFlags()`).

- [ ] **Step 1: Write the failing test**

Create `test/features/library/feature_flags_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/library_dependencies.dart';

void main() {
  test('defaults: every feature on except fax', () {
    const f = FeatureFlags();
    expect(f.fax, isFalse, reason: 'fax is the only default-off flag');
    final onByDefault = <bool>[
      f.crop, f.rotate, f.filter, f.viewText, f.retake, f.share, f.deletePage,
      f.rename, f.merge, f.split, f.deleteDocument, f.exportPdf, f.shareImage,
      f.exportAllImages, f.print, f.protectWithPassword, f.shareLink,
      f.idCard, f.scan, f.import,
    ];
    expect(onByDefault, everyElement(isTrue));
  });

  test('an override changes only that flag', () {
    const f = FeatureFlags(print: false);
    expect(f.print, isFalse);
    expect(f.crop, isTrue);
    expect(f.fax, isFalse);
  });

  test('LibraryDependencies exposes default FeatureFlags', () {
    const deps = LibraryDependencies();
    expect(deps.features.fax, isFalse);
    expect(deps.features.crop, isTrue);
  });

  test('LibraryDependencies accepts a FeatureFlags override', () {
    const deps = LibraryDependencies(features: FeatureFlags(scan: false));
    expect(deps.features.scan, isFalse);
    expect(deps.features.import, isTrue);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/library/feature_flags_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '…/feature_flags.dart'` / `FeatureFlags` undefined.

- [ ] **Step 3: Create the `FeatureFlags` class**

Create `lib/features/library/feature_flags.dart`:

```dart
/// Build-time feature flags. Each capability of the app is gated by one
/// `bool`, defaulted from `const bool.fromEnvironment('FEATURE_X', …)` so a
/// build can strip any feature with `--dart-define=FEATURE_X=false` (or a JSON
/// via `--dart-define-from-file`, the same channel the donation config uses).
///
/// Every flag defaults ON except [fax], which defaults OFF (no fax provider is
/// wired yet). A disabled flag HIDES its control entirely — see PageViewerScreen
/// / HomeScreen / EditorToolbar for the gating.
///
/// This object is INJECTABLE (threaded through LibraryDependencies.features):
/// widgets read it from their dependencies, never as a bare global const —
/// `bool.fromEnvironment` is a compile-time constant, so a global could not be
/// varied in a widget test.
class FeatureFlags {
  final bool crop;
  final bool rotate;
  final bool filter;
  final bool viewText;
  final bool retake;
  final bool share;
  final bool deletePage;
  final bool rename;
  final bool merge;
  final bool split;
  final bool deleteDocument;
  final bool exportPdf;
  final bool shareImage;
  final bool exportAllImages;
  final bool print;
  final bool protectWithPassword;
  final bool shareLink;
  final bool fax;
  final bool idCard;
  final bool scan;
  final bool import;

  const FeatureFlags({
    this.crop = const bool.fromEnvironment('FEATURE_CROP', defaultValue: true),
    this.rotate =
        const bool.fromEnvironment('FEATURE_ROTATE', defaultValue: true),
    this.filter =
        const bool.fromEnvironment('FEATURE_FILTER', defaultValue: true),
    this.viewText =
        const bool.fromEnvironment('FEATURE_VIEW_TEXT', defaultValue: true),
    this.retake =
        const bool.fromEnvironment('FEATURE_RETAKE', defaultValue: true),
    this.share =
        const bool.fromEnvironment('FEATURE_SHARE', defaultValue: true),
    this.deletePage =
        const bool.fromEnvironment('FEATURE_DELETE_PAGE', defaultValue: true),
    this.rename =
        const bool.fromEnvironment('FEATURE_RENAME', defaultValue: true),
    this.merge =
        const bool.fromEnvironment('FEATURE_MERGE', defaultValue: true),
    this.split =
        const bool.fromEnvironment('FEATURE_SPLIT', defaultValue: true),
    this.deleteDocument = const bool.fromEnvironment(
      'FEATURE_DELETE_DOCUMENT',
      defaultValue: true,
    ),
    this.exportPdf =
        const bool.fromEnvironment('FEATURE_EXPORT_PDF', defaultValue: true),
    this.shareImage =
        const bool.fromEnvironment('FEATURE_SHARE_IMAGE', defaultValue: true),
    this.exportAllImages = const bool.fromEnvironment(
      'FEATURE_EXPORT_ALL_IMAGES',
      defaultValue: true,
    ),
    this.print =
        const bool.fromEnvironment('FEATURE_PRINT', defaultValue: true),
    this.protectWithPassword = const bool.fromEnvironment(
      'FEATURE_PROTECT_WITH_PASSWORD',
      defaultValue: true,
    ),
    this.shareLink =
        const bool.fromEnvironment('FEATURE_SHARE_LINK', defaultValue: true),
    this.fax =
        const bool.fromEnvironment('FEATURE_FAX', defaultValue: false),
    this.idCard =
        const bool.fromEnvironment('FEATURE_ID_CARD', defaultValue: true),
    this.scan =
        const bool.fromEnvironment('FEATURE_SCAN', defaultValue: true),
    this.import =
        const bool.fromEnvironment('FEATURE_IMPORT', defaultValue: true),
  });
}
```

- [ ] **Step 4: Add `features` to `LibraryDependencies`**

In `lib/features/library/library_dependencies.dart`, add the import near the other feature imports (after line 21's `link_share_channel.dart`):

```dart
import 'feature_flags.dart';
```

Then add the field and default to the class (currently lines 28-43):

```dart
class LibraryDependencies {
  final DocumentRepositoryFactory createRepository;
  final DocumentPrinter printer;
  final ShareChannel share;
  final FileArchiver archiver;
  final LinkShareChannel linkShare;
  final FaxProvider fax;
  final FeatureFlags features;
  const LibraryDependencies({
    this.createRepository = _defaultCreateRepository,
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
    this.archiver = const SystemFileArchiver(),
    this.linkShare = const UnavailableLinkShareChannel(),
    this.fax = const UnavailableFaxProvider(),
    this.features = const FeatureFlags(),
  });
}
```

- [ ] **Step 5: Run tests and analyze**

Run: `flutter test test/features/library/feature_flags_test.dart`
Expected: PASS (4 tests).
Run: `flutter analyze lib/features/library/feature_flags.dart lib/features/library/library_dependencies.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/feature_flags.dart lib/features/library/library_dependencies.dart test/features/library/feature_flags_test.dart
git commit -m "feat(library): build-time FeatureFlags value object + LibraryDependencies wiring"
```

---

### Task 2: `EditorToolbar` per-action visibility

**Files:**
- Modify: `lib/features/library/widgets/editor_toolbar.dart:9-103`
- Test: `test/features/library/editor_toolbar_visibility_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 (pure widget; stays decoupled from `FeatureFlags`).
- Produces: `EditorToolbar` gains seven bool params — `showCrop`, `showRotate`, `showFilter`, `showText`, `showRetake`, `showShare`, `showDelete` — each defaulting `true`. When a `show*` is false, that button is not built and the row reflows.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/editor_toolbar_visibility_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/editor_toolbar.dart';
import 'package:mobile/theme/ream_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required Widget toolbar}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.dark(),
        home: Scaffold(bottomNavigationBar: toolbar),
      ),
    );
    await tester.pumpAndSettle();
  }

  EditorToolbar build({
    bool showCrop = true,
    bool showShare = true,
  }) => EditorToolbar(
    onCrop: () {},
    onRotate: () {},
    onText: () {},
    onRetake: () {},
    onShare: () {},
    onDelete: () {},
    onFilter: () {},
    showCrop: showCrop,
    showShare: showShare,
  );

  testWidgets('shows all seven buttons by default', (tester) async {
    await pump(tester, toolbar: build());
    for (final key in const [
      'page-viewer-edit',
      'page-viewer-rotate',
      'page-viewer-filter',
      'page-viewer-view-text',
      'page-viewer-retake',
      'page-viewer-share',
      'page-viewer-delete-page',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('hides the crop button when showCrop is false', (tester) async {
    await pump(tester, toolbar: build(showCrop: false));
    expect(find.byKey(const Key('page-viewer-edit')), findsNothing);
    // others remain
    expect(find.byKey(const Key('page-viewer-rotate')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-share')), findsOneWidget);
  });

  testWidgets('hides the share button when showShare is false', (tester) async {
    await pump(tester, toolbar: build(showShare: false));
    expect(find.byKey(const Key('page-viewer-share')), findsNothing);
    expect(find.byKey(const Key('page-viewer-edit')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/library/editor_toolbar_visibility_test.dart`
Expected: FAIL — `No named parameter with the name 'showCrop'`.

- [ ] **Step 3: Add the `show*` params and conditional build**

Replace the fields/constructor (lines 10-27) with:

```dart
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onText;
  final VoidCallback? onRetake;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onFilter;
  final bool showCrop;
  final bool showRotate;
  final bool showFilter;
  final bool showText;
  final bool showRetake;
  final bool showShare;
  final bool showDelete;

  const EditorToolbar({
    super.key,
    required this.onCrop,
    required this.onRotate,
    required this.onText,
    required this.onRetake,
    required this.onShare,
    required this.onDelete,
    required this.onFilter,
    this.showCrop = true,
    this.showRotate = true,
    this.showFilter = true,
    this.showText = true,
    this.showRetake = true,
    this.showShare = true,
    this.showDelete = true,
  });
```

Replace the `build` method body's `Row(children: [...])` (lines 39-98) so the buttons are built conditionally:

```dart
  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final buttons = <Widget>[
      if (showCrop)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-edit'),
            icon: Icons.crop,
            label: 'Crop',
            onPressed: onCrop,
          ),
        ),
      if (showRotate)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-rotate'),
            icon: Icons.rotate_right,
            label: 'Rotate',
            onPressed: onRotate,
          ),
        ),
      if (showFilter)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-filter'),
            icon: Icons.tune,
            label: 'Filter',
            onPressed: onFilter,
          ),
        ),
      if (showText)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-view-text'),
            icon: Icons.text_snippet_outlined,
            label: 'Text',
            onPressed: onText,
          ),
        ),
      if (showRetake)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-retake'),
            icon: Icons.replay,
            label: 'Retake',
            onPressed: onRetake,
          ),
        ),
      if (showShare)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-share'),
            icon: Icons.ios_share,
            label: 'Share',
            onPressed: onShare,
          ),
        ),
      if (showDelete)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-delete-page'),
            icon: Icons.delete_outline,
            label: 'Delete',
            danger: true,
            onPressed: onDelete,
          ),
        ),
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: r.paper,
          border: Border(top: BorderSide(color: r.line)),
        ),
        child: Row(children: buttons),
      ),
    );
  }
```

Also update the class doc comment (lines 5-8) to note that a `show*` of false omits the button entirely (in addition to a null callback disabling it).

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/library/editor_toolbar_visibility_test.dart`
Expected: PASS (3 tests).
Run: `flutter test test/features/library/editor_toolbar_test.dart`
Expected: PASS (pre-existing toolbar tests still green — the new params default true, so behavior is unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/widgets/editor_toolbar.dart test/features/library/editor_toolbar_visibility_test.dart
git commit -m "feat(library): EditorToolbar hides buttons whose show* flag is false"
```

---

### Task 3: `PageViewerScreen` — thread `FeatureFlags`, gate toolbar + Share-button visibility

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart:14-16` (imports), `:40-55` (constructor), `:548-549` (add getter near it), `:703-719` (toolbar call)
- Test: `test/features/library/page_viewer_toolbar_flags_test.dart`

**Interfaces:**
- Consumes: `FeatureFlags` (Task 1), `EditorToolbar`'s `show*` params (Task 2).
- Produces: `PageViewerScreen` gains `final FeatureFlags features` (default `const FeatureFlags()`) and a private getter `bool get _showShareButton`. Later tasks (4, 5) read `widget.features` in the same file; Task 6 passes `features:` into the constructor.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/page_viewer_toolbar_flags_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    required FeatureFlags features,
  }) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(
          documentId: 1,
          name: 'Scan X',
          repository: repo,
          features: features,
        ),
      ),
    );
    // Non-loadable image path does not hang.
    await tester.pumpAndSettle();
  }

  testWidgets('all toolbar buttons present with default flags', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags());
    for (final key in const [
      'page-viewer-edit',
      'page-viewer-rotate',
      'page-viewer-filter',
      'page-viewer-view-text',
      'page-viewer-retake',
      'page-viewer-share',
      'page-viewer-delete-page',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('crop off hides the crop button', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags(crop: false));
    expect(find.byKey(const Key('page-viewer-edit')), findsNothing);
    expect(find.byKey(const Key('page-viewer-rotate')), findsOneWidget);
  });

  testWidgets('share umbrella off hides the Share button', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags(share: false));
    expect(find.byKey(const Key('page-viewer-share')), findsNothing);
  });

  testWidgets('share on but every sub-action off hides the Share button', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(
        exportPdf: false,
        shareImage: false,
        exportAllImages: false,
        print: false,
        protectWithPassword: false,
        shareLink: false,
        // fax already defaults false
      ),
    );
    expect(find.byKey(const Key('page-viewer-share')), findsNothing);
  });

  testWidgets('share stays visible when at least one sub-action is on', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(
        exportPdf: true,
        shareImage: false,
        exportAllImages: false,
        print: false,
        protectWithPassword: false,
        shareLink: false,
      ),
    );
    expect(find.byKey(const Key('page-viewer-share')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/library/page_viewer_toolbar_flags_test.dart`
Expected: FAIL — `No named parameter with the name 'features'`.

- [ ] **Step 3: Add the import**

In `lib/features/library/page_viewer_screen.dart`, add near the other library imports (after line 16's `enhancer_mode.dart`):

```dart
import 'feature_flags.dart';
```

- [ ] **Step 4: Add the constructor field**

Replace the constructor (lines 40-55) so it carries `features`:

```dart
class PageViewerScreen extends StatefulWidget {
  final int documentId;
  final String name;
  final DocumentRepository repository;
  final ScanDependencies dependencies;
  final DocumentPrinter printer;
  final ShareChannel share;
  final FeatureFlags features;
  const PageViewerScreen({
    super.key,
    required this.documentId,
    required this.name,
    required this.repository,
    this.dependencies = const ScanDependencies(),
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
    this.features = const FeatureFlags(),
  });
```

- [ ] **Step 5: Add the `_showShareButton` getter**

Immediately after the `_actionsDisabled` getter (ends line 549), add:

```dart

  /// The Share toolbar button appears only when the umbrella `share` flag is on
  /// AND at least one share sub-action is enabled — so an empty share sheet can
  /// never be opened.
  bool get _showShareButton =>
      widget.features.share &&
      (widget.features.exportPdf ||
          widget.features.shareImage ||
          widget.features.exportAllImages ||
          widget.features.print ||
          widget.features.protectWithPassword ||
          widget.features.shareLink ||
          widget.features.fax);
```

- [ ] **Step 6: Pass `show*` into the toolbar**

Replace the `EditorToolbar(...)` call (lines 703-719) with:

```dart
          bottomNavigationBar: EditorToolbar(
            showCrop: widget.features.crop,
            showRotate: widget.features.rotate,
            showFilter: widget.features.filter,
            showText: widget.features.viewText,
            showRetake: widget.features.retake,
            showShare: _showShareButton,
            showDelete: widget.features.deletePage,
            onCrop: _actionsDisabled
                ? null
                : () => _editCrop(_pages![_current]),
            onRotate: _actionsDisabled ? null : () => unawaited(_rotatePage()),
            onText: _actionsDisabled ? null : _viewText,
            onRetake: _actionsDisabled ? null : () => unawaited(_retakePage()),
            onShare: _actionsDisabled
                ? null
                : () => unawaited(_openShareMenu()),
            onDelete: _actionsDisabled
                ? null
                : () => unawaited(_confirmAndDeletePage()),
            onFilter: _actionsDisabled
                ? null
                : () => unawaited(_editFilter(_pages![_current])),
          ),
```

- [ ] **Step 7: Run tests**

Run: `flutter test test/features/library/page_viewer_toolbar_flags_test.dart`
Expected: PASS (5 tests).
Run: `flutter test test/features/library/`
Expected: PASS — existing page-viewer tests unaffected (default flags keep every button visible).

- [ ] **Step 8: Commit**

```bash
git add lib/features/library/page_viewer_screen.dart test/features/library/page_viewer_toolbar_flags_test.dart
git commit -m "feat(library): PageViewerScreen gates toolbar + Share-button on FeatureFlags"
```

---

### Task 4: `PageViewerScreen` — gate the share bottom-sheet tiles

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart:591-644` (`_openShareMenu` sheet children)
- Test: `test/features/library/page_viewer_share_sheet_flags_test.dart`

**Interfaces:**
- Consumes: `widget.features` (Task 3).
- Produces: within the share sheet, each `ListTile` is built only when its flag is on.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/page_viewer_share_sheet_flags_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> openShareSheet(
    WidgetTester tester, {
    required FeatureFlags features,
  }) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(
          documentId: 1,
          name: 'Scan X',
          repository: repo,
          features: features,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
  }

  testWidgets('all share tiles present by default (fax too, if fax on)', (
    tester,
  ) async {
    await openShareSheet(tester, features: const FeatureFlags(fax: true));
    for (final key in const [
      'page-viewer-export',
      'page-viewer-export-image',
      'page-viewer-export-all-images',
      'page-viewer-print',
      'page-viewer-protect',
      'page-viewer-share-link',
      'page-viewer-fax',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('fax defaults off — no fax tile', (tester) async {
    await openShareSheet(tester, features: const FeatureFlags());
    expect(find.byKey(const Key('page-viewer-fax')), findsNothing);
    expect(find.byKey(const Key('page-viewer-export')), findsOneWidget);
  });

  testWidgets('print off — no print tile, others remain', (tester) async {
    await openShareSheet(tester, features: const FeatureFlags(print: false));
    expect(find.byKey(const Key('page-viewer-print')), findsNothing);
    expect(find.byKey(const Key('page-viewer-export')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-protect')), findsOneWidget);
  });

  testWidgets('protect off — no protect tile', (tester) async {
    await openShareSheet(
      tester,
      features: const FeatureFlags(protectWithPassword: false),
    );
    expect(find.byKey(const Key('page-viewer-protect')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/library/page_viewer_share_sheet_flags_test.dart`
Expected: FAIL — the `fax defaults off` and `print off` cases fail because every tile is still built unconditionally.

- [ ] **Step 3: Gate each tile**

In `_openShareMenu`, replace the `children: [ ... ]` list (lines 598-641) so every tile is guarded by its flag:

```dart
          children: [
            if (widget.features.exportPdf)
              ListTile(
                key: const Key('page-viewer-export'),
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Export PDF'),
                onTap: () => Navigator.of(ctx).pop('export-pdf'),
              ),
            if (widget.features.shareImage)
              ListTile(
                key: const Key('page-viewer-export-image'),
                leading: const Icon(Icons.image_outlined),
                title: const Text('Share as image'),
                onTap: () => Navigator.of(ctx).pop('export-image'),
              ),
            if (widget.features.exportAllImages)
              ListTile(
                key: const Key('page-viewer-export-all-images'),
                leading: const Icon(Icons.collections_outlined),
                title: const Text('Share all as images'),
                onTap: () => Navigator.of(ctx).pop('export-all-images'),
              ),
            if (widget.features.print)
              ListTile(
                key: const Key('page-viewer-print'),
                leading: const Icon(Icons.print_outlined),
                title: const Text('Print'),
                onTap: () => Navigator.of(ctx).pop('print'),
              ),
            if (widget.features.protectWithPassword)
              ListTile(
                key: const Key('page-viewer-protect'),
                leading: const Icon(Icons.lock_outline),
                title: const Text('Protect with password'),
                onTap: () => Navigator.of(ctx).pop('protect'),
              ),
            if (widget.features.shareLink)
              ListTile(
                key: const Key('page-viewer-share-link'),
                leading: const Icon(Icons.link),
                title: const Text('Share link'),
                onTap: () => Navigator.of(ctx).pop(kShareLinkValue),
              ),
            if (widget.features.fax)
              ListTile(
                key: const Key('page-viewer-fax'),
                leading: const Icon(Icons.print),
                title: const Text('Fax'),
                onTap: () => Navigator.of(ctx).pop(kFaxValue),
              ),
          ],
```

(The `switch (value)` handler below stays as-is — an unreachable case is harmless, and every case still compiles.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/library/page_viewer_share_sheet_flags_test.dart`
Expected: PASS (4 tests).
Run: `flutter test test/features/library/page_viewer_share_extras_test.dart`
Expected: PASS — that test injects the default `FeatureFlags`; `share-link` is on by default and `fax`… NOTE: this pre-existing test taps `page-viewer-fax`. Since fax now defaults OFF, this test will break. Fix it in the same commit by constructing the viewer with `features: const FeatureFlags(fax: true)`:

In `test/features/library/page_viewer_share_extras_test.dart`, change the `PageViewerScreen(...)` at line 16 to:

```dart
        home: PageViewerScreen(
          documentId: 1,
          name: 'Scan X',
          repository: repo,
          features: const FeatureFlags(fax: true),
        ),
```

and add the import at the top:

```dart
import 'package:mobile/features/library/feature_flags.dart';
```

Re-run: `flutter test test/features/library/page_viewer_share_extras_test.dart`
Expected: PASS.

- [ ] **Step 5: Full library sweep**

Run: `flutter test test/features/library/`
Expected: PASS. If any other pre-existing test taps `page-viewer-fax` with default flags, apply the same `features: const FeatureFlags(fax: true)` fix to that test file (the fax tile is the only default-visibility change).

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/page_viewer_screen.dart test/features/library/page_viewer_share_sheet_flags_test.dart test/features/library/page_viewer_share_extras_test.dart
git commit -m "feat(library): gate share-sheet tiles on FeatureFlags (fax now default-off)"
```

---

### Task 5: `PageViewerScreen` — gate the overflow (⋯) menu

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart:551-585` (`_buildOverflowMenu`), `:675` (trailing usage stays — already accepts `Widget?`)
- Test: `test/features/library/page_viewer_overflow_flags_test.dart`

**Interfaces:**
- Consumes: `widget.features` (Task 3).
- Produces: `_buildOverflowMenu()` returns `Widget?` — `null` when all four items are off, so `EditorTopBar.trailing` (already `Widget?`) renders no button.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/page_viewer_overflow_flags_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    required FeatureFlags features,
  }) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(
          documentId: 1,
          name: 'Scan X',
          repository: repo,
          features: features,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('overflow button present by default', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags());
    expect(find.byKey(const Key('page-viewer-page-menu')), findsOneWidget);
  });

  testWidgets('overflow button hidden when all four items are off', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(
        rename: false,
        merge: false,
        split: false,
        deleteDocument: false,
      ),
    );
    expect(find.byKey(const Key('page-viewer-page-menu')), findsNothing);
  });

  testWidgets('only enabled items appear in the opened menu', (tester) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(merge: false, split: false),
    );
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-rename')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-merge')), findsNothing);
    expect(find.byKey(const Key('page-viewer-split')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/library/page_viewer_overflow_flags_test.dart`
Expected: FAIL — the "hidden when all off" and "only enabled items" cases fail (menu + all items always built).

- [ ] **Step 3: Make `_buildOverflowMenu` return `Widget?` and gate items**

Replace `_buildOverflowMenu` (lines 551-585) with:

```dart
  /// The overflow (⋯) menu: Rename, Merge, Split, Delete-document. Returns null
  /// (no button) when every item is disabled by its feature flag.
  Widget? _buildOverflowMenu() {
    final f = widget.features;
    if (!(f.rename || f.merge || f.split || f.deleteDocument)) return null;
    return PopupMenuButton<String>(
      key: const Key('page-viewer-page-menu'),
      enabled: !_actionsDisabled,
      onSelected: (v) {
        if (v == 'rename') unawaited(_rename());
        if (v == 'merge') unawaited(_mergeAnother());
        if (v == 'split') unawaited(_splitAfter());
        if (v == 'delete') unawaited(_confirmAndDelete());
      },
      itemBuilder: (_) => [
        if (f.rename)
          const PopupMenuItem<String>(
            value: 'rename',
            key: Key('page-viewer-rename'),
            child: Text('Rename'),
          ),
        if (f.merge)
          const PopupMenuItem<String>(
            value: 'merge',
            key: Key('page-viewer-merge'),
            child: Text('Merge another document…'),
          ),
        if (f.split)
          const PopupMenuItem<String>(
            value: 'split',
            key: Key('page-viewer-split'),
            child: Text('Split after this page'),
          ),
        if (f.deleteDocument)
          const PopupMenuItem<String>(
            value: 'delete',
            key: Key('page-viewer-delete'),
            child: Text('Delete document'),
          ),
      ],
    );
  }
```

The `trailing: _buildOverflowMenu()` at line 675 needs no change — `EditorTopBar.trailing` is already `Widget?` and renders a spacer when null.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/library/page_viewer_overflow_flags_test.dart`
Expected: PASS (3 tests).
Run: `flutter test test/features/library/`
Expected: PASS — default flags keep the menu and all items, so existing tests are unaffected.

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/page_viewer_screen.dart test/features/library/page_viewer_overflow_flags_test.dart
git commit -m "feat(library): gate overflow menu items; hide the ⋯ button when all off"
```

---

### Task 6: `HomeScreen` — gate scan / id-card / import + pass `features` to the viewer

**Files:**
- Modify: `lib/features/library/home_screen.dart:242-249` (PageViewerScreen call), `:543-581` (`_buildActionRow`)
- Modify: `test/support/fake_library.dart:585-587` (`fakeLibraryDependencies`)
- Test: `test/features/library/home_screen_flags_test.dart`

**Interfaces:**
- Consumes: `LibraryDependencies.features` (Task 1); `PageViewerScreen.features` (Task 3).
- Produces: home action buttons gated; `fakeLibraryDependencies(repo, {features})` test helper.

- [ ] **Step 1: Add the `features` override to the test helper**

In `test/support/fake_library.dart`, add the import near the top (with the other `mobile/features/library` imports):

```dart
import 'package:mobile/features/library/feature_flags.dart';
```

Replace `fakeLibraryDependencies` (lines 585-587) with:

```dart
/// LibraryDependencies whose factory returns the given fake repository.
LibraryDependencies fakeLibraryDependencies(
  FakeDocumentRepository repo, {
  FeatureFlags features = const FeatureFlags(),
}) => LibraryDependencies(
  createRepository: () async => repo,
  features: features,
);
```

- [ ] **Step 2: Write the failing test**

Create `test/features/library/home_screen_flags_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required FeatureFlags features,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
            features: features,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all three home buttons present by default', (tester) async {
    await pumpHome(tester, features: const FeatureFlags());
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
    expect(find.byKey(const Key('home-scan-id')), findsOneWidget);
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('id card off hides the ID card button', (tester) async {
    await pumpHome(tester, features: const FeatureFlags(idCard: false));
    expect(find.byKey(const Key('home-scan-id')), findsNothing);
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('scan off hides the Scan button', (tester) async {
    await pumpHome(tester, features: const FeatureFlags(scan: false));
    expect(find.byKey(const Key('home-scan')), findsNothing);
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('import off hides the Import button', (tester) async {
    await pumpHome(tester, features: const FeatureFlags(import: false));
    expect(find.byKey(const Key('home-import')), findsNothing);
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/features/library/home_screen_flags_test.dart`
Expected: FAIL — the off cases fail (all three buttons always built).

- [ ] **Step 4: Gate the action row**

Replace `_buildActionRow` (lines 543-581) with a version that builds only enabled buttons and interleaves 8px gaps so layout stays correct regardless of which are hidden:

```dart
  Widget _buildActionRow(BuildContext context) {
    final f = widget.libraryDependencies.features;
    final buttons = <Widget>[
      if (f.scan)
        Expanded(
          flex: 3,
          child: ReamActionButton(
            key: const Key('home-scan'),
            label: 'Scan',
            icon: Icons.add,
            primary: true,
            onPressed: _repository == null ? null : _openScan,
          ),
        ),
      if (f.idCard)
        Expanded(
          flex: 2,
          child: ReamActionButton(
            key: const Key('home-scan-id'),
            label: 'ID card',
            icon: Icons.badge_outlined,
            onPressed: _repository == null ? null : _openIdScan,
          ),
        ),
      if (f.import)
        Expanded(
          flex: 2,
          child: ReamActionButton(
            key: const Key('home-import'),
            label: 'Import',
            icon: Icons.download_outlined,
            onPressed: _repository == null ? null : _onImport,
          ),
        ),
    ];
    final spaced = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 8));
      spaced.add(buttons[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(children: spaced),
    );
  }
```

- [ ] **Step 5: Pass `features` into the viewer**

In the `PageViewerScreen(...)` builder (lines 242-249), add the `features` argument:

```dart
        builder: (_) => PageViewerScreen(
          documentId: s.document.id,
          name: s.document.name,
          repository: repo,
          dependencies: widget.dependencies,
          printer: widget.libraryDependencies.printer,
          share: widget.libraryDependencies.share,
          features: widget.libraryDependencies.features,
        ),
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/features/library/home_screen_flags_test.dart`
Expected: PASS (4 tests).
Run: `flutter test test/features/library/home_screen_test.dart`
Expected: PASS — default flags keep all three buttons.

- [ ] **Step 7: Commit**

```bash
git add lib/features/library/home_screen.dart test/support/fake_library.dart test/features/library/home_screen_flags_test.dart
git commit -m "feat(library): HomeScreen gates scan/id-card/import; passes FeatureFlags to viewer"
```

---

### Task 7: BDD scenario + steps + build_runner + device verification

**Files:**
- Create: `integration_test/f1_feature_flags.feature`
- Create: `test/step/the_app_launches_with_the_print_feature_disabled.dart`
- Create: `test/step/i_open_the_share_menu.dart`
- Create: `test/step/i_do_not_see_the_print_action.dart`
- Modify: `test/support/fake_library.dart` (`persistentLibraryDependencies` gains a `features` param)
- Generated: `integration_test/f1_feature_flags_test.dart` (via build_runner — do not hand-edit)

**Interfaces:**
- Consumes: `runCamScannerApp` (from `main.dart`), `persistentLibraryDependencies`, the persistent-storage seed step + `i_open_the_first_document` + `i_see_the_page_viewer` (all pre-existing), `FeatureFlags` (Task 1).

- [ ] **Step 1: Add a `features` param to `persistentLibraryDependencies`**

In `test/support/fake_library.dart`, replace the signature/body of `persistentLibraryDependencies` (lines 637-655) so it accepts a flags override (import from Task 6 already present):

```dart
LibraryDependencies persistentLibraryDependencies({
  required File dbFile,
  required Directory baseDir,
  FeatureFlags features = const FeatureFlags(),
}) {
  final share = FakeShareChannel();
  lastBddShareChannel = share;
  return LibraryDependencies(
    createRepository: () async => DriftDocumentRepository(
      db: AppDatabase(NativeDatabase(dbFile)),
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(baseDir),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const PerspectiveWarper(),
    ),
    printer: FakeDocumentPrinter(),
    share: share,
    features: features,
  );
}
```

- [ ] **Step 2: Write the `.feature` file**

Create `integration_test/f1_feature_flags.feature`:

```gherkin
Feature: Build-time feature flags hide disabled actions
  Scenario: A build with the print feature disabled hides the Print action
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches with the print feature disabled
    And I open the first document
    Then I see the page viewer
    When I open the share menu
    Then I do not see the print action
```

- [ ] **Step 3: Regenerate the BDD test**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: creates `integration_test/f1_feature_flags_test.dart` and reports the three new step stubs it wired (the launch step, open-share, do-not-see-print). Reused steps ("a document with a real page image…", "I open the first document", "I see the page viewer") map to the existing files.

- [ ] **Step 4: Implement the launch step**

Create `test/step/the_app_launches_with_the_print_feature_disabled.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/persistent_storage.dart';

/// Usage: the app launches with the print feature disabled
Future<void> theAppLaunchesWithThePrintFeatureDisabled(
  WidgetTester tester,
) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: persistentLibraryDependencies(
      dbFile: persistentDbFile!,
      baseDir: persistentDir!,
      features: const FeatureFlags(print: false),
    ),
  );
  await tester.pumpAndSettle();
}
```

- [ ] **Step 5: Implement the open-share-menu step**

Create `test/step/i_open_the_share_menu.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the share menu
Future<void> iOpenTheShareMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-share')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 6: Implement the assertion step**

Create `test/step/i_do_not_see_the_print_action.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the print action
Future<void> iDoNotSeeThePrintAction(WidgetTester tester) async {
  expect(find.byKey(const Key('page-viewer-print')), findsNothing);
  // The share sheet is really open — a still-enabled action is present.
  expect(find.byKey(const Key('page-viewer-export')), findsOneWidget);
}
```

- [ ] **Step 7: Confirm the step import paths match**

The generator writes relative imports in `integration_test/f1_feature_flags_test.dart` pointing at `../test/step/...`. If build_runner produced a placeholder for a reused step, delete the duplicate stub so the existing implementation is used (matches how e5 reused e4's steps).

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: clean regeneration, no unresolved step warnings.

- [ ] **Step 8: Run the BDD test on the host**

Run: `flutter test integration_test/f1_feature_flags_test.dart`
Expected: PASS — `+1 All tests passed!` (host run exercises the widget tree; no native libs needed for gating).

- [ ] **Step 9: Analyze + full host suite**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test`
Expected: All host tests pass except the 2 known-environmental `opencv_edge_detector` failures (libdartcv doesn't load under plain `flutter test` — documented, not a regression).

- [ ] **Step 10: Commit**

```bash
git add integration_test/f1_feature_flags.feature integration_test/f1_feature_flags_test.dart test/step/the_app_launches_with_the_print_feature_disabled.dart test/step/i_open_the_share_menu.dart test/step/i_do_not_see_the_print_action.dart test/support/fake_library.dart
git commit -m "test(library): BDD scenario — disabled print feature hides the Print action"
```

- [ ] **Step 11: Device verification (CONTROLLER-RUN — both platforms)**

This is the project's device gate. The gating logic is pure-Dart UI (no camera/opencv/ML Kit/PDF native path), so the BDD integration test IS the device proof; a per-flag on-device matrix adds no coverage.

Run on a real Android device:
`flutter test integration_test/f1_feature_flags_test.dart -d <android-device-id>`
Run on a real iOS device/sim:
`flutter test integration_test/f1_feature_flags_test.dart -d <ios-device-id>`
Expected on both: `+1 All tests passed!`

Record both results in the progress ledger. If a device is genuinely unavailable, record it as an explicit, named gap (never a silent one) per the project non-negotiable.

---

## Self-Review

**1. Spec coverage:**
- 21 flags with exact env names + fax-default-off → Task 1 (class) + flag table in Global Constraints. ✅
- Injectable, threaded through `LibraryDependencies.features` → Task 1. ✅
- Hide-entirely gating for toolbar / share button / share sheet / overflow / home → Tasks 2–6. ✅
- Share button auto-hide when all sub-flags off → Task 3 (`_showShareButton`). ✅
- Overflow button hidden when all four off → Task 5. ✅
- TDD + BDD, both platforms → every task is test-first; Task 7 is BDD + device. ✅
- Accepted gap (scan+import both off ⇒ no way to add documents): documented in the spec; not guarded, consistent with "a build can strip anything." No task needed. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step states the exact command and expected result. ✅

**3. Type consistency:** `FeatureFlags` field names are identical across Tasks 1, 3–7. `EditorToolbar.show*` names (Task 2) match the call site (Task 3). `_buildOverflowMenu` returns `Widget?` (Task 5) and `EditorTopBar.trailing` is `Widget?` (verified). `fakeLibraryDependencies`/`persistentLibraryDependencies` gain a `features` param used consistently (Tasks 6, 7). ✅

**Cross-task note for the executor:** Task 4 changes the default visibility of exactly one control — the fax tile (now default-off). The only pre-existing test known to tap `page-viewer-fax` is `page_viewer_share_extras_test.dart`, fixed in Task 4 Step 4. Task 4 Step 5's full-library sweep catches any other tap-fax test; apply the same `features: const FeatureFlags(fax: true)` fix if found.
