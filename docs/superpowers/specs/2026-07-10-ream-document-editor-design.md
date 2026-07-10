# Ream redesign — Phase 2a: Document editor (screen 06)

**Date:** 2026-07-10
**Source design:** `Ream Scanner.dc.html` screen **06 · Document editor** (direction
1a). Local copy + tokens: `docs/design/ream/` (read first).
**Scope:** re-skin `PageViewerScreen` (the document editor / page viewer) to the
Ream design. One screen; its own TDD/BDD cycle. Part of Phase 2 (per-screen
re-skins) in the roadmap established by the Phase-1 spec.

## Decisions (locked with the user)

- **Dark viewer.** The editor is a per-screen **dark** surface (near-black, so the
  page pops), regardless of the app's light theme mode — implemented by wrapping
  the editor subtree in `Theme(data: ReamTheme.dark())`. The rest of the app stays
  light; the app-wide dark theme is still deferred to the final phase.
- **6-icon bottom toolbar + `⋯` overflow**, nothing lost. Toolbar: Crop, Rotate,
  Text, Retake, Share, Delete (red). Overflow: everything else.
- **Share** (toolbar) opens the existing share/export menu (PDF, image, all-images,
  print, protect, link, fax). **Delete** (toolbar, red) = delete **page**.
  Delete-**document** moves to the overflow.
- **Donation banner removed from the editor** (the toolbar owns the bottom; the
  design shows no banner here; it stays on the Library home). The one wiring test
  asserting the banner in the page viewer is updated.
- **`+` add-page in the thumbnail strip is deferred** — pure re-skin this cycle.

## Design language (screen 06)

Dark surface (`ReamColors.dark`: `paper #16130E`, `surface #211D16`,
`ink #F4F1EA`, `muted #8F887A`, `line #322C22`), `green #4FA866` for active
accents, `deleteRed #F47B74` for Delete. Figtree for the title/labels; IBM Plex
Mono for the page counter. Rounded, hairline-bordered dark tiles.

## Architecture

- **Theme scoping.** Wrap the editor's `Scaffold` in `Theme(data: ReamTheme.dark())`
  so `context.ream` inside the editor resolves to dark tokens and stock Material
  chrome adapts. Consequences (intended):
  - **Dialogs** launched from the editor (delete-confirm, rename, export-quality,
    password, merge-picker) inherit the dark theme via Flutter's captured-themes
    mechanism — coherent with the dark editor.
  - **Pushed full screens** (EditCropScreen 04, RecognizedTextScreen 07,
    PdfPreviewScreen 08, ScanScreen) build under the app's **light** theme — they
    remain light until their own Phase-2 cycles. Named, accepted inconsistency.
- **System UI.** While the editor is shown, set `SystemUiOverlayStyle.light`
  (light status-bar icons over the dark surface); restore the prior style on pop
  (use an `AnnotatedRegion<SystemUiOverlayStyle>` around the editor so it reverts
  automatically when the route is covered/popped).
- **Dark-palette validation.** `ReamColors.dark` was extrapolated from the 1b
  mockups and never rendered. This task is the first real use — it includes
  **validating and, if needed, tuning** the dark tokens on-device (contrast of
  `ink`/`muted`/`line` on `paper`/`surface`; green/red legibility). Any token
  change lands in `ream_colors.dart` (dark set) with the existing token test
  updated.

## Components

New, under `lib/features/library/widgets/`:
- **`EditorTopBar`** — dark bar: `‹` back (`page-viewer-back`), centered title,
  `⋯` overflow (keeps `page-viewer-page-menu` + its item keys).
- **`EditorToolbar`** — the 6-item bottom bar; **`EditorToolbarButton`**
  (icon-over-label, optional `danger` color for Delete, disabled state).
- **`PageCounterPill`** — "N / M" mono pill overlaid top-right of the viewer
  (shown when page count > 1), key `page-viewer-page-counter`.
