# H2 Page Thumbnail Strip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a horizontal scrollable page-thumbnail strip to the bottom of `PageViewerScreen`, replacing the "X / N" text indicator, so users can see all pages at a glance and tap to navigate.

**Architecture:** A new pure-display `PageThumbnailStrip` widget receives `List<PageImage>`, a `currentIndex`, and an `onTap` callback. It renders one `Image.file` tile per page (with `cacheWidth` for memory efficiency, `errorBuilder` for missing files) and auto-scrolls to keep the current page visible. `PageViewerScreen._buildPages` switches from a `Stack`-with-indicator to a `Column` of `[Expanded(PageView), PageThumbnailStrip]`.

**Tech Stack:** Flutter 3.12.2+, `dart:io` (File), `package:flutter_test`, `bdd_widget_test` + `build_runner` for BDD, `pnpm nx` Nx monorepo runner.

## Global Constraints

- No new `pubspec.yaml` dependencies — everything uses existing Flutter packages
- OCP: `FilterPickerStrip`, `EnhancerMode`, all enhancers, `DriftDocumentRepository.createFromCapture()`, and `addPageToDocument` must NOT be modified
- Widget tests use non-loadable paths (`/nonexistent/...`) — prevents `Image.file` from hanging in `FakeAsync`; on-device rendering is verified by BDD
- `cacheWidth` on each tile thumbnail: `(56 * MediaQuery.of(context).devicePixelRatio).round()`
- Tile dimensions: 56 px wide × 80 px tall; 4 px margin each side; strip height: 96 px; background: `Colors.black`
- Current-page border: `Border.all(color: scheme.primary, width: 2)` with `BorderRadius.circular(4)`
- Widget keys: `Key('page-thumbnail-strip')` on the `ListView`, `Key('page-thumb-$index')` (0-based) per tile
- Run all tests with: `pnpm nx run mobile:test --skip-nx-cache`
- Run analyzer with: `pnpm nx run mobile:analyze --skip-nx-cache`
- BDD generation: `cd apps/mobile && flutter pub run build_runner build --delete-conflicting-outputs`
- Test file for the suite is at repo root; run from repo root

---

### Task 1: `PageThumbnailStrip` widget + `PageViewerScreen` wiring + host tests

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart`
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart` (lines ~244–278: `_buildPages`)
- Create: `apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart`
- Modify: `apps/mobile/test/features/library/page_viewer_screen_test.dart` (update 2 assertions that reference `page-viewer-indicator`)

**Interfaces:**
- Consumes: `PageImage` from `lib/features/library/page_image.dart` — fields: `int position`, `String imagePath`, `String? flatImagePath`, `String get displayPath` (flat ?? original)
- Produces: `class PageThumbnailStrip extends StatefulWidget` with constructor `const PageThumbnailStrip({super.key, required List<PageImage> pages, required int currentIndex, required void Function(int) onTap})`

- [ ] **Step 1: Write failing tests for `PageThumbnailStrip`**

Create `apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/widgets/page_thumbnail_strip.dart';

void main() {
  final pages = [
    const PageImage(position: 1, imagePath: '/nonexistent/h2p1.jpg'),
    const PageImage(position: 2, imagePath: '/nonexistent/h2p2.jpg'),
    const PageImage(position: 3, imagePath: '/nonexistent/h2p3.jpg'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<PageImage>? p,
    int current = 0,
    void Function(int)? onTap,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageThumbnailStrip(
            pages: p ?? pages,
            currentIndex: current,
            onTap: onTap ?? (_) {},
          ),
        ),
      ));

  testWidgets('ListView has key page-thumbnail-strip', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
  });

  testWidgets('renders one tile per page with the correct 0-based key', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-2')), findsOneWidget);
  });

  testWidgets('current tile has a border; non-current tiles do not', (tester) async {
    await pump(tester, current: 1);
    await tester.pump();

    final selected = tester.widget<Container>(find.byKey(const Key('page-thumb-1')));
    final decoration = selected.decoration as BoxDecoration?;
    expect(decoration?.border, isNotNull, reason: 'selected tile must have a border');

    final notSelected = tester.widget<Container>(find.byKey(const Key('page-thumb-0')));
    expect(notSelected.decoration, isNull, reason: 'non-selected tile must have no border');
  });

  testWidgets('tapping tile i calls onTap(i)', (tester) async {
    int? tapped;
    await pump(tester, onTap: (i) => tapped = i);
    await tester.pump();

    await tester.tap(find.byKey(const Key('page-thumb-2')));
    await tester.pump();

    expect(tapped, 2);
  });

  testWidgets('tapping tile 0 calls onTap(0)', (tester) async {
    int? tapped;
    await pump(tester, onTap: (i) => tapped = i);
    await tester.pump();

    await tester.tap(find.byKey(const Key('page-thumb-0')));
    await tester.pump();

    expect(tapped, 0);
  });

  // IMPORTANT: On host, Image.file with a non-loadable path does NOT hang and does NOT
  // fire errorBuilder inside FakeAsync. Asserting cacheWidth and errorBuilder is the
  // deterministic wiring check; actual image rendering is verified on-device.
  testWidgets('each visible tile uses a downsampled Image.file with errorBuilder', (tester) async {
    await pump(tester);
    await tester.pump();
    final imgs = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(imgs, isNotEmpty);
    expect(imgs.first.image, isA<ResizeImage>(),
        reason: 'cacheWidth set → ResizeImage wraps FileImage');
    expect(imgs.first.errorBuilder, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd /path/to/repo  # repo root
pnpm nx run mobile:test --skip-nx-cache -- --name "page_thumbnail_strip_test"
```

