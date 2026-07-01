# J1 Task 2 Report — Page-viewer "Export all as images" action

## Status

COMPLETE — all steps executed; commit pending below.

## Steps Executed

### Step 1: Failing test written

Created `apps/mobile/test/features/library/page_viewer_export_all_test.dart` with two `testWidgets`:
- `Export all as images shows a confirmation with the count`
- `a failing export shows an error snackbar`

### Step 2: Red — test failure confirmed

```
00:00 +0 -1: Export all as images shows a confirmation with the count [E]
  The finder "Found 0 widgets with key [<'page-viewer-export-all-images'>]: []"
  could not find any matching widgets.
00:00 +0 -2: a failing export shows an error snackbar [E]
  The finder "Found 0 widgets with key [<'page-viewer-export-all-images'>]: []"
  could not find any matching widgets.
00:00 +0 -2: Some tests failed.
```

### Step 3: `_exportAllImages()` added to `page_viewer_screen.dart`

Added near `_exportPageAsImage`. Catches `DocumentExportException` and any other error; shows "Exported N image(s)" or "Couldn't export images" snackbar.

### Step 4: `onSelected` handler + `PopupMenuItem` added

In `onSelected`: `if (v == 'export-all-images') unawaited(_exportAllImages());`
In `itemBuilder`: new `PopupMenuItem` with `key: Key('page-viewer-export-all-images')` after the `export-image` item.

### Step 5: Green — test passes

```
00:00 +1: a failing export shows an error snackbar
00:00 +2: All tests passed!
```

### Step 6: Full library group + analyze

```
00:10 +255: All tests passed!
flutter analyze --no-fatal-infos → No issues found! (ran in 3.6s)
```

## Commit Hash

(to be filled after commit)

## One-line Test Summary

2/2 new widget tests pass; 255/255 library group tests pass; `flutter analyze` clean.

## Concerns

None. The fake's `exportAllPagesAsImages` was already in place from Task 1 (commit a995ea4), so Task 2 wired cleanly. Singular/plural handled inline (`n == 1 ? 'image' : 'images'`).
