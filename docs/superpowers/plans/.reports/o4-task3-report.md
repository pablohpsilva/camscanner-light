# O4 Task 3 Report — Wire "View text" into the page viewer

## Status
COMPLETE

## Commit
65d0061 — feat(o4): page viewer 'View text' opens recognized-text screen

## Red → Green (new test: page_viewer_view_text_test.dart)

**Red (before implementation):**
```
00:00 +0 -1: View text opens the recognized-text screen for the current page [E]
The following assertion was thrown running a test:
The finder "Found 0 widgets with key [<'page-viewer-view-text'>]: []" (used in a call to "tap()")
could not find any matching widgets.
```

**Green (after implementation):**
```
00:00 +0: View text opens the recognized-text screen for the current page
00:00 +1: All tests passed!
```

## Full library test group result
```
00:07 +242: All tests passed!
```
242 tests, all pass.

## flutter analyze
```
Analyzing mobile...
No issues found! (ran in 3.6s)
```

## Changes made
- `apps/mobile/lib/features/library/page_viewer_screen.dart`:
  - Added `import 'recognized_text_screen.dart';`
  - Added `_viewText()` method that pushes `RecognizedTextScreen` for the current page
  - Added `if (v == 'view-text') _viewText();` to `onSelected`
  - Added `PopupMenuItem` with key `page-viewer-view-text` and value `'view-text'` as the first item in `itemBuilder`
- `apps/mobile/test/features/library/page_viewer_view_text_test.dart` (created):
  - Single widget test asserting the "View text" menu item navigates to `RecognizedTextScreen` and renders the page's `ocrText`

## Concerns
None. The test uses a non-loadable `/x.jpg` image path, maintaining the established pattern for host tests (no Image.file hang). All 242 library tests pass with no regressions.
