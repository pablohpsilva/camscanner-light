# E3 — Re-edit Crop Corners Design

## Goal

Let the user reopen a saved document's crop overlay from the page viewer, adjust the corner handles, and re-trigger perspective flatten — replacing the stored flat image with a new warp from the original JPEG.

## Context

- **E1** introduced `CropCorners`, the `CropOverlay` widget, and persisted corners in the `Pages.corners` column (schema v2).
- **E2** introduced `ImageWarper` / `PerspectiveWarper`, the `Pages.flatRelativePath` column (schema v3), `PageImage.displayPath`, and `DriftDocumentRepository.createFromCapture` warp-on-save.
- **E3** adds an update pathway: read the always-preserved original JPEG, re-warp with new corners, overwrite `flatRelativePath`. No schema migration needed.

## Architecture

Three layers:

1. **Repository** — new `updatePageCorners` method on the `DocumentRepository` interface; implemented in `DriftDocumentRepository`.
2. **`EditCropScreen`** — small new screen (~65 lines) that wraps `CropOverlay` over the original JPEG and returns accepted corners via `Navigator.pop`.
3. **`PageViewerScreen`** — new crop-edit AppBar icon button; calls `_editCrop` which pushes `EditCropScreen`, awaits corners, calls the repo, reloads.

All file I/O and DB writes stay inside the repository. The screen never touches `ImageWarper`, `DocumentFileStore`, or Drift directly.

## Components

### `DocumentRepository` interface

New method added to `lib/features/library/document_repository.dart`:

```dart
/// Re-warps the page at [position] using [corners] and updates the stored
/// flat image. If [corners] == [CropCorners.fullFrame], deletes the flat
/// and clears [flatRelativePath]. Throws on warp or write failure.
Future<void> updatePageCorners(
    int documentId, int position, CropCorners corners);
```

### `DriftDocumentRepository.updatePageCorners`

File: `lib/features/library/drift/drift_document_repository.dart`

Algorithm:

1. Load the page row by `documentId` + `position` (getSingleOrNull; throw `DocumentSaveException` if absent).
2. Read existing `flatRelativePath` (needed for deletion in the fullFrame path).
3. **fullFrame branch** (`corners == CropCorners.fullFrame`):
   - Best-effort delete the flat file: `_fileStore.absoluteFor(flatRel).delete()` — swallow `FileSystemException`.
   - Update row: `PagesCompanion(corners: Value(null), flatRelativePath: Value(null))`.
