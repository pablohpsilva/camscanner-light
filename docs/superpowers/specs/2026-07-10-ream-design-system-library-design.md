# Ream visual redesign — Phase 1: Design System + Library

**Date:** 2026-07-10
**Source design:** `Ream Scanner.dc.html` (Claude Design project
`b1f98d43-afb3-4442-9c2b-f8d1787c2cbc`, direction **1a — warm & clean**).
**Scope of this spec:** the themable design system + the Library (Home) screen
re-skin, list **and** grid. Other screens are later cycles (see Roadmap).

**Implementer reference (read first):** `docs/design/ream/README.md` — committed
design markup (`Ream Scanner.dc.html`), the exact oklch→sRGB color-token table,
type rules, screen→file index, and the per-task definition of done. Subagents
must consult it before writing code.

## Decisions (locked with the user)

- **Themable, light-first.** Build a theme that supports light + dark; implement
  and verify the **1a warm & clean light** theme now. The **dark** theme is
  extrapolated from the 1b "scanner HUD" screens but is only wired/verified in
  the final phase.
- **No rename.** Keep the app name/identity ("CamScanner-light", bundle ids,
  store listing). Apply the Ream *visual style* only. Do **not** rename the app
  or churn store assets. Visible copy stays as-is except where a restyle
  naturally touches it; we do not introduce the literal word "Ream" into UI copy
  in this phase.
- **Sequence:** design system + Library first (this spec), then one re-skin
  cycle per remaining screen, then a final app-wide "apply the redesign" phase.
- **Inline search**, as designed (replaces today's tap-to-open AppBar search
  mode).
- **Go live in Phase 1:** `MaterialApp` switches to the Ream light theme now; the
  redesigned Library is what launches. Later screens go live as re-skinned.
- **Review & clean (screen 04)** is an in-app editor to redesign — but in a
  **later** cycle, not this one.
- **Scanning/capture screens (03, 05, 1b capture HUD) are out of scope** — the
  app uses the OS document scanner for capture.

## Design language (from 1a)

- **Palette (light):** `paper #f4f1ea`, `surface #fffdf8`, `surface2 #faf7f0`,
  `ink #33302a`, `ink2 #5c574d`, `muted #928c80`, `line #e6e1d6`,
  `line2 #efebe2`. **Confidence trio:** `green oklch(0.66 0.13 150)`,
  `amber oklch(0.70 0.13 78)`, `blue oklch(0.66 0.12 245)`, each with a `-deep`
  and `-soft` variant (see the `.dc.html` `:root`). App background behind the
  paper surface is `#e7e3d9`.
- **Type:** **Figtree** (400/500/600/700/800) for UI; **IBM Plex Mono**
  (400/500/600) for technical readouts (page counts, dates, IDs, confidence
  numbers). Titles are Figtree 800 with tight tracking (`-.02em`).
- **Shape:** generously rounded (cards 13–15px, pills 9–20px), soft shadows,
  1px hairline borders in `line`. Primary action is `green-deep` filled.

## Architecture

New directory **`lib/theme/`**:

- **`ream_colors.dart`** — `ReamColors extends ThemeExtension<ReamColors>` with a
  field per semantic token above (all as `Color`; oklch values converted to
  sRGB `Color` constants at authoring time). Provides `ReamColors.light` and
  `ReamColors.dark`, plus `lerp`/`copyWith`. A `BuildContext.ream` extension
  getter returns `Theme.of(context).extension<ReamColors>()!` for terse access.
  - *What it does:* single source of truth for semantic colors.
  - *How you use it:* `context.ream.green`, `context.ream.paper`, etc.
  - *Depends on:* nothing (pure data).
- **`ream_typography.dart`** — builds the Figtree `TextTheme` and exposes a
  `ReamText` helper / `mono(...)` `TextStyle` factory for IBM Plex Mono readouts.
- **`ream_theme.dart`** — `ReamTheme.light()` / `ReamTheme.dark()` returning
  `ThemeData`: maps `ReamColors` onto `ColorScheme` (so stock Material widgets
  inherit sensible colors), sets `scaffoldBackgroundColor`, `textTheme`, and
  `extensions: [ReamColors.light|dark]`. `useMaterial3: true` retained.
- **Fonts:** add `fonts/Figtree-*.ttf` and `fonts/IBMPlexMono-*.ttf`
  (OFL-licensed) and declare them under `flutter: fonts:` in `pubspec.yaml`.
  Bundled (not runtime-fetched) — the app is offline/private by design. Font
  files are downloaded from Google Fonts (OFL) as an implementation step.

New reusable widgets in **`lib/theme/widgets/`** (each independently
widget-testable, reused by later screens):

- `ConfidenceChip({ConfidenceLevel level, String label})` — green/amber/blue pill
  with a leading dot. (Built now as a core primitive; used heavily by later
  capture/review/OCR screens.)
- `ReamSearchField` — inline search input matching the header style.
- `ReamSegmented` — two/three-segment toggle (List/Grid; also the sort pill's
  visual base).
- `ReamActionButton` — the bottom-row buttons (primary filled + secondary
  outlined variants) for Scan / ID card / Import.