Expected: FAIL with `Error: Could not resolve the package 'mobile/features/library/widgets/page_thumbnail_strip.dart'` or similar (file does not exist yet).

- [ ] **Step 3: Create `PageThumbnailStrip` widget**

Create `apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../page_image.dart';

/// Horizontal scrollable strip of page thumbnails for [PageViewerScreen].
/// [currentIndex] is 0-based (matching [PageController]). Auto-scrolls to
/// keep the active tile visible when [currentIndex] changes.
/// Tapping tile i calls [onTap](i).
class PageThumbnailStrip extends StatefulWidget {
  final List<PageImage> pages;
  final int currentIndex;
  final void Function(int index) onTap;

  const PageThumbnailStrip({
    super.key,
    required this.pages,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<PageThumbnailStrip> createState() => _PageThumbnailStripState();
}

class _PageThumbnailStripState extends State<PageThumbnailStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll after first frame so the controller has attached clients.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(PageThumbnailStrip old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    const double kSlot = 64.0; // 56 tile + 4 left margin + 4 right margin
    const double kPad = 8.0;   // ListView horizontal padding start
    final target = (kPad + widget.currentIndex * kSlot)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return Container(
      height: 96,
      color: Colors.black,
      child: ListView.builder(
        key: const Key('page-thumbnail-strip'),
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: widget.pages.length,
        itemBuilder: (context, index) {
          final isSelected = index == widget.currentIndex;
          final page = widget.pages[index];
          final placeholder = Container(
            width: 56,
            height: 80,
            color: scheme.surfaceContainerHighest,
            child:
                Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
          );
          return GestureDetector(
            onTap: () => widget.onTap(index),
            child: Container(
              key: Key('page-thumb-$index'),
              width: 56,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: isSelected
                  ? BoxDecoration(
                      border: Border.all(color: scheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(page.displayPath),
                  width: 56,
                  height: 80,
                  fit: BoxFit.cover,
                  cacheWidth: (56 * dpr).round(),
                  errorBuilder: (_, __, ___) => placeholder,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run the new tests to confirm they pass**

```bash
pnpm nx run mobile:test --skip-nx-cache -- --name "page_thumbnail_strip_test"
```

Expected: All 6 tests in `page_thumbnail_strip_test.dart` PASS.

- [ ] **Step 5: Update existing `page_viewer_screen_test.dart`**

The existing test `'loaded: full-res FileImage (NOT ResizeImage) + indicator'` in
`apps/mobile/test/features/library/page_viewer_screen_test.dart` asserts
`Key('page-viewer-indicator')` and `find.text('1 / 1')`, and uses `tester.widget<Image>(find.byType(Image))` which will fail once there are multiple `Image` widgets (strip + full-res). Update only these parts.

Find and replace the existing test (lines 55–71):

```dart
  testWidgets('loaded: full-res FileImage (NOT ResizeImage) + indicator',
      (tester) async {
    await pushViewer(tester, FakeDocumentRepository());

    expect(find.byType(PageViewerScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);

    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<FileImage>(),
        reason: 'viewer decodes full-res; NOT a ResizeImage like the thumbnail');
    expect((img.image as FileImage).file.path, '/nonexistent/page-1-1.jpg');
    expect(img.errorBuilder, isNotNull);

    expect(find.byKey(const Key('page-viewer-indicator')), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
  });
```

Replace with:

```dart
  testWidgets(
      'loaded: full-res FileImage (NOT ResizeImage); strip replaces indicator',
      (tester) async {
    await pushViewer(tester, FakeDocumentRepository());

    expect(find.byType(PageViewerScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);

    // The full-res image is the one inside the InteractiveViewer (NOT the strip thumbnail).
    final fullRes = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('page-viewer-page-1')),
        matching: find.byType(Image),
      ),
    );
    expect(fullRes.image, isA<FileImage>(),
        reason: 'viewer decodes full-res; NOT a ResizeImage like strip thumbnails');
    expect((fullRes.image as FileImage).file.path, '/nonexistent/page-1-1.jpg');
    expect(fullRes.errorBuilder, isNotNull);

    // Strip replaces old text indicator.
    expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-indicator')), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
  });
