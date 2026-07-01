# H4 Delete / Retake Page — Design Spec

**Date:** 2026-07-01
**Status:** Approved
**Step:** H4 — Delete / retake page (Feature 06 / multi-page series)
**Depends on:** H3 (reorder pages complete and gated)
**Feeds:** H5 (multi-page PDF export)

---

## Goal

From the `PageViewerScreen`, a user can **delete** the page they are currently
viewing (with confirmation) or **retake** it — re-capture a fresh photo that
replaces the page in place, keeping its position. Deleting the *only* remaining
page deletes the whole document (with confirmation), matching the spec-06
"last-page rule".

Both actions work identically on iOS and Android (Material `PopupMenuButton`,
`AlertDialog`, and the existing camera stack — no platform-specific code).

---

## UX Decisions (most efficient + best UX)

**Per-page actions live in an app-bar overflow menu (`PopupMenuButton`, ⋮).**
Two items: **Retake page** and **Delete page**, both acting on the page
currently shown in the `PageView` (`_pages![_current]`).

- Rejected: per-thumbnail long-press context menu — long-press is already bound
  to drag-reorder (H3 `ReorderableDragStartListener`); overloading it is a
  conflict and hurts discoverability.
- Rejected: two more app-bar icons — the bar already holds rename / edit-crop /
  export / delete-document; grouping page-scoped actions under one overflow keeps
  it uncluttered and reads clearly.
- The existing **document-level delete** (trash icon) stays as-is (deletes the
  whole document regardless of page count). "Delete page" is page-scoped and
  distinct; on a 1-page document it collapses to the same outcome, and the
  confirm copy makes that explicit.

**Delete confirmation copy adapts to page count** (the viewer knows the count):
- Multiple pages: *"Delete this page?"* → "This can't be undone."
- Only one page: *"This is the only page. Deleting it removes the whole document."*

**Retake is single-shot.** It reuses the full capture → review pipeline
(`CameraScreen` → `CaptureReviewScreen`, including edge-detect pre-fill, crop,
and enhancer) so retaken pages get the same quality treatment as scanned ones.
On accept, the page is replaced in place and the camera pops straight back to
the viewer (no page-accumulation, no "Done" step).

---

## Architecture

Six focused changes:

| Layer | Change |
|---|---|
| `DocumentRepository` (interface) | Add `deletePage(...)` and `replacePage(...)` |
| `DriftDocumentRepository` | Implement both; delete renumbers remaining pages contiguously; replace overwrites the row + files in place |
| `CameraScreen` | Add optional single-capture mode (`onCapture` callback); when set, accept invokes it and pops |
| `PageViewerScreen` | Add `ScanDependencies` param; app-bar overflow menu; `_confirmAndDeletePage`, `_retakePage` handlers |
| `HomeScreen` | Pass `dependencies:` when constructing `PageViewerScreen` |
| `FakeDocumentRepository` (test support) | Implement the two new methods with in-memory renumbering + throw flags |

No schema migration. Pages are addressed by their stored `relativeImagePath` /
`flatRelativePath` columns (not derived from `position` at read time), so
renumbering positions is a column-only update — no file moves.

---

## API

### `DocumentRepository` additions

```dart
/// Deletes the page at [position] of [documentId]: removes its row, best-effort
/// deletes its image and flat files, and renumbers the remaining pages so their
/// positions stay contiguous (1..N-1). If it was the only page, the whole
/// document (row + dir) is deleted.
///
/// Returns the number of pages remaining (0 => the document was deleted).
/// Throws [DocumentSaveException] when no page exists at ([documentId], [position]).
Future<int> deletePage(int documentId, int position);

/// Replaces the page at [position] of [documentId] in place with [capture]
/// (EXIF-scrubbed), applying [corners] (default full-frame) and [enhancer]
/// exactly as [addPageToDocument] does. Overwrites the page's stored image and
/// flat derivative, updates its corners, and bumps `modifiedAt`. The page keeps
/// its [position]. Throws [DocumentSaveException] when no page exists at
/// ([documentId], [position]).
Future<void> replacePage(
  int documentId,
  int position,
  CapturedImage capture, {
  CropCorners? corners,
  ImageEnhancer? enhancer,
});
```

### `FakeDocumentRepository` additions

```dart
final bool throwOnDeletePage;    // new ctor param, default false
final bool throwOnReplacePage;   // new ctor param, default false
int? lastDeletedPagePosition;    // recorded on deletePage success
int? lastReplacedPagePosition;   // recorded on replacePage success
```

