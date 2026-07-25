# ScannerCam Light — UI batch (7 items) design

Date: 2026-07-25
Status: Approved decisions captured; pending user review of this spec
Target: next release after 1.1.3 (version chosen at ship time — 1.1.4 or 1.2.0)

## Overview

Seven mostly-independent UI fixes/improvements, plus one foundational rename.
All bound by the project's non-negotiables: TDD + BDD, verified green on Android
emulator + iOS simulator (physical-device runs are the project's standing named
gap), commit **named paths only** (never `git add -A` — the long-lived WIP pile
incl. `pubspec.yaml`), required commit trailers, preserve existing widget test
keys unless a task explicitly renames them atomically with all references.

## Locked decisions (from brainstorming)

1. Action-button overflow → **icon-only secondary buttons** (ID card, Import)
   with tooltips + semantics; keep the labeled primary Scan button. Font size
   and row height unchanged. Fixes overflow for every language, not just LB.
2. Handedness default → **right-handed (Scan on the right)**. This is a
   deliberate, visible layout change for existing users on update.
3. Filter picker → **keep per-filter thumbnails, restyled to the design system**
   (filled selected pill, high-contrast labels).
4. Live filter preview on the big image → **proxy + debounce**.
5. Swipe actions → **add `flutter_slidable`**; item 5 gets extra-careful
   interaction tests.
6. Share-link → hidden via feature-flag default flip; share-with-password added
   to the home 3-dots menu.
7. iOS Bitcoin donation → **default ON**, behind `FEATURE_IOS_BTC_DONATION`.
8. Design-system rename **"Ream" → neutral `App*`** (internal only; never
   user-facing). Plus fix the visible `appTitle` inconsistency.

## ⚠️ Named risk (accepted by owner)

**Item 7 / App Store Guideline 3.1.1.** Apple previously rejected iOS donations
(Ko-fi/BTC), which is why they are hidden on iOS today. Showing Bitcoin on iOS —
even after the tip consumables — risks another 3.1.1 rejection. The owner chose
**default ON**. Mitigation: it stays behind `FEATURE_IOS_BTC_DONATION`, so a
review-safe build can disable it via `--dart-define` with **no code change**.
Re-flag this at ship/submission time.

---

## Phase 0 — Foundational rename (runs first, serially)

The rename touches the same files as every feature lane, so it cannot run in
parallel with them. Do it first, merge, then branch all feature work off the
renamed base.

### P0-A: Rename `Ream*` → `App*` (design system)

Purely internal — verified zero user-facing occurrences (no ARB string, no
`Info.plist`/manifest label, no `Text()` widget). App launcher name stays
"ScannerCam Light".

Mechanical rename across ~67 files (~443 occurrences):

- Files: `lib/theme/ream_colors.dart` → `app_colors.dart`,
  `ream_theme.dart` → `app_theme.dart`,
  `ream_typography.dart` → `app_typography.dart`,
  `widgets/ream_action_button.dart` → `app_action_button.dart`,
  `widgets/ream_back_header.dart` → `app_back_header.dart`,
  `widgets/ream_search_field.dart` → `app_search_field.dart`,
  `widgets/ream_section_label.dart` → `app_section_label.dart`,
  `widgets/ream_segmented.dart` → `app_segmented.dart`.
- Types: `ReamColors`→`AppColors`, `ReamTheme`→`AppTheme`,
  `ReamTypography`→`AppTypography`, `ReamActionButton`→`AppActionButton`,
  `ReamBackHeader`→`AppBackHeader`, `ReamSearchField`→`AppSearchField`,
  `ReamSectionLabel`→`AppSectionLabel`, `ReamSegment`→`AppSegment`,
  `ReamSegmented`→`AppSegmented`.
- Accessor: `extension ReamColorsX` → `AppColorsX`; getter `context.ream` →
  `context.appColors` (~24 call sites).
- Constants/fns: `kReamScrimStrong/Medium`→`kAppScrimStrong/Medium`,
  `kReamCardShadow`→`kAppCardShadow`, `reamInkOnFill`→`appInkOnFill`.
- Test helper: `test/support/ream_pump.dart` → `app_pump.dart`,
  `pumpReam` → `pumpApp` (~12 files).
- Widget key: `Key('ream-back')` → `Key('back')` — rename atomically with all 7
  test references.
- Update all imports (~30 lib files, ~37 test files).

**Verify:** `flutter analyze` clean; full host suite green (baseline
`+1094 ~2 0-fail`). No behavior change — the test suite is the safety net.

### P0-B: Fix visible in-app title (parallel with P0-A — different files)

`appTitle` is `"CamScanner-light"` in all 11 ARBs but the launcher name is
"ScannerCam Light". Change `appTitle` → `"ScannerCam Light"` in `app_en.arb`
and every `app_*.arb`. Update any test asserting the old title.

---

## Phase 1 — Feature lanes (parallel off the renamed base)

### Lane A — Home action row + handedness (items 1, 2)

- **A1** `app_action_button.dart`: add an **icon-only mode** (label optional →
  rendered as `Tooltip` + `Semantics` label instead of visible `Text`); add
  defensive `maxLines: 1` on the primary label. Widget tests for both modes.
- **A2** New `HandednessStore` (SharedPreferences key `handedness`) +
  `HandednessController extends ChangeNotifier`, mirroring
  `ThemeController`/`LocaleController` exactly. Store + controller unit tests
  (copy `theme_mode_store_test` / `theme_controller_test`).