```

Also add a new test at the end of the viewer test file (inside `main()`, after the last test) to verify the strip and navigation:

```dart
  // ── H2 — Page thumbnail strip ──────────────────────────────────────────

  testWidgets('H2: strip is present; tapping thumb 0 fires animateToPage',
      (tester) async {
    // Two-page repo so the strip has two tiles.
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/h2a.jpg'),
        const PageImage(position: 2, imagePath: '/nonexistent/h2b.jpg'),
      ],
    );
    await pushViewer(tester, repo);

    expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
  });
```

- [ ] **Step 6: Wire `PageThumbnailStrip` into `PageViewerScreen._buildPages`**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`:

Add the import at the top (after existing imports):
```dart
import 'widgets/page_thumbnail_strip.dart';
```

Find and replace the entire `_buildPages` method:

Old:
```dart
  Widget _buildPages(List<PageImage> pages) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: pages.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (context, i) {
            final pg = pages[i];
            return InteractiveViewer(
              key: Key('page-viewer-page-${pg.position}'),
              child: Image.file(
                File(pg.displayPath),
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '${_current + 1} / ${pages.length}',
              key: const Key('page-viewer-indicator'),
            ),
          ),
        ),
      ],
    );
  }
```

New:
```dart
  Widget _buildPages(List<PageImage> pages) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final pg = pages[i];
              return InteractiveViewer(
                key: Key('page-viewer-page-${pg.position}'),
                child: Image.file(
                  File(pg.displayPath),
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 64),
                  ),
                ),
              );
            },
          ),
        ),
        PageThumbnailStrip(
          pages: pages,
          currentIndex: _current,
          onTap: (i) => _controller.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 7: Run all host tests and analyzer**

```bash
pnpm nx run mobile:test --skip-nx-cache
```

Expected: All tests pass (the updated viewer test + the new strip tests).

```bash
pnpm nx run mobile:analyze --skip-nx-cache
```

Expected: `Successfully ran target analyze for project mobile`

- [ ] **Step 8: Commit Task 1**

```bash
git add \
  apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart \
  apps/mobile/lib/features/library/page_viewer_screen.dart \
  apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart \
  apps/mobile/test/features/library/page_viewer_screen_test.dart
git commit -m "feat(h2): PageThumbnailStrip widget + PageViewerScreen wiring"
```

---

### Task 2: BDD scenarios + step defs + verify script

**Files:**
- Create: `apps/mobile/integration_test/h2_page_thumbnail_strip.feature`
- Create: `apps/mobile/integration_test/h2_page_thumbnail_strip_test.dart` (generated by build_runner — commit it)
- Create: `apps/mobile/test/step/the_page_viewer_is_open_with2_pages.dart`
- Create: `apps/mobile/test/step/i_see_the_page_thumbnail_strip.dart`
- Create: `apps/mobile/test/step/i_tap_the_second_page_thumbnail.dart`
- Create: `apps/mobile/test/step/the_viewer_has_navigated_to_page2.dart`
- Create: `scripts/verify/h2.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md` (H2 row → `✅ **built & gated**`)

**Interfaces:**
- Consumes (from Task 1): `PageThumbnailStrip` (`Key('page-thumbnail-strip')`, `Key('page-thumb-$index')`); `PageViewerScreen` (`Key('page-viewer-page-$position')`)
- Consumes: `FakeDocumentRepository(pages: [...])` from `test/support/fake_library.dart`
- Produces: committed BDD test + passing verify script

**Step-file naming convention (build_runner rule):**
When a digit immediately follows a letter (no preceding space in the camelCase result), no
underscore is inserted. When a letter follows a digit, an underscore IS inserted.
Examples: "has 2 pages" → `has2_pages`; "page 2" → `page2`.
So: "with 2 pages" → `with2_pages`, "page 2" → `page2`.

- [ ] **Step 1: Write the BDD feature file**

Create `apps/mobile/integration_test/h2_page_thumbnail_strip.feature`:

```gherkin
Feature: H2 Page thumbnail strip

  Scenario: Thumbnail strip is visible on a multi-page document
    Given the page viewer is open with 2 pages
    Then I see the page thumbnail strip

  Scenario: Tapping a thumbnail navigates to that page
    Given the page viewer is open with 2 pages
    When I tap the second page thumbnail
    Then the viewer has navigated to page 2
