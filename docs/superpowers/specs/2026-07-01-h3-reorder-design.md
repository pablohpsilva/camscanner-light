# H3 Reorder Pages — Design Spec

**Date:** 2026-07-01
**Status:** Approved
**Step:** H3 — Reorder pages (Feature 06 / multi-page series)
**Depends on:** H2 (PageThumbnailStrip complete and gated)
**Feeds:** H4 (delete/retake page), H5 (multi-page PDF)

---

## Goal

Users can long-press a page thumbnail in the `PageViewerScreen` strip to drag it left or right; releasing drops it in the new position. The new order is persisted immediately to the database.

---

## Architecture

Four focused changes, each with a clear single responsibility:

| Layer | Change |
|---|---|
| `DocumentRepository` (interface) | Add `reorderPages(int documentId, List<int> orderedPositions)` |
| `DriftDocumentRepository` | Implement `reorderPages` with a row-id-keyed transaction |
| `PageThumbnailStrip` (widget) | Add optional `onReorder` param; switch to `ReorderableListView` when set |
| `PageViewerScreen` | Add `_reorderPages(oldIndex, newIndex)`; wire to strip and repository |

No new files are needed. No schema migration (position column already exists, no uniqueness constraint).

---

## API

### `DocumentRepository`

```dart
/// Reassigns page positions for [documentId] according to [orderedPositions].
///
/// [orderedPositions]: the original 1-based position values in their desired
/// new order. Example: [2, 1] = swap two pages (former page 2 becomes first).
///
/// Throws [DocumentSaveException] when [documentId] has no pages.
Future<void> reorderPages(int documentId, List<int> orderedPositions);
```

### `FakeDocumentRepository` additions

```dart
bool throwOnReorder = false;                  // new ctor param
List<int> lastReorderedPositions = [];        // recorded on success
```

---

## Drift Implementation

Two steps, no temp-offset trick needed (updates are keyed by primary key `id`, so no position-value ambiguity):

1. **Before transaction:** query all page rows for `documentId` to build `Map<int position, int rowId>`.
2. **In transaction:**
   - For each `(i, oldPosition)` in `orderedPositions`, write `position = i + 1` to the row whose `id = posToId[oldPosition]`. Skip if `oldPosition == newPosition`.
   - Bump `documents.modifiedAt`.

Throws `DocumentSaveException('reorderPages: no pages for $documentId')` when the pre-flight query returns empty (no document or no pages).

---

## `PageThumbnailStrip` Changes

Add one optional parameter:

```dart
final void Function(int oldIndex, int newIndex)? onReorder;
```

**When `onReorder != null`** — use `ReorderableListView.builder`:
```dart
ReorderableListView.builder(
  scrollDirection: Axis.horizontal,
  buildDefaultDragHandles: false,   // we control the listener
  onReorder: onReorder!,
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
  itemCount: widget.pages.length,
  itemBuilder: (context, index) => ReorderableDragStartListener(
    key: Key('page-thumb-$index'),  // key must be on the outermost child
    index: index,
    child: _buildTile(context, index),
  ),
)
```

`ReorderableDragStartListener` activates drag on long-press; tap still fires `onTap` via the `GestureDetector` inside `_buildTile`. The selected-tile `foregroundDecoration` border is unchanged.

**When `onReorder == null`** — keep the existing `ListView.builder` (backward compat).

Extract `_buildTile(BuildContext context, int index)` as a private method returning the current `GestureDetector(Container(…Image.file…))` tree. Both branches call it — DRY.

---

## `PageViewerScreen` Changes

Add `_reorderPages`:

```dart
void _reorderPages(int oldIndex, int newIndex) {
  // ReorderableListView passes newIndex as if the item hasn't been removed yet;
  // normalize to the true insertion index.
  final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
  final ordered = List<PageImage>.from(_pages!);
  ordered.insert(insertAt, ordered.removeAt(oldIndex));
  setState(() => _pages = ordered);
  widget.repository
      .reorderPages(
          widget.documentId, ordered.map((p) => p.position).toList())
      .catchError((_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't reorder pages")),
    );
    _load();
  });
}
```

Pass to strip in `_buildPages`:

```dart
PageThumbnailStrip(
  pages: pages,
  currentIndex: _current,
  onTap: (i) => _controller.animateToPage(i, …),
  onReorder: _reorderPages,   // NEW
)
```

---

## UX

- Long-press a thumbnail → drag feedback appears (tile lifts, gap opens).
- Drag left/right → tile moves; strip scrolls if needed (Flutter built-in).
- Release → `onReorder` fires → optimistic reorder in UI → async persist.
- Failure → SnackBar `"Couldn't reorder pages"` + reload from DB.
- No loading indicator during persist (optimistic). The SnackBar is the only error signal.

---

## Testing Strategy

### Host widget tests (no device)

**`page_thumbnail_strip_test.dart`** (2 new tests):
- `onReorder != null` → `ReorderableListView` is in the widget tree.
- `onReorder == null` → `ListView` is in the widget tree (existing renderer).

**`drift_document_repository_test.dart`** (2 new tests):
- `reorderPages([2,1])` on a 2-page doc → positions swap; `modifiedAt` bumped.
- `reorderPages` on a documentId with no pages → throws `DocumentSaveException`.

**`page_viewer_screen_test.dart`** (2 new tests):
- Invoke `onReorder(1, 0)` via strip → `repo.lastReorderedPositions == [2, 1]`; page with position 2 is now shown at index 0 in PageView.
- `FakeDocumentRepository(throwOnReorder: true)` + invoke `onReorder` → SnackBar `"Couldn't reorder pages"` appears.

### BDD (integration, on-device)

File: `integration_test/h3_page_reorder.feature`

```gherkin
Feature: H3 Page reorder

  Scenario: Dragging the second thumbnail to the first position swaps the order
    Given the page viewer is open with 2 pages
    When the second page thumbnail is dragged to the first position
    Then the first visible page is position 2
```

Step `the second page thumbnail is dragged to the first position`: find the `ReorderableListView` and call its `onReorder(1, 0)` directly via the widget test API (reliable in both host and device contexts; a real drag gesture is tested manually).

Reuse existing step def `the_page_viewer_is_open_with2_pages.dart` (already in `test/step/`).

---

## Acceptance Criteria (each closed by a passing test)

- [ ] `reorderPages` persists the new page order and bumps `modifiedAt` — **unit (Drift)**
- [ ] `reorderPages` on a document with no pages throws `DocumentSaveException` — **unit (Drift)**
- [ ] `PageThumbnailStrip` renders `ReorderableListView` when `onReorder` is provided — **widget**
- [ ] Invoking `onReorder` from the strip calls `repository.reorderPages` with correct positions — **widget**
- [ ] Failed reorder shows SnackBar `"Couldn't reorder pages"` and reloads — **widget**
- [ ] BDD: dragging second thumbnail to first position shows page 2 first — **BDD integration**

---

## Out of Scope (YAGNI)

- Reorder animation beyond Flutter's built-in `ReorderableListView` proxy decorator.
- Undo/redo.
- Reorder in the camera session (H4/H5 territory).
- Multi-select reorder.