Restyle:
- **`PageThumbnailStrip`** — already dark (black bg); change the active-tile
  border to `context.ream.green`; keep bg on the dark surface; **preserve keys**
  `page-thumbnail-strip`, `page-thumb-$index`, `page-thumb-item-$index`.

## Action mapping (all preserved; keys kept)

| Action | Where now | Where after | Key (unchanged unless noted) |
|--------|-----------|-------------|------------------------------|
| Crop | app-bar icon | toolbar | `page-viewer-edit` |
| Rotate | overflow | toolbar | `page-viewer-rotate` |
| Text (OCR) | overflow | toolbar | `page-viewer-view-text` |
| Retake | overflow | toolbar | `page-viewer-retake` |
| Share | (new) | toolbar → opens share/export menu | `page-viewer-share` (new) |
| Delete page | overflow | toolbar (red) | `page-viewer-delete-page` |
| Rename | app-bar icon | overflow | `page-viewer-rename` |
| Export PDF | app-bar icon | overflow | `page-viewer-export` |
| Delete document | app-bar icon | overflow | `page-viewer-delete` |
| Merge / Split / Print / Protect / Share-image / Share-all / link / fax | overflow | overflow (unchanged) | existing keys |

The five actions moving **out of** the overflow (Crop, Rotate, Text, Retake,
Delete-page) are **removed** from the overflow (no duplication). Everything else
in the overflow is unchanged.

## Behavior preserved (must stay green)

Load / error+retry / empty states (`page-viewer-loading`, `page-viewer-error`,
`page-viewer-retry`, `page-viewer-empty`); `PageView` pinch-zoom/pan; page-change
tracking; every action's repository call and error snackbar; delete-page clamp +
reload + jump; rotate cache-clear; reorder persist; retake→replacePage;
crop→updatePageCorners; export/print/protect/merge/split/text nav; the
`_exporting` disable-guards.

## Testing

**Host (TDD, `flutter test`).** New widget tests for `EditorToolbar` /
`EditorToolbarButton` / `PageCounterPill` / `EditorTopBar`, and the restyled
strip's green active border. Then the **test migration**:
- **Shared BDD steps** are the leverage point: update `i_rotate_the_page`,
  `i_open_the_text_view`, `i_delete_the_current_page`, the retake step (h4), and
  the crop/re-edit step to tap the **toolbar** button directly (drop the
  "open overflow first" tap). This fixes the feature layer for all 12 viewer
  features at once.
- **Host test files** (`page_viewer_rotate_test`, `page_viewer_view_text_test`,
  `page_viewer_h4_test`, `page_viewer_screen_test`, `delete_page_test`, and any
  other that reaches Crop/Rotate/Text/Retake/Delete-page via the overflow) drop
  the overflow tap and target the toolbar button (keys unchanged). Tests for
  overflow-resident actions (split/merge/print/protect/export/rename/export-pdf/
  delete-document) are unchanged.
- Update the donation wiring test that asserts the banner in the page viewer
  (banner is now removed from the editor).

**Device (real Android + iOS sim, per the non-negotiable).** Run the viewer BDD
features (`k1_rotate_page`, `h4_delete_retake`, `h2_page_thumbnail_strip`,
`h3_page_reorder`, `b3_view_and_delete`, `o4_recognized_text` where relevant) on
the real Android device and the iOS 18.3 simulator. This run is also the
**dark-palette visual validation** — capture a screenshot per platform and tune
`ReamColors.dark` if contrast is poor. Real iOS hardware remains a named gap.

## Non-goals

Re-skinning Crop (04) / OCR (07) / PDF-preview (08) / Scan screens (their own
cycles); the `+` add-page affordance; app-wide dark theme go-live; any behavior
change to the actions themselves.

## Definition of done

TDD host tests green; `flutter analyze` clean (no new issues); all viewer host
tests + BDD features green on host; device runs green on Android + iOS sim with a
dark-palette screenshot per platform; exact commands + output reported before
claiming done.