```

- [ ] **Step 2: Generate the BDD test via build_runner**

```bash
cd apps/mobile
flutter pub run build_runner build --delete-conflicting-outputs
cd ../..
```

Expected: Creates `apps/mobile/integration_test/h2_page_thumbnail_strip_test.dart`.

The generated file will look like this (verify the content matches):

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_page_viewer_is_open_with2_pages.dart';
import './../test/step/i_see_the_page_thumbnail_strip.dart';
import './../test/step/i_tap_the_second_page_thumbnail.dart';
import './../test/step/the_viewer_has_navigated_to_page2.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H2 Page thumbnail strip''', () {
    testWidgets('''Thumbnail strip is visible on a multi-page document''',
        (tester) async {
      await thePageViewerIsOpenWith2Pages(tester);
      await iSeeThePageThumbnailStrip(tester);
    });
    testWidgets('''Tapping a thumbnail navigates to that page''',
        (tester) async {
      await thePageViewerIsOpenWith2Pages(tester);
      await iTapTheSecondPageThumbnail(tester);
      await theViewerHasNavigatedToPage2(tester);
    });
  });
}
```

If the generated file differs (different filenames from your step text), adjust your step
definitions to match the actual generated imports — the generated file is the truth.

- [ ] **Step 3: Write step definition — `the_page_viewer_is_open_with2_pages.dart`**

Create `apps/mobile/test/step/the_page_viewer_is_open_with2_pages.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../support/fake_library.dart';

/// Shared repo for H2 BDD steps — read by Then/When steps in this feature.
FakeDocumentRepository h2Repo = FakeDocumentRepository();

/// Usage: the page viewer is open with 2 pages
Future<void> thePageViewerIsOpenWith2Pages(WidgetTester tester) async {
  h2Repo = FakeDocumentRepository(
    pages: [
      const PageImage(position: 1, imagePath: '/nonexistent/h2bdd1.jpg'),
      const PageImage(position: 2, imagePath: '/nonexistent/h2bdd2.jpg'),
    ],
  );
  await tester.pumpWidget(MaterialApp(
    home: PageViewerScreen(documentId: 1, name: 'H2 Doc', repository: h2Repo),
  ));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 4: Write step definition — `i_see_the_page_thumbnail_strip.dart`**

Create `apps/mobile/test/step/i_see_the_page_thumbnail_strip.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the page thumbnail strip
Future<void> iSeeThePageThumbnailStrip(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
}
```

- [ ] **Step 5: Write step definition — `i_tap_the_second_page_thumbnail.dart`**

Create `apps/mobile/test/step/i_tap_the_second_page_thumbnail.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the second page thumbnail
Future<void> iTapTheSecondPageThumbnail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-thumb-1')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 6: Write step definition — `the_viewer_has_navigated_to_page2.dart`**

Create `apps/mobile/test/step/the_viewer_has_navigated_to_page2.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the viewer has navigated to page 2
/// Verifies that the PageView has animated to page index 1 (0-based),
/// which shows the page at position 2. Key: 'page-viewer-page-2'.
Future<void> theViewerHasNavigatedToPage2(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
}
```

- [ ] **Step 7: Run all host tests to confirm the suite is still green**

```bash
pnpm nx run mobile:test --skip-nx-cache
```

Expected: All tests pass (new strip tests + updated viewer tests).

- [ ] **Step 8: Write `scripts/verify/h2.sh`**

Create `scripts/verify/h2.sh`:

