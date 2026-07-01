# H3 Reorder Pages — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can long-press a page thumbnail in the `PageViewerScreen` strip to drag it to a new position; the new order persists to the database.

**Architecture:** Add `reorderPages` to `DocumentRepository` (interface + Drift implementation); extend `PageThumbnailStrip` with an optional `onReorder` callback that switches the renderer from `ListView` to `ReorderableListView`; wire `_reorderPages` in `PageViewerScreen` for optimistic reorder + async persist with SnackBar rollback on failure.

**Tech Stack:** Flutter 3.x `ReorderableListView` (horizontal, `buildDefaultDragHandles: false`, `ReorderableDragStartListener` per tile); Drift (SQLite); `bdd_widget_test` + `build_runner` for BDD integration tests.

## Global Constraints

- Dart/Flutter: `apps/mobile/pubspec.yaml` versions — do NOT add new pub dependencies.
- Widget keys: `Key('page-thumbnail-strip')` on the strip root; `Key('page-thumb-$index')` (0-based) on each tile's `Container` — unchanged from H2.
- `foregroundDecoration` (NOT `decoration`) for the selected-tile border — preserved from H2.
- `displayPath` (not `imagePath`) for tile images — unchanged from H2.
- All host tests run with `pnpm nx run mobile:test --skip-nx-cache` from the repo root.
- BDD step filename convention: letter-then-digit = no underscore (e.g. "position 2" → `position2`).
- No `// ignore:` comments unless the lint is demonstrably fired by the linter (check `flutter analyze` output before adding).
- TDD: write the failing test first, run to confirm RED, implement, confirm GREEN.
- Commit after each task passes its tests.

---

## File Map

| Action | File |
|---|---|
| Modify | `apps/mobile/lib/features/library/document_repository.dart` |
| Modify | `apps/mobile/lib/features/library/drift/drift_document_repository.dart` |
| Modify | `apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart` |
| Modify | `apps/mobile/lib/features/library/page_viewer_screen.dart` |
| Modify | `apps/mobile/test/support/fake_library.dart` |
| Modify | `apps/mobile/test/features/library/drift_document_repository_test.dart` |
| Modify | `apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart` |
| Modify | `apps/mobile/test/features/library/page_viewer_screen_test.dart` |
| Create | `apps/mobile/integration_test/h3_page_reorder.feature` |
| Create (generated) | `apps/mobile/integration_test/h3_page_reorder_test.dart` |
| Create | `apps/mobile/test/step/the_second_page_thumbnail_is_dragged_to_the_first_position.dart` |
| Create | `apps/mobile/test/step/the_first_visible_page_is_position2.dart` |
| Create | `scripts/verify/h3.sh` |
| Modify | `docs/superpowers/plans/00-plans-index.md` |

---

### Task 1: `reorderPages` — Repository interface + Fake