- **A3** Wire handedness `main.dart` → `runCamScannerApp` → `CamScannerApp`
  (add to the `Listenable.merge`) → `HomeScreen`. In `_buildActionRow`: render
  ID card + Import icon-only (A1), and order the row so primary Scan sits on the
  handed side (default right). Handedness is applied as explicit logical order
  **after** Flutter's automatic RTL flip — assert Arabic + handedness compose
  without double-flipping. Depends A1, A2.
- **A4** `settings_screen.dart`: 2-segment `AppSegmented` (Left/Right) under a
  new section label, copying the theme-toggle pattern. Settings widget test +
  a new `*.feature` BDD (shape of `t1_theme_settings.feature`). Depends A2.
  (Different file from A3 → parallel after A2.)

### Lane B — Review filter (items 3, 4)

- **B1** `filter_picker_strip.dart`: restyle to design-system tokens
  (`context.appColors`) — themed surface, high-contrast labels, **filled
  selected pill**; keep the per-filter thumbnails. Preserve keys
  (`filter-picker-strip`, `filter-tile-*`). Update `filter_picker_strip_test`.
- **B2** `capture_review_screen.dart`: live preview on the big image — on filter
  change (debounced), run `enhancerForMode(mode).enhance()` on a downsized proxy
  (~1080px long side), swap the large widget to `Image.memory` under the crop
  overlay, spinner while computing; full-res enhance still only on Accept. Also
  wrap the strip in the design-system theme scope so it matches EditFilterScreen.
  Preserve `review-image`/`review-accept`/`crop-reset` keys. Tests updated.
- **B3** `edit_filter_screen.dart`: same live-preview treatment (proxy +
  debounce + `Image.memory` + spinner) on the base image. Tests updated.

  (B1 = strip file only; B2 = capture-review file; B3 = edit-filter file →
  three distinct files, fully parallel.)

### Lane C — Home list swipe + menu (items 5, 6)

- **C1** Add `flutter_slidable` to `pubspec.yaml` (single named line) +
  `flutter pub get`. Unblocks C5.
- **C2** Copy-text document-level use case: repository method to fetch a
  document's page OCR text, concatenate, copy to clipboard, snackbar. New file +
  repository method + unit tests (OCR text already lives in the FTS index).
- **C3** Document-level "protect with password" handler reusing
  `showPasswordDialog` + the existing protect pipeline. Unit/widget tests.
- **C4a** `feature_flags.dart`: flip `FEATURE_SHARE_LINK` default `true → false`
  (keep the flag). Update its test. (1-line, independent.)
- **C4b** `documents_list_view.dart` 3-dots menu: add **Share with password**
  (`ShareActionKind.protect`, gated by `protectWithPassword`); share-link now
  hidden via C4a. Tests. (Same file as C5 → sequence C4b then C5.)
- **C5** `documents_list_view.dart` **slidable rows** (`flutter_slidable`):
  swipe-left → **Delete with confirm dialog** (no immediate delete);
  swipe-right → reveal **Rename · Copy text · Share · Share with password**;
  3-dots menu kept for non-swipe. Grid view unchanged (list only).
  **Extra-careful tests** (owner's explicit ask): swipe-left reveals+confirms
  delete, cancel aborts, swipe-right reveals each action and each fires the
  right handler, 3-dots still works, keys preserved. Widget tests + a dedicated
  `*.feature` BDD. Depends C1, C2, C3, C4b.

### Lane D — Donation Bitcoin on iOS (item 7)

- **D1** New `FEATURE_IOS_BTC_DONATION` (default **true**), injected into
  `DonationScreen` like `tipJarMode` (constructor param defaulted from
  `bool.fromEnvironment`, threaded through `DonationScreen.route`). In the iOS
  tip-jar branch, append the existing `_BitcoinSection` (QR + copy, reuse
  `_copyAddress`) **after** `TipJarBody`, guarded by
  `iosBtcDonation && bitcoinAddress.isNotEmpty`. Tests: body-selection +
  wiring; a `*.feature` BDD for "iOS shows BTC after tips when enabled".

---

## Dependency graph (for parallel dispatch)

```
Phase 0:  P0-A ─┐   P0-B (parallel, different files)
                └─► merge → renamed base
Phase 1 (all off renamed base):
  A1 ─┐
  A2 ─┼─► A3            Lane A
      └─► A4
  B1   B2   B3          Lane B (fully parallel)
  C1 ─► C5
  C2 ─► C5              Lane C
  C3 ─► C5
  C4a  C4b ─► C5
  D1                    Lane D (independent)
```

Lanes A, B, C, D are mutually independent (disjoint files). Within a lane,
only the noted dependencies serialize.

## Testing (per task, non-negotiable)

Each task: failing test first (TDD), minimal impl, green; user-facing behavior
gets a `.feature` + generated test + shared steps (BDD), regenerated with
`build_runner`. Native-independent UI verified on host; the swipe, live-preview,
handedness, and donation flows additionally verified on Android emulator + iOS
simulator. Physical devices = standing named gap.

## Known gaps / notes

- Version bump deferred to ship time; keeps this batch separate from the pending
  1.1.3 auto-filter IPA (still awaiting Apple Distribution sign-in for export).
- Item 7 App Store 3.1.1 risk (above) — re-flag at submission.
- `flutter_slidable` is a new dependency (owner-approved for item 5).