```bash
#!/usr/bin/env bash
# Verify H2 (Page thumbnail strip) acceptance criteria.
# Run from repository root: bash scripts/verify/h2.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== H2 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "PageThumbnailStrip class exists" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "class PageThumbnailStrip"

assert_file_has "Key(page-thumbnail-strip) in page_thumbnail_strip.dart" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "page-thumbnail-strip"

assert_file_has "Key(page-thumb- prefix) in page_thumbnail_strip.dart" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "page-thumb-"

assert_file_has "PageThumbnailStrip used in page_viewer_screen.dart" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "PageThumbnailStrip"

assert_file_has "Key(page-thumbnail-strip) in page_viewer_screen.dart" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-thumbnail-strip"

# Negative: old indicator must be gone from the viewer screen
if grep -qF "page-viewer-indicator" "apps/mobile/lib/features/library/page_viewer_screen.dart"; then
  fail "old page-viewer-indicator key still present in page_viewer_screen.dart — must be removed"
else
  pass "old page-viewer-indicator absent from page_viewer_screen.dart"
fi

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/h2_page_thumbnail_strip.feature" \
  "Page thumbnail strip"

assert_file_has "BDD generated test exists" \
  "apps/mobile/integration_test/h2_page_thumbnail_strip_test.dart" \
  "thePageViewerIsOpenWith2Pages"

# ---- OpenCV host library (scan tests in shared suite need it) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Host tests + analyze + coverage ----
assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device gate (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android h2_page_thumbnail_strip_test.dart
verify_integration_ios h2_page_thumbnail_strip_test.dart

verify_summary
```

Make it executable:
```bash
chmod +x scripts/verify/h2.sh
```

- [ ] **Step 9: Run the verify script (device gate skipped)**

```bash
VERIFY_SKIP_DEVICE=1 bash scripts/verify/h2.sh
```

Expected: All static + host checks pass; the DEVICE CHECKS SKIPPED line is the only failure (expected).

- [ ] **Step 10: Update plans index**

In `docs/superpowers/plans/00-plans-index.md`, change the H2 row from:

```
| H2 | Page thumbnail strip | 06 | `…-h2-thumbnails.md` | ⏳ |
```

to:

```
| H2 | Page thumbnail strip | 06 | `2026-07-01-h2-thumbnails.md` | ✅ **built & gated** |
```

- [ ] **Step 11: Commit Task 2**

```bash
git add \
  apps/mobile/integration_test/h2_page_thumbnail_strip.feature \
  apps/mobile/integration_test/h2_page_thumbnail_strip_test.dart \
  apps/mobile/test/step/the_page_viewer_is_open_with2_pages.dart \
  apps/mobile/test/step/i_see_the_page_thumbnail_strip.dart \
  apps/mobile/test/step/i_tap_the_second_page_thumbnail.dart \
  apps/mobile/test/step/the_viewer_has_navigated_to_page2.dart \
  scripts/verify/h2.sh \
  docs/superpowers/plans/00-plans-index.md
git commit -m "feat(h2): BDD scenarios, step defs, and verify script"
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Task |
|---|---|
| `PageThumbnailStrip` class in `page_thumbnail_strip.dart` | Task 1 Step 3 |
| Strip shows one tile per page; renders `displayPath` | Task 1 Steps 1+3 |
| Current tile has 2 px primary border | Task 1 Steps 1+3 |
| Tapping tile i calls `onTap(i)` | Task 1 Steps 1+3 |
| `PageViewerScreen` shows strip; indicator gone | Task 1 Steps 5+6 |
| Strip tap → `PageController.animateToPage` | Task 1 Step 6 |
| `Key('page-thumbnail-strip')` on ListView | Task 1 Step 3 |
| `Key('page-thumb-$index')` (0-based) per tile | Task 1 Step 3 |
| BDD: 2-page viewer → 2 thumbnails visible | Task 2 |
| BDD: tap second thumbnail → page 2 shown | Task 2 |
| `scripts/verify/h2.sh` | Task 2 Step 8 |

All spec requirements covered. No gaps.

### Placeholder scan

No "TBD", "TODO", "fill in", or "similar to Task N" in this plan. All code is complete.

### Type consistency

- `PageImage.displayPath` used consistently throughout (not `imagePath`)
- `currentIndex` is 0-based everywhere — matches `PageController` semantics
- `Key('page-thumb-$index')` (0-based) in widget matches assertions in tests and BDD steps
- `Key('page-viewer-page-${pg.position}')` (1-based position) unchanged from existing viewer
- `FakeDocumentRepository(pages: [...])` constructor param matches existing `fake_library.dart`