Add the abstract method to `DocumentRepository` and the matching implementation to `FakeDocumentRepository`. No Drift yet. No widget tests yet (those come in Tasks 3 and 4).

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`

**Interfaces:**
- Produces: `Future<void> reorderPages(int documentId, List<int> orderedPositions)` — Tasks 2, 4 consume this.
- Produces (fake): `bool throwOnReorder`, `List<int> lastReorderedPositions` — Task 4 widget tests use these.

- [ ] **Step 1: Add `reorderPages` to `DocumentRepository`**

  Open `apps/mobile/lib/features/library/document_repository.dart`. After the `addPageToDocument` declaration (around line 62), insert:

  ```dart
  /// Reassigns page positions for [documentId] according to [orderedPositions].
  ///
  /// [orderedPositions]: the original 1-based position values in their desired
  /// new order. Example: [2, 1] = swap two pages (former page 2 becomes first).
  ///
  /// Throws [DocumentSaveException] when [documentId] has no pages.
  Future<void> reorderPages(int documentId, List<int> orderedPositions);
  ```

- [ ] **Step 2: Add `reorderPages` to `FakeDocumentRepository`**

  Open `apps/mobile/test/support/fake_library.dart`.

  a) Add to the field declarations (after `throwOnAddPage`):
  ```dart
  final bool throwOnReorder;
  ```

  b) Add to the mutable tracking fields (after `addPageCalls`):
  ```dart
  List<int> lastReorderedPositions = <int>[];
  ```

  c) Add `this.throwOnReorder = false,` to the constructor (after `throwOnAddPage`):
  ```dart
  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.throwOnList = false,
    this.throwOnGetPages = false,
    this.throwOnDelete = false,
    this.throwOnExport = false,
    this.throwOnRename = false,
    this.throwOnUpdate = false,
    this.throwOnAddPage = false,
    this.throwOnReorder = false,   // ← add this line
    this.gate,
    this.exportGate,
    this.listGate,
    this.addPageGate,
    List<Document>? documents,
    this.pages,
  }) : documents = documents ?? <Document>[];
  ```

  d) Add the `@override` implementation (after `addPageToDocument`):
  ```dart
  @override
  Future<void> reorderPages(int documentId, List<int> orderedPositions) async {
    if (throwOnReorder) {
      throw const DocumentSaveException('fake: reorder failed');
    }
    lastReorderedPositions = List<int>.unmodifiable(orderedPositions);
  }
  ```

- [ ] **Step 3: Run `flutter analyze` from `apps/mobile/` — expect no errors**

  ```bash
  cd apps/mobile && flutter analyze --no-fatal-infos
  ```

  Expected: `No issues found!` (or only pre-existing warnings). Fix any new errors before continuing.

- [ ] **Step 4: Commit**

  ```bash
  git add apps/mobile/lib/features/library/document_repository.dart \
          apps/mobile/test/support/fake_library.dart
  git commit -m "feat(h3): add reorderPages to DocumentRepository interface + FakeDocumentRepository"
  ```

---

### Task 2: `DriftDocumentRepository.reorderPages`

Implement `reorderPages` in the Drift repo. Updates pages by primary-key (`id`) to avoid position-conflict ambiguity, then bumps `documents.modifiedAt` in the same transaction.

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `reorderPages(int documentId, List<int> orderedPositions)` from Task 1.
- Consumes: `addPageToDocument` (already in the repo — used to set up a 2-page document in tests).

- [ ] **Step 1: Write two failing tests in `drift_document_repository_test.dart`**

  In `main()`, add after the last existing test:

  ```dart
  group('reorderPages', () {
    test('swaps page positions for a 2-page document', () async {
      final r = repo();
      final doc = await r.createFromCapture(capture);
      // Add a second page using the same fixture file.
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
            File('test/fixtures/exif_sample.jpg').readAsBytesSync());
      await r.addPageToDocument(doc.id, CapturedImage(src2.path));

      final before = await r.getDocumentPages(doc.id);
      expect(before.map((p) => p.position), [1, 2]);
      final path1 = before[0].imagePath;
      final path2 = before[1].imagePath;

      // Swap: position 2 goes first, position 1 goes second.
      await r.reorderPages(doc.id, [2, 1]);

      final after = await r.getDocumentPages(doc.id);
      expect(after[0].imagePath, path2,
          reason: 'former page 2 is now at index 0');
      expect(after[1].imagePath, path1,
          reason: 'former page 1 is now at index 1');
    });

    test('throws DocumentSaveException when documentId has no pages', () async {
      await expectLater(
        repo().reorderPages(9999, [1]),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  });
  ```

- [ ] **Step 2: Run the tests to confirm RED**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "reorderPages"
  ```

  Expected: FAIL — `reorderPages` is not implemented yet (abstract method on `DriftDocumentRepository`). The compile error or `UnimplementedError` confirms RED.

- [ ] **Step 3: Implement `reorderPages` in `DriftDocumentRepository`**

  Open `apps/mobile/lib/features/library/drift/drift_document_repository.dart`. Add this method after `addPageToDocument`:

  ```dart
  @override
  Future<void> reorderPages(int documentId, List<int> orderedPositions) async {
    // Pre-fetch rows before the transaction to build a position→rowId map.
    // Updates inside the transaction use the primary key (id) to avoid
    // position-value conflicts when two pages swap positions.
    final rows = await (_db.select(_db.pages)
          ..where((t) => t.documentId.equals(documentId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    if (rows.isEmpty) {
      throw DocumentSaveException(
          'reorderPages: no pages for $documentId');
    }
    final posToId = {for (final r in rows) r.position: r.id};

    await _db.transaction(() async {
      for (var i = 0; i < orderedPositions.length; i++) {
        final oldPosition = orderedPositions[i];
        final rowId = posToId[oldPosition];
        if (rowId == null) continue; // unknown position — skip
        final newPosition = i + 1;
        if (oldPosition == newPosition) continue; // no change needed
        await (_db.update(_db.pages)
              ..where((t) => t.id.equals(rowId)))
            .write(PagesCompanion(position: Value(newPosition)));
      }
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(documentId)))
          .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
    });
  }
  ```

- [ ] **Step 4: Run the tests to confirm GREEN**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "reorderPages"
  ```

  Expected: Both `reorderPages` tests PASS.

- [ ] **Step 5: Run the full suite to catch regressions**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  ```

  Expected: All tests pass (319+ tests).

- [ ] **Step 6: Commit**

  ```bash
  git add apps/mobile/lib/features/library/drift/drift_document_repository.dart \
          apps/mobile/test/features/library/drift_document_repository_test.dart
  git commit -m "feat(h3): implement reorderPages in DriftDocumentRepository"
  ```

---

### Task 3: `PageThumbnailStrip` drag-reorder support

Add an optional `onReorder` callback. When set, switch the renderer from `ListView.builder` to `ReorderableListView.builder` with `ReorderableDragStartListener` per tile. Extract `_buildTile` as a private method shared by both branches.

The tile's `Container(key: Key('page-thumb-$index'), ...)` keeps the same key in the same position — existing tests continue to work unchanged.

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart`
- Modify: `apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart`

**Interfaces:**
- Produces: `PageThumbnailStrip(onReorder: void Function(int oldIndex, int newIndex)?)` — Tasks 4, 5 consume this.

- [ ] **Step 1: Write two failing tests in `page_thumbnail_strip_test.dart`**

  a) Update the `pump` helper to accept `onReorder` (add a named parameter after `onTap`):

  ```dart
  Future<void> pump(
    WidgetTester tester, {
    List<PageImage>? p,
    int current = 0,
    void Function(int)? onTap,
    void Function(int, int)? onReorder,   // ← add this
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageThumbnailStrip(
            pages: p ?? pages,
            currentIndex: current,
            onTap: onTap ?? (_) {},
            onReorder: onReorder,          // ← add this
          ),
        ),
      ));
  ```

  b) Add two new tests at the end of `main()`:

  ```dart
  testWidgets('onReorder provided → ReorderableListView is rendered', (tester) async {
    await pump(tester, onReorder: (_, __) {});
    await tester.pump();
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('onReorder null → ListView is rendered (default)', (tester) async {
    await pump(tester); // onReorder defaults to null
    await tester.pump();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
  });
  ```

  Add the import for `ReorderableListView` — it's in `package:flutter/material.dart` (already imported). No new import needed.

- [ ] **Step 2: Run to confirm RED**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "onReorder"
  ```

  Expected: FAIL — `PageThumbnailStrip` doesn't have `onReorder` yet.

- [ ] **Step 3: Rewrite `page_thumbnail_strip.dart`**

  Replace the entire file content with the following (all existing logic is preserved; `_buildTile` is extracted; the `build` method branches on `onReorder`):

  ```dart
  import 'dart:io';

  import 'package:flutter/material.dart';

  import '../page_image.dart';

  /// Horizontal scrollable strip of page thumbnails for [PageViewerScreen].
  /// [currentIndex] is 0-based (matching [PageController]). Auto-scrolls to
  /// keep the active tile visible when [currentIndex] changes.
  /// Tapping tile i calls [onTap](i).
  /// When [onReorder] is provided, tiles are long-press-draggable to reorder.
  class PageThumbnailStrip extends StatefulWidget {
    final List<PageImage> pages;
    final int currentIndex;
    final void Function(int index) onTap;
    final void Function(int oldIndex, int newIndex)? onReorder;

    const PageThumbnailStrip({
      super.key,
      required this.pages,
      required this.currentIndex,
      required this.onTap,
      this.onReorder,
    });

    @override
    State<PageThumbnailStrip> createState() => _PageThumbnailStripState();
  }

  class _PageThumbnailStripState extends State<PageThumbnailStrip> {
    final ScrollController _scrollController = ScrollController();

    @override
    void initState() {
      super.initState();
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

    /// Builds the tile for page at [index]. The tile's Container carries
    /// Key('page-thumb-$index') so tests can find it regardless of whether
    /// the parent list is ListView or ReorderableListView.
    Widget _buildTile(BuildContext context, int index) {
      final isSelected = index == widget.currentIndex;
      final page = widget.pages[index];
      final scheme = Theme.of(context).colorScheme;
      final dpr = MediaQuery.of(context).devicePixelRatio;
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
          foregroundDecoration: isSelected
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
              errorBuilder: (_, _, _) => placeholder,
            ),
          ),
        ),
      );
    }

    @override
    Widget build(BuildContext context) {
      return Container(
        height: 96,
        color: Colors.black,
        child: widget.onReorder != null
            ? ReorderableListView.builder(
                key: const Key('page-thumbnail-strip'),
                scrollController: _scrollController,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                onReorder: widget.onReorder!,
                itemCount: widget.pages.length,
                itemBuilder: (context, index) => ReorderableDragStartListener(
                  key: ValueKey('page-thumb-item-$index'),
                  index: index,
                  child: _buildTile(context, index),
                ),
              )
            : ListView.builder(
                key: const Key('page-thumbnail-strip'),
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: widget.pages.length,
                itemBuilder: _buildTile,
              ),
      );
    }
  }
  ```

- [ ] **Step 4: Run strip tests to confirm GREEN**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "onReorder|ListView|ReorderableListView|page-thumbnail-strip|tile"
  ```

  Expected: All strip tests pass (both new and existing).

- [ ] **Step 5: Run full suite**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  ```

  Expected: All tests pass. No regressions.

- [ ] **Step 6: Commit**

  ```bash
  git add apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart \
          apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart
  git commit -m "feat(h3): PageThumbnailStrip supports drag-reorder via onReorder"
  ```

---

### Task 4: `PageViewerScreen` wire-up

Add `_reorderPages` (sync, optimistic) and `_persistReorder` (async, fire-and-forget) to `_PageViewerScreenState`. Pass `onReorder: _reorderPages` to `PageThumbnailStrip` inside `_buildPages`. Add two widget tests: success (positions reported correctly) and failure (SnackBar shown).

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Modify: `apps/mobile/test/features/library/page_viewer_screen_test.dart`

**Interfaces:**
- Consumes: `PageThumbnailStrip.onReorder` from Task 3.
- Consumes: `FakeDocumentRepository.throwOnReorder`, `.lastReorderedPositions` from Task 1.
- Consumes: `DocumentRepository.reorderPages` from Task 1.

- [ ] **Step 1: Write two failing tests in `page_viewer_screen_test.dart`**

  Add at the end of `main()`, after the existing H2 tests:

  ```dart
  // ── H3 — Reorder pages ─────────────────────────────────────────────────

  testWidgets(
      'H3: invoking onReorder(1, 0) calls reorderPages([2,1]) and shows page 2 first',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/r1.jpg'),
        const PageImage(position: 2, imagePath: '/nonexistent/r2.jpg'),
      ],
    );
    await pushViewer(tester, repo);

    // PageThumbnailStrip now renders a ReorderableListView (onReorder is set).
    final rlv = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView));
    rlv.onReorder(1, 0); // move index 1 → index 0
    await tester.pumpAndSettle();

    // Repository was called with the new position order.
    expect(repo.lastReorderedPositions, [2, 1]);
    // The PageView now shows the page that was at position 2 (now index 0).
    expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
  });

  testWidgets('H3: reorder failure shows SnackBar and stays on viewer',
      (tester) async {
    final repo = FakeDocumentRepository(
      throwOnReorder: true,
      pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/r1.jpg'),
        const PageImage(position: 2, imagePath: '/nonexistent/r2.jpg'),
      ],
    );
    await pushViewer(tester, repo);

    final rlv = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView));
    rlv.onReorder(1, 0);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reorder pages"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });
  ```

  Also add the `ReorderableListView` import (it's in `material.dart` — already imported). No new import needed.

- [ ] **Step 2: Run to confirm RED**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "H3"
  ```

  Expected: FAIL — `PageViewerScreen` doesn't wire `onReorder` yet; `find.byType(ReorderableListView)` throws.

- [ ] **Step 3: Add `_reorderPages` and `_persistReorder` to `page_viewer_screen.dart`**

  In `_PageViewerScreenState`, add these two methods after `_editCrop`:

  ```dart
  void _reorderPages(int oldIndex, int newIndex) {
    // ReorderableListView reports newIndex as if the dragged item hasn't been
    // removed yet; adjust to the true insertion index.
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final ordered = List<PageImage>.from(_pages!);
    ordered.insert(insertAt, ordered.removeAt(oldIndex));
    setState(() => _pages = ordered); // optimistic: update UI immediately
    _persistReorder(ordered);
  }

  Future<void> _persistReorder(List<PageImage> ordered) async {
    try {
      await widget.repository.reorderPages(
          widget.documentId, ordered.map((p) => p.position).toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reorder pages")),
      );
      _load();
    }
  }
  ```

- [ ] **Step 4: Wire `onReorder` in `_buildPages`**

  In `_buildPages`, update the `PageThumbnailStrip` call to add `onReorder`:

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
          onReorder: _reorderPages,   // ← add this line
        ),
      ],
    );
  }
  ```

- [ ] **Step 5: Run H3 viewer tests to confirm GREEN**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "H3"
  ```

  Expected: Both H3 tests PASS.

- [ ] **Step 6: Run full suite**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  ```

  Expected: All tests pass (321+ tests). Zero regressions.

- [ ] **Step 7: Run `flutter analyze`**

  ```bash
  cd apps/mobile && flutter analyze --no-fatal-infos
  ```

  Expected: No new issues. If `_persistReorder` triggers `discarded_futures` lint, add `// ignore: discarded_futures` on the `_persistReorder(ordered);` line in `_reorderPages` only.

- [ ] **Step 8: Commit**

  ```bash
  git add apps/mobile/lib/features/library/page_viewer_screen.dart \
          apps/mobile/test/features/library/page_viewer_screen_test.dart
  git commit -m "feat(h3): PageViewerScreen wires drag-reorder; optimistic update + async persist"
  ```

---

### Task 5: BDD feature + step defs + generated test

Write the Gherkin feature, two new step defs, then run `build_runner` to generate the test file. Commit all generated and authored files together.

**Existing step def to reuse (do NOT recreate):**
`apps/mobile/test/step/the_page_viewer_is_open_with2_pages.dart` — already exists from H2.

**Files:**
- Create: `apps/mobile/integration_test/h3_page_reorder.feature`
- Create: `apps/mobile/test/step/the_second_page_thumbnail_is_dragged_to_the_first_position.dart`
- Create: `apps/mobile/test/step/the_first_visible_page_is_position2.dart`
- Create (generated): `apps/mobile/integration_test/h3_page_reorder_test.dart`

**Interfaces:**
- Consumes: `PageViewerScreen` with `onReorder` wired (Task 4).
- Consumes: `FakeDocumentRepository` + `h2Repo` from existing step def.
- Consumes: `ReorderableListView` from `package:flutter/material.dart`.

- [ ] **Step 1: Write the feature file**

  Create `apps/mobile/integration_test/h3_page_reorder.feature`:

  ```gherkin
  Feature: H3 Page reorder

    Scenario: Dragging the second thumbnail to the first position swaps the order
      Given the page viewer is open with 2 pages
      When the second page thumbnail is dragged to the first position
      Then the first visible page is position 2
  ```

- [ ] **Step 2: Write the "drag" step definition**

  Create `apps/mobile/test/step/the_second_page_thumbnail_is_dragged_to_the_first_position.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  /// Invokes the [ReorderableListView.onReorder] callback directly
  /// (long-press drag is not simulated in host; the callback wiring is the
  /// contract under test here; on-device testing covers the gesture).
  Future<void> theSecondPageThumbnailIsDraggedToTheFirstPosition(
      WidgetTester tester) async {
    final rlv = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView));
    rlv.onReorder(1, 0); // move index 1 to index 0
    await tester.pumpAndSettle();
  }
  ```

- [ ] **Step 3: Write the "then" step definition**

  Create `apps/mobile/test/step/the_first_visible_page_is_position2.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  Future<void> theFirstVisiblePageIsPosition2(WidgetTester tester) async {
    // After reorder, the PageView shows the page formerly at position 2
    // at index 0. Its InteractiveViewer has key 'page-viewer-page-2'.
    expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
  }
  ```

- [ ] **Step 4: Run `build_runner` to generate the test**

  ```bash
  pnpm nx run mobile:build_runner
  ```

  Expected: Generates `apps/mobile/integration_test/h3_page_reorder_test.dart`.

  The generated file will import:
  - `the_page_viewer_is_open_with2_pages.dart`
  - `the_second_page_thumbnail_is_dragged_to_the_first_position.dart`
  - `the_first_visible_page_is_position2.dart`

  Verify these imports appear in the generated file:
  ```bash
  grep "import" apps/mobile/integration_test/h3_page_reorder_test.dart
  ```

- [ ] **Step 5: Run full suite (includes the generated BDD test via host runner)**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  ```

  Expected: All tests pass including the new H3 BDD scenario.

- [ ] **Step 6: Commit**

  ```bash
  git add apps/mobile/integration_test/h3_page_reorder.feature \
          apps/mobile/integration_test/h3_page_reorder_test.dart \
          apps/mobile/test/step/the_second_page_thumbnail_is_dragged_to_the_first_position.dart \
          apps/mobile/test/step/the_first_visible_page_is_position2.dart
  git commit -m "test(h3): BDD feature, step defs, and generated test for page reorder"
  ```

---

### Task 6: Verify script + plans index

Author `scripts/verify/h3.sh` following the same pattern as `scripts/verify/h2.sh`. Update the plans index to mark H3 done.

**Files:**
- Create: `scripts/verify/h3.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Create `scripts/verify/h3.sh`**

  ```bash
  #!/usr/bin/env bash
  # Verify H3 (Reorder pages) acceptance criteria.
  # Run from repository root: bash scripts/verify/h3.sh
  # VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib.sh
  source "$DIR/lib.sh"
  cd "$ROOT"

  echo "== H3 verification =="

  require_tool flutter
  require_tool pnpm

  # ---- Static assertions ----
  assert_file_has "reorderPages in DocumentRepository interface" \
    "apps/mobile/lib/features/library/document_repository.dart" \
    "reorderPages"

  assert_file_has "reorderPages in DriftDocumentRepository" \
    "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
    "reorderPages"

  assert_file_has "onReorder parameter in PageThumbnailStrip" \
    "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
    "onReorder"

  assert_file_has "ReorderableListView in PageThumbnailStrip" \
    "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
    "ReorderableListView"

  assert_file_has "ReorderableDragStartListener in PageThumbnailStrip" \
    "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
    "ReorderableDragStartListener"

  assert_file_has "_reorderPages in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "_reorderPages"

  assert_file_has "onReorder wired in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "onReorder"

  assert_file_has "BDD feature file exists" \
    "apps/mobile/integration_test/h3_page_reorder.feature" \
    "Page reorder"

  assert_file_has "generated BDD test exists" \
    "apps/mobile/integration_test/h3_page_reorder_test.dart" \
    "thePageViewerIsOpenWith2Pages"

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
      pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=h3
  fi

  echo "== H3 verification complete =="
  ```

  Make it executable:
  ```bash
  chmod +x scripts/verify/h3.sh
  ```

- [ ] **Step 2: Update `docs/superpowers/plans/00-plans-index.md`**

  Find the H3 row and change status from `⏳` to `✅ **built & gated**`:

  Before:
  ```
  | H3 | Reorder pages | 06 | `…-h3-reorder.md` | ⏳ |
  ```

  After:
  ```
  | H3 | Reorder pages | 06 | `2026-07-01-h3-reorder-pages.md` | ✅ **built & gated** |
  ```

- [ ] **Step 3: Run `scripts/verify/h3.sh` with device skipped**

  ```bash
  VERIFY_SKIP_DEVICE=1 bash scripts/verify/h3.sh
  ```

  Expected: All non-device checks pass. Output ends with `== H3 verification complete ==`.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/verify/h3.sh docs/superpowers/plans/00-plans-index.md
  git commit -m "chore(h3): verify script and plans index update"
  ```