4. **non-fullFrame branch**:
   - Read original JPEG: `File(_fileStore.absoluteFor(page.relativeImagePath)).readAsBytes()`.
   - Call `_warper.warp(bytes, corners)` — if null returned (shouldn't happen; fullFrame is guarded), treat as no-op and return.
   - Write result: `_fileStore.writeRelative(flatRelativeFor(docId, position), flat)`.
   - Update row: `PagesCompanion(corners: Value(corners.toStorage()), flatRelativePath: Value(flatRel))`.
   - If warp or write throws: **rethrow** — DB is not updated; caller shows SnackBar.
5. Row update uses `.where((t) => t.documentId.equals(documentId) & t.position.equals(position))`.

No transaction needed — same best-effort pattern as `createFromCapture`.

### `EditCropScreen`

New file: `lib/features/library/edit_crop_screen.dart`

```dart
class EditCropScreen extends StatefulWidget {
  final String imagePath;       // original JPEG (pg.imagePath)
  final CropCorners initialCorners;
  const EditCropScreen({super.key, required this.imagePath, required this.initialCorners});
}
```

- State tracks `_corners` (initialized to `initialCorners`).
- Layout: `Scaffold` with AppBar ("Edit crop", Cancel back-button) + `Stack`:
  - `Image.file(File(imagePath), fit: BoxFit.contain)`
  - `CropOverlay(corners: _corners, onCornersChanged: (c) => setState(() => _corners = c), ...)`
- Accept button in AppBar actions, key `'edit-crop-accept'`: `Navigator.of(context).pop(_corners)`.
- Cancel (back) pops with `null` (default back-button behavior).

`imageSize` for `CropOverlay` is derived from a `LayoutBuilder` wrapping the image, identical to `capture_review_screen.dart` pattern.

### `PageViewerScreen` changes

File: `lib/features/library/page_viewer_screen.dart`

New AppBar action (inserted between rename and export):

```dart
IconButton(
  key: const Key('page-viewer-edit'),
  tooltip: 'Edit crop',
  icon: const Icon(Icons.crop),
  onPressed: (_loading || _error || _exporting || (_pages?.isEmpty ?? true))
      ? null
      : () => _editCrop(_pages![_current]),
)
```

New method `_editCrop(PageImage pg)`:

```dart
Future<void> _editCrop(PageImage pg) async {
  final corners = await Navigator.of(context).push<CropCorners>(
    MaterialPageRoute(builder: (_) => EditCropScreen(
      imagePath: pg.imagePath,
      initialCorners: pg.corners,
    )),
  );
  if (corners == null || !mounted) return;
  try {
    await widget.repository.updatePageCorners(widget.documentId, pg.position, corners);
    if (!mounted) return;
    await _load();
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't update crop")),
    );
  }
}
```

Disabled state matches rename/delete: disabled when `_loading || _error || _exporting || pages empty`.

## Data Flow

```
User taps 'Edit crop' (page-viewer-edit)
  → PageViewerScreen._editCrop(pg)
    → push EditCropScreen(imagePath: pg.imagePath, initialCorners: pg.corners)
      User drags handles → CropOverlay.onCornersChanged updates _corners
      User taps Accept (edit-crop-accept)
        → Navigator.pop(context, _corners)
    → corners returned (non-null)
    → repository.updatePageCorners(documentId, pg.position, corners)
      → DriftDocumentRepository:
          load page row → read original JPEG → warp → write flat → update DB
    → _load() → getDocumentPages() → PageImage with new flatImagePath
      → InteractiveViewer shows updated displayPath
```

Cancel path: `Navigator.pop(null)` → `_editCrop` returns early, nothing changes.

## Error Handling

| Failure | Behaviour |
|---------|-----------|
| Page row not found | `updatePageCorners` throws; SnackBar "Couldn't update crop" |
| Original JPEG missing | `readAsBytes` throws; rethrow; SnackBar |
| Warp throws `WarpException` | rethrow; SnackBar; DB unchanged |
| Flat file write fails | rethrow; SnackBar; DB unchanged |
| Flat file delete fails (fullFrame) | swallow `FileSystemException`; DB still cleared |
| `_load()` after update fails | same error/retry UI as initial load |

## Testing

### Repository unit tests

Group `'E3 — updatePageCorners'` in `test/features/library/drift_document_repository_test.dart`:

1. **Non-fullFrame corners → flat written, DB updated** — create a document, call `updatePageCorners` with adjusted corners (using `FakeImageWarper` returning fixed bytes), assert `flatRelativePath` written to disk and returned in `getDocumentPages`.
2. **fullFrame corners → flat deleted, DB cleared** — pre-seed a flat, call `updatePageCorners(CropCorners.fullFrame)`, assert flat file gone and `getDocumentPages` returns `flatImagePath: null`.
3. **Warp throws → DB unchanged, method throws** — use `FakeImageWarper(shouldThrow: true)`, assert `updatePageCorners` throws and page row is unmodified.
4. **Unknown page → throws** — call `updatePageCorners` on a non-existent documentId, assert throws.

### Widget tests

Two new tests in `test/features/library/page_viewer_screen_test.dart`:

1. **Edit button present and enabled** when pages loaded — assert `Key('page-viewer-edit')` is enabled.
2. **Tapping edit button pushes EditCropScreen; accepting corners calls `updatePageCorners`** — tap `page-viewer-edit`, verify `Key('edit-crop-accept')` appears, tap it, verify `FakeDocumentRepository.lastUpdatedCorners` is set.

`FakeDocumentRepository` needs:
- `int? lastUpdatedPosition` field
- `CropCorners? lastUpdatedCorners` field
- `updatePageCorners` implementation that records args (and optionally throws if `updateGate` is set).

### BDD integration test

**`integration_test/e3_reedit.feature`:**

```gherkin
Feature: Re-edit crop
  Scenario: User re-adjusts corners on a saved document and sees the updated page
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I see the crop overlay
    And I drag the top left crop corner
    And I tap Accept
    Then I see a saved document on the home
    When I open the first document
    Then I see the page viewer
    When I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
```

**New step files:**
- `test/step/i_tap_the_edit_crop_button.dart` — taps `Key('page-viewer-edit')`, pumps.
- `test/step/i_tap_accept_on_the_viewer.dart` — taps `Key('edit-crop-accept')`, pumps.

**Reused step files (no changes):**
- `i_see_the_crop_overlay.dart` — finds `Key('crop-overlay')` (same widget, same key in pushed route).
- `i_drag_the_top_left_crop_corner.dart` — drags `Key('crop-handle-tl')` (same widget).
- `i_tap_accept.dart` — taps `Key('review-accept')` for the initial capture accept.
- `i_see_the_page_viewer.dart` — finds `Key('page-viewer-page-1')`.

**Generated:** `integration_test/e3_reedit_test.dart` (build_runner, do not edit).

### Verify script

`scripts/verify/e3.sh` — mirrors `e2.sh` structure:
- Static asserts: `updatePageCorners` on interface and impl, `EditCropScreen` file, `edit_crop_screen.dart` import in viewer, `'page-viewer-edit'` key, `'edit-crop-accept'` key, new step files, feature file, `FakeDocumentRepository.updatePageCorners`.
- Suite: `flutter test apps/mobile` (all tests, coverage floor 70%).
- Analyze: `flutter analyze`.
- Integration gate: `VERIFY_SKIP_DEVICE=1` by default; `REAL_DEVICE=1` opt-in for on-device run.
- Fail-closed on any assertion.

## Files Changed

| Action | File |
|--------|------|
| Modify | `lib/features/library/document_repository.dart` |
| Modify | `lib/features/library/drift/drift_document_repository.dart` |
| Create | `lib/features/library/edit_crop_screen.dart` |
| Modify | `lib/features/library/page_viewer_screen.dart` |
| Modify | `test/support/fake_library.dart` |
| Modify | `test/features/library/drift_document_repository_test.dart` |
| Modify | `test/features/library/page_viewer_screen_test.dart` |
| Create | `test/step/i_tap_the_edit_crop_button.dart` |
| Create | `test/step/i_tap_accept_on_the_viewer.dart` |
| Create | `integration_test/e3_reedit.feature` |
| Create | `integration_test/e3_reedit_test.dart` (build_runner) |
| Create | `scripts/verify/e3.sh` |

No schema migration. No new dependencies. `library_dependencies.dart` unchanged.
