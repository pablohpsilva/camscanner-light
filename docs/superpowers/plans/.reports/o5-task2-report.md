# O5 Task 2 Report — Home screen search mode

## Status

DONE — all steps 1–8 complete.

## Commit

`49aadff` — `feat(o5): home search mode — live filter, clear, close, empty state`

## Red-then-green

**Red (Step 2):** `flutter test test/features/library/home_search_test.dart`
```
00:00 +0 -4: Some tests failed.
  Could not find widget with key 'documents-search' — all 4 tests failed.
```

**Green (Step 6):** `flutter test test/features/library/home_search_test.dart`
```
00:00 +4: All tests passed!
```

## Library group result (Step 7)

`flutter test test/features/library/` → **251 tests passed** (0 failures, 0 skips).
Includes all existing `home_screen_test.dart` tests — no regressions.

## Analyze

`flutter analyze --no-fatal-infos` → **No issues found!** (ran in 3.5s)

## Changes made

### `apps/mobile/lib/features/library/home_screen.dart`
- Added `_searchController` (`TextEditingController`), `_searching` (`bool`), `_query` (`String`) fields.
- Added `dispose()` that disposes `_searchController`.
- Added `_openSearch`, `_closeSearch`, `_onQueryChanged` (race-guarded), `_refresh` methods.
- Changed the three post-push `await _load()` calls (in `_openScan`, `_openDocument`, `_renameDocument`) to `await _refresh()`.
- Replaced `build` with search-aware version: toggles between `_buildNormalAppBar` (search icon `documents-search`) and `_buildSearchAppBar` (back `documents-search-close`, field `documents-search-field`, clear `documents-search-clear`); hides FAB and `SortControlBar` while searching; shows `documents-search-empty` on non-empty query with no results.

### `apps/mobile/test/features/library/home_search_test.dart` (new)
- 4 widget tests covering: live filter, clear restores full list, no-match empty state, close restores sort bar.

## Concerns

None. The `pumpAndSettle` works correctly because `_onQueryChanged` completes synchronously in the fake (no timer/debounce). The race guard (`value != _query`) is in place for production async use.