`deletePage` on the fake mutates its in-memory `_pages` list: removes the target,
renumbers survivors to 1..N-1, returns the new length; throws
`DocumentSaveException` if the position is absent (or `throwOnDeletePage`).
`replacePage` records the position (and throws on `throwOnReplacePage` / absent).

---

## Drift Implementation

### `deletePage(documentId, position)`

```
row = SELECT * FROM pages WHERE documentId=? AND position=?   (getSingleOrNull)
if row == null: throw DocumentSaveException('deletePage: no page (id, pos)')

remaining = (count of pages for documentId) - 1

transaction:
  DELETE FROM pages WHERE id = row.id
  if remaining > 0:
    for each survivor with position > deleted position:
      position -= 1            // keyed by id, descending order not required
    UPDATE documents.modifiedAt = clock()
  else:
    DELETE FROM documents WHERE id = documentId   // last-page rule

after commit (best-effort, outside txn):
  delete file row.relativeImagePath
  if row.flatRelativePath != null: delete it
  if remaining == 0: _fileStore.deleteDocumentDir(documentId)  // nuke the dir

return remaining
```

Renumber via a pre-fetched `id → position` list (like `reorderPages`), writing
`position - 1` to each survivor whose original position exceeded the deleted one.
Files are addressed by the row's stored relative paths, so no renaming is needed.

### `replacePage(documentId, position, capture, {corners, enhancer})`

Mirrors `addPageToDocument`, but targets an existing row instead of inserting:

```
row = SELECT * FROM pages WHERE documentId=? AND position=?   (getSingleOrNull)
if row == null: throw DocumentSaveException('replacePage: no page (id, pos)')

raw = read capture.path; scrubbed = _scrubber.scrub(raw)
isFullFrame = corners == null || corners == fullFrame
bytesToStore = (enhancer != null && isFullFrame) ? enhance(scrubbed) : scrubbed  // silent on failure
write bytesToStore to row.relativeImagePath        // overwrite in place

flatRel = null
if !isFullFrame:
  flat = _warper.warp(scrubbed, corners)
  if flat != null:
    flatBytes = enhancer != null ? enhance(flat) : flat   // silent on failure
    flatRel = _fileStore.flatRelativeFor(documentId, position)
    write flatBytes to flatRel

if flatRel == null && row.flatRelativePath != null:
  delete old flat file (best-effort)                // stale derivative removed

transaction:
  UPDATE pages SET corners=corners?.toStorage(), flatRelativePath=flatRel
         WHERE id = row.id
  UPDATE documents.modifiedAt = clock()

delete temp source (capture.path) if under systemTemp   // reuse _deleteTempSource
```

Wrap in try/catch → `DocumentSaveException('replacePage failed: $e')`, rethrowing
`DocumentSaveException` unchanged (same contract as `addPageToDocument`).

---

## `CameraScreen` Changes — single-capture mode

Add one optional parameter:

```dart
/// When non-null, the screen is in single-capture (retake) mode: after the
/// user accepts a capture in review, [onCapture] is invoked with the image,
/// crop corners, and enhancer. If it returns true the camera screen pops back
/// to its caller (one page only — no accumulation, no "Done"). When null
/// (default) the screen keeps its create/append behavior.
final Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)? onCapture;
```

`_onAccept` gains a leading branch:

```dart
if (widget.onCapture != null) {
  final ok = await widget.onCapture!(image, corners, enhancer);
  if (!mounted) return;
  if (!ok) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't replace page. Try again.")));
    navigator.pop();            // dismiss review, stay in camera to retry
    return;
  }
  navigator.pop();              // dismiss review
  navigator.pop();              // leave camera, back to viewer
  return;
}
// …existing create/append logic unchanged…
```

In single-capture mode the app-bar title stays "Scan" and the "Done" action is
never shown (`_pageCount` stays 0, and the "Done" affordance is already gated on
`_pageCount > 0`). No other change.

---

## `PageViewerScreen` Changes

**New parameter** (DI for the retake camera):

```dart
final ScanDependencies dependencies;
// ctor: this.dependencies = const ScanDependencies(),
```

`HomeScreen._openDocument` passes `dependencies: widget.dependencies`.

**App-bar overflow menu** (added to `actions`, after the export icon, before or
replacing nothing existing — the document trash icon stays):

```dart
PopupMenuButton<String>(
  key: const Key('page-viewer-page-menu'),
  enabled: !(_loading || _error || _exporting || (_pages?.isEmpty ?? true)),
  onSelected: (v) {
    if (v == 'retake') _retakePage();
    if (v == 'delete') _confirmAndDeletePage();
  },
  itemBuilder: (_) => const [
    PopupMenuItem(value: 'retake', key: Key('page-viewer-retake'),
        child: Text('Retake page')),
    PopupMenuItem(value: 'delete', key: Key('page-viewer-delete-page'),
        child: Text('Delete page')),
  ],
),
```