- Document **row** and **grid card** widgets (paper thumbnail framing + title +
  mono meta line).

## Library (Home) screen — target structure

Replaces the Material `AppBar` + FAB with the designed layout. `HomeScreen`
state and data flow (`DocumentRepository`, cold-start watchdog, sort, search,
selection, import/scan/id navigation) are **preserved**; only presentation and
the search interaction change.

- **Header (custom, not `AppBar`):**
  - Title "Documents" (Figtree 800), subtitle "Private · on this device" with a
    small lock glyph.
  - **Settings gear** top-right → opens a menu that includes **Send feedback**
    (preserving today's overflow-menu entry; gated by `_feedbackAvailable` as
    now). This keeps the existing feedback path reachable.
  - **Inline `ReamSearchField`** (always visible). Typing drives the existing
    FTS search (`repo.searchDocuments`) with the current race-guard. Empty query
    restores the full list. No separate "search mode" AppBar.
  - Controls row: **sort pill** + **List/Grid `ReamSegmented` toggle**. The sort
    pill shows the active criterion + a direction arrow (e.g. "Modified ↓") and
    opens a small menu listing Name / Created / Modified. Selecting a criterion
    calls the existing `nextSort` (re-selecting the active one toggles
    direction), so `document_sort.dart` and its semantics are unchanged — only
    the presentation moves from three `ChoiceChip`s to a pill + menu. The
    `d3_sort` BDD step "I tap the sort chip {name}" is adapted to open the pill
    and pick that criterion.
- **Body:** `DocumentsListView` (restyled) when list mode; a new
  `DocumentsGridView` (2-column cards, `aspect-ratio .77`) when grid mode.
  View-mode state lives in `HomeScreen`, **in-memory** for now (persistence is a
  YAGNI follow-up). Empty and error/loading states restyled to paper.
- **Bottom:** a **3-button action row** — primary green **Scan**, **ID card**,
  **Import** (replacing the extended FAB + the app-bar scan-id/import icons) —
  above the restyled **amber donation banner** (`DonationBanner`).

### Behavior preserved (must stay green)
Cold-start watchdog + named startup failure; sort model + persistence of the
active sort within a session; FTS content search; multi-select + export;
rename/share per-row menus; donation banner → donation screen; feedback entry
when available; scan/id/import navigation.

### Keys / tests impacted
Restructuring moves several actions, so these host tests are **updated
failing-first** to the new structure: `home_screen_test`, `home_search_test`,
`home_scan_id_test`, `home_screen_import_test`, `home_feedback_menu_test`,
`home_multi_export_test`, `home_share_test`, `documents_list_view_test`,
`document_sort` UI touchpoints. Widget keys that tests rely on are re-homed onto
the new controls (e.g. the scan-id/import actions move from the app bar to the
bottom row but keep stable keys like `home-scan-id`, `home-import`; search moves
to `documents-search-field`; add `documents-grid`, `library-view-toggle`).

## Testing plan (both platforms — non-negotiable)

**TDD (host, `flutter test`):**
- `ream_colors_test` — light/dark expose all tokens; `lerp` interpolates; the
  `context.ream` getter resolves from a themed context.
- `ream_theme_test` — `ThemeData` carries the extension; scaffold background =
  paper; `ColorScheme` mapping sane.
- Component tests: `confidence_chip_test` (three levels render their color +
  label), `ream_search_field_test`, `ream_segmented_test`,
  `ream_action_button_test`, `document_grid_view_test`, restyled
  `donation_banner` test.
- Updated `HomeScreen` host tests (above) for the new header, inline search,
  list/grid toggle, and bottom action row.

**BDD (`.feature` in `integration_test/`, steps in `test/step/`):**
- Keep green (adapt steps to new controls): `d3_sort`, `s1_donation_banner`,
  `o5_content_search`, `i2_gallery_import`, `id_scan`, `b2_restart_persistence`.
- New: `ui1_library_grid_toggle.feature` (switch list↔grid; a saved document
  appears in both), and coverage that Scan/ID/Import are reachable from the
  bottom action row + inline search filters the list.
- Regenerate with `dart run build_runner build --delete-conflicting-outputs`.

**Device (real Android + real iOS):**
- Run the library `integration_test/*_test.dart` features on a real Android
  device and a real iOS device with `-d <device-id>`. Native deps exercised:
  drift/sqlite, JPEG thumbnail decode. Report the exact commands + green output
  before claiming done. Any unavailable lane is named explicitly, never silent.

## Non-goals (this phase)
Re-skinning any non-Library screen; the dark theme go-live; view-mode
persistence; capture/ID scan screens; renaming the app; store assets.

## Roadmap

1. **Phase 1 (this spec):** design system + Library (list + grid), live on the
   Ream light theme, green on host + real Android + real iOS.
2. **Phases 2…N:** one re-skin cycle each (own spec/plan/TDD/BDD): Document
   editor (06), Recognized text/OCR (07), Export PDF (08), Send feedback (09),
   Support/Donation (10), Review & clean editor (04).
3. **Final phase — "apply the redesign":** switch the whole app onto the Ream
   theme app-wide, wire + verify the **dark** theme, and run a cross-screen
   consistency/polish pass with a full-app device regression on both platforms.
