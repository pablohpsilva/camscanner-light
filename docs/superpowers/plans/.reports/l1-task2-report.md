# L1 Task 2 Report — Merge picker dialog + page-viewer wiring

## Status
COMPLETE — commit `b3d136c`

## Red → Green Summary

| Test | Red | Green |
|------|-----|-------|
| `page_viewer_merge_test.dart: Merge lists other documents and merges the chosen one` | FAIL — `page-viewer-merge` key not found | PASS |
| `page_viewer_merge_test.dart: Merge shows an empty message when there are no other documents` | FAIL — `page-viewer-merge` key not found | PASS |

**Files created/modified:**
- `lib/features/library/merge_picker_dialog.dart` (created) — `MergePickerDialog` + `showMergePicker`
- `lib/features/library/page_viewer_screen.dart` (modified) — import, `_mergeAnother()`, `if (v == 'merge')` dispatch, `page-viewer-merge` menu item after rotate
- `test/features/library/page_viewer_merge_test.dart` (created) — 2 widget tests

## Library Group Result
266/266 tests passed (`flutter test test/features/library/`)

## Analyze
`No issues found!` (`flutter analyze --no-fatal-infos`)

## Concerns / Deviations
1. **Test assertion scoped to dialog** — The plan's `expect(find.text('Alpha'), findsNothing)` assertion fails because the AppBar title "Alpha" is in the widget tree even while the dialog is open. Fixed by scoping both text assertions as `find.descendant(of: find.byKey('merge-picker-dialog'), matching: find.text(...))`. Intent preserved: verifies the dialog's list excludes the current document.
2. **Lint fix** — Renamed local function `_doc` → `makeDoc` to satisfy `no_leading_underscores_for_local_identifiers` lint rule (info, would not have been fatal but analyze reported it).