**Delete-page handler:**

```dart
Future<void> _confirmAndDeletePage() async {
  final pages = _pages;
  if (pages == null || pages.isEmpty) return;
  final page = pages[_current];
  final isLast = pages.length == 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(isLast
          ? 'This is the only page. Deleting it removes the whole document.'
          : "Delete this page? This can't be undone."),
      actions: [
        TextButton(
          key: const Key('page-viewer-delete-page-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel')),
        TextButton(
          key: const Key('page-viewer-delete-page-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final remaining = await widget.repository
        .deletePage(widget.documentId, page.position);
    if (!mounted) return;
    if (remaining == 0) {
      Navigator.of(context).pop();   // document gone → back to Home
      return;
    }
    if (_current >= remaining) _current = remaining - 1;  // clamp
    await _load();
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't delete page")));
  }
}
```

**Retake handler:**

```dart
Future<void> _retakePage() async {
  final pages = _pages;
  if (pages == null || pages.isEmpty) return;
  final page = pages[_current];
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CameraScreen(
        dependencies: widget.dependencies,
        repository: widget.repository,
        onCapture: (image, corners, enhancer) async {
          try {
            await widget.repository.replacePage(
                widget.documentId, page.position, image,
                corners: corners, enhancer: enhancer);
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    ),
  );
  if (!mounted) return;
  await _load();   // refresh whether or not a replace happened
}
```

After `_load()`, clamp `_current` if it now exceeds bounds (defensive; retake
doesn't change count, but keep the same clamp helper used by delete).

---

## Error Handling

| Failure | Behavior |
|---|---|
| `deletePage` throws | SnackBar "Couldn't delete page"; viewer state unchanged |
| Page row missing | `DocumentSaveException` (guards double-delete races) → SnackBar |
| `replacePage` throws | `onCapture` returns false → camera SnackBar "Couldn't replace page. Try again.", stays in camera |
| File cleanup fails | Swallowed (best-effort); DB is authoritative, worst case = orphan file |
| Capture cancelled (user backs out of camera) | No `onCapture` call; viewer `_load()` is a harmless no-op refresh |

---

## Testing

**Unit — `DriftDocumentRepository`** (`drift_document_repository_h4_test.dart`,
real `NativeDatabase.memory()` like existing drift tests):
- delete a middle page of 3 → remaining 2, positions renumbered to [1,2], correct page removed, files deleted.
- delete the last remaining page → returns 0, document row gone, `deleteDocumentDir` called.
- delete a non-existent position → throws `DocumentSaveException`.
- replace an existing page (full-frame) → image bytes overwritten, corners cleared, position unchanged.
- replace with non-full-frame corners → flat written, `flatRelativePath` set, corners stored.
- replace a non-existent position → throws `DocumentSaveException`.

**Widget — `PageViewerScreen`** (`FakeDocumentRepository`):
- overflow menu exposes "Retake page" and "Delete page".
- Delete page (multi-page doc) → confirm dialog with per-page copy → confirm calls `deletePage`, records position, refreshes.
- Delete page cancel → `deletePage` not called.
- Delete the only page → dialog shows whole-document copy; confirming pops the viewer (remaining 0).
- `deletePage` throws → SnackBar shown, still on viewer.
- Retake selects camera route (push occurs); `replacePage` invoked when the injected `onCapture` fires (unit-level via calling the callback / or verify navigation push).

**BDD — `apps/mobile/integration_test/h4_delete_retake.feature`** → generated
`h4_delete_retake_test.dart` (on-device), step defs in `test/step/`:
- *Given a 2-page document, when I delete the current page and confirm, then the document has 1 page.*
- *Given a 1-page document, when I delete the page and confirm, then I return to the library and the document is gone.*
- *Given a document, when I retake the current page, then the page is replaced (modifiedAt bumped / new image shown).*

**Verify harness — `scripts/verify/h4.sh`** (built on `scripts/verify/lib.sh`):
asserts the two repository methods exist, host unit + widget suites pass, the
`.feature`/generated test are present and committed, and the on-device
integration test asserts the rendered result. Silence = FAIL; independent
adversarial verifier runs it from a clean state.

---

## Out of Scope (YAGNI)

- Multi-select / bulk page delete (spec 06 lists single-page delete only).
- Undo / trash-can restore for a deleted page.
- Insert-at-arbitrary-position (spec's "insert" is folded into add + reorder, already shipped).
- Reordering files on disk to match renumbered positions (unnecessary — rows store their own paths).
