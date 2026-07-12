# Ream Document Editor Re-skin — Implementation Plan (Phase 2a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin `PageViewerScreen` (the document editor) to the Ream design —
a dark viewer with a custom top bar, a 6-icon bottom toolbar, a page-counter pill,
a green-active thumbnail strip, and all existing actions preserved.

**Architecture:** Wrap the editor subtree in `Theme(ReamTheme.dark())` so
`context.ream` resolves to dark tokens; build small dark toolbar/topbar/counter
widgets (reusing the Phase-1 design system); restructure `PageViewerScreen` to
compose them; migrate the viewer's host tests + shared BDD steps to the relocated
controls.

**Tech Stack:** Flutter, the Ream design system (`lib/theme/`), `bdd_widget_test`.

## Global Constraints

Copied from `docs/superpowers/specs/2026-07-10-ream-document-editor-design.md` and
`docs/design/ream/README.md`. **Every task implicitly includes this.**

- Run all Flutter commands from `apps/mobile/`. Package name `mobile`.
- The editor is **dark**: wrap its `Scaffold` in `Theme(data: ReamTheme.dark())`.
  Widgets read colors via `context.ream` (dark tokens: `paper #16130E`,
  `surface #211D16`, `ink #F4F1EA`, `muted #8F887A`, `line #322C22`,
  `green #4FA866`, `deleteRed #F47B74`). Widget tests pump with
  `pumpReam(tester, child, theme: ReamTheme.dark())`.
- **No behavior change** to any action; **preserve all widget keys** (see the
  mapping). No literal "Ream" in UI copy. Fonts: Figtree UI / IBMPlexMono readouts.
- **Action mapping** (keys unchanged): toolbar = Crop `page-viewer-edit`, Rotate
  `page-viewer-rotate`, Text `page-viewer-view-text`, Retake `page-viewer-retake`,
  Share `page-viewer-share` (new; opens the share/export menu), Delete-page
  `page-viewer-delete-page` (red). Share menu = Export-PDF `page-viewer-export`,
  Share-image `page-viewer-export-image`, Share-all `page-viewer-export-all-images`,
  Print `page-viewer-print`, Protect `page-viewer-protect`, + share-extras
  (link/fax). Overflow `page-viewer-page-menu` = Rename `page-viewer-rename`,
  Merge `page-viewer-merge`, Split `page-viewer-split`, Delete-document
  `page-viewer-delete`. Back button `page-viewer-back` (new).
- **Donation banner removed** from the editor.
- **TDD** (test-first, real assertions), `flutter analyze` clean on changed files,
  `dart format`. **Scoped commits** (`git add <paths>`, NEVER `-A` — the tree has
  a long-lived unrelated WIP pile). On `index.lock`, wait 3s + retry. Commit
  trailers:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Lw79qoRinSfhgDMmUbJJWi`
- **Verify, then claim**: paste FAIL→PASS + analyze output. Device-dependent
  behavior needs a real Android + iOS(sim) run — or a named gap. No "should work".

---

## Parallelization map

| Wave | Tasks | Parallel? |
|------|-------|-----------|
| **1 Widgets** | 1 EditorToolbarButton · 2 PageCounterPill · 3 EditorTopBar · 4 PageThumbnailStrip restyle · 5 EditorToolbar | 1–4 **parallel** (disjoint new files; 4 modifies the strip + its test). 5 after 1. |
| **2 Integration** | 6 PageViewerScreen restructure + host-test migration | single owner, serial (big). |
| **3 Verify** | 7 BDD step migration + regen · 8 device + dark-palette validation | 7 then 8. |

**Strict subagent contract:** identical to Phase 1 — read `docs/design/ream/README.md`
+ your brief first; own only your files; TDD order with pasted FAIL→PASS; real
assertions (no `skip:`/filler); `flutter analyze` clean; scoped commit; report the
commands, output, SHA, and any named gap; never claim done with an open gap.

---

## Task 1: `EditorToolbarButton`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/editor_toolbar_button.dart`
- Test: `apps/mobile/test/features/library/editor_toolbar_button_test.dart`

**Interfaces:**
- Consumes: `context.ream`, `pumpReam` (`test/support/ream_pump.dart`).
- Produces: `class EditorToolbarButton extends StatelessWidget` —
  `EditorToolbarButton({required IconData icon, required String label,
  VoidCallback? onPressed, bool danger = false, Key? key})`. Icon over label,
  vertical, dark. Enabled color `context.ream.ink`; `danger` → `context.ream.deleteRed`;
  `onPressed == null` → dimmed (`context.ream.muted`), non-tappable.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/features/library/widgets/editor_toolbar_button.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('renders icon+label and fires onPressed', (tester) async {
    var taps = 0;
    await pumpReam(tester, EditorToolbarButton(
      key: const Key('tb-rotate'), icon: Icons.rotate_right, label: 'Rotate',
      onPressed: () => taps++), theme: ReamTheme.dark());
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
    await tester.tap(find.byKey(const Key('tb-rotate')));
    expect(taps, 1);
  });

  testWidgets('danger uses deleteRed', (tester) async {
    await pumpReam(tester, EditorToolbarButton(
      icon: Icons.delete_outline, label: 'Delete', danger: true,
      onPressed: () {}), theme: ReamTheme.dark());
    final icon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
    expect(icon.color, ReamColors.dark.deleteRed);
  });

  testWidgets('null onPressed dims and does not fire', (tester) async {
    await pumpReam(tester, const EditorToolbarButton(
      key: Key('tb-x'), icon: Icons.crop, label: 'Crop', onPressed: null),
      theme: ReamTheme.dark());
    await tester.tap(find.byKey(const Key('tb-x')));
    expect(find.text('Crop'), findsOneWidget); // no throw
  });
}
```

- [ ] **Step 2: Run — expect FAIL.** `cd apps/mobile && flutter test test/features/library/editor_toolbar_button_test.dart`
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';

/// One item in the dark editor toolbar: an icon over a small label. [danger]
/// tints it red (Delete); a null [onPressed] dims and disables it.
class EditorToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  const EditorToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final enabled = onPressed != null;
    final color = !enabled ? r.muted : (danger ? r.deleteRed : r.ink);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(
            fontFamily: 'Figtree', fontSize: 10, fontWeight: FontWeight.w600,
            color: color)),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): EditorToolbarButton`).

---

## Task 2: `PageCounterPill`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/page_counter_pill.dart`
- Test: `apps/mobile/test/features/library/page_counter_pill_test.dart`

**Interfaces:**
- Produces: `class PageCounterPill extends StatelessWidget` —
  `PageCounterPill({required int current, required int total, Key? key})`.
  Renders "current/total" (1-based) in an `IBMPlexMono` pill on a translucent
  dark background. Root `key` defaults are the caller's; the widget itself has no
  fixed key (caller supplies `page-viewer-page-counter`).

- [ ] **Step 1: Failing test** — pump `PageCounterPill(current: 2, total: 6)` via
  `pumpReam(..., theme: ReamTheme.dark())`; assert `find.text('2 / 6')` findsOne.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';
import '../../../theme/ream_typography.dart';

/// A small "N / M" page-counter pill overlaid on the editor viewer.
class PageCounterPill extends StatelessWidget {
  final int current; // 1-based
  final int total;
  const PageCounterPill({super.key, required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      child: Text('$current / $total',
          style: ReamTypography.mono(size: 11, weight: FontWeight.w600, color: r.ink)),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): PageCounterPill`).

---

## Task 3: `EditorTopBar`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/editor_top_bar.dart`
- Test: `apps/mobile/test/features/library/editor_top_bar_test.dart`

**Interfaces:**
- Produces: `class EditorTopBar extends StatelessWidget implements PreferredSizeWidget`
  — `EditorTopBar({required String title, VoidCallback? onBack, Widget? trailing,
  Key? key})`. A dark bar with a back button (`key: Key('page-viewer-back')`,
  `Icons.arrow_back_ios_new`, calls `onBack`), a centered title (Figtree 700,
  `context.ream.ink`, ellipsis), and an optional `trailing` (the overflow menu).
  `preferredSize => const Size.fromHeight(kToolbarHeight)`. Use it as the
  Scaffold `appBar`.

- [ ] **Step 1: Failing test** — pump inside a `Scaffold(appBar: EditorTopBar(...))`
  via a dark-themed MaterialApp; assert the title text shows, `page-viewer-back`
  is present and tapping it fires `onBack`, and a provided `trailing` widget renders.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** a `PreferredSizeWidget` returning a `SafeArea` + `Row`
  (back / `Expanded` centered title / trailing-or-spacer) on `context.ream.paper`,
  height `kToolbarHeight`.
- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): EditorTopBar`).

---

## Task 4: Restyle `PageThumbnailStrip` active border  *(Wave 1 — parallel; modifies existing)*

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart`
- Modify: `apps/mobile/test/features/library/widgets/page_thumbnail_strip_test.dart` (if present; else add a small test)

**Interfaces:**
- Unchanged public API + keys (`page-thumbnail-strip`, `page-thumb-$index`,
  `page-thumb-item-$index`). Change: the active tile's border color from
  `Theme.of(context).colorScheme.primary` to `context.ream.green`; keep the black
  strip background (works on the dark editor). Placeholder icon → `context.ream.muted`.

- [ ] **Step 1:** Adjust/add a test asserting the selected tile's
  `foregroundDecoration` border color is `ReamColors.dark.green` when pumped under
  `ReamTheme.dark()`. Run → FAIL.
- [ ] **Step 2:** In `_buildTile`, replace `scheme.primary` with `context.ream.green`
  and the placeholder colors with `context.ream` tokens (`surface`/`muted`). Import
  `../../../theme/ream_colors.dart`.
- [ ] **Step 3:** Run → PASS.  **Step 4:** analyze + format + commit
  (`feat(library): thumbnail strip green active border (Ream)`).

---

## Task 5: `EditorToolbar`  *(Wave 1 — run after Task 1)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/editor_toolbar.dart`
- Test: `apps/mobile/test/features/library/editor_toolbar_test.dart`

**Interfaces:**
- Consumes: `EditorToolbarButton` (Task 1), `context.ream`.
- Produces: `class EditorToolbar extends StatelessWidget` —
  `EditorToolbar({required VoidCallback? onCrop, required VoidCallback? onRotate,
  required VoidCallback? onText, required VoidCallback? onRetake,
  required VoidCallback? onShare, required VoidCallback? onDelete, Key? key})`.
  Renders 6 `EditorToolbarButton`s on `context.ream.paper` with a top `line`
  hairline, evenly spaced, with these fixed keys: Crop `page-viewer-edit`
  (`Icons.crop`), Rotate `page-viewer-rotate` (`Icons.rotate_right`), Text
  `page-viewer-view-text` (`Icons.text_snippet_outlined`), Retake
  `page-viewer-retake` (`Icons.replay`), Share `page-viewer-share`
  (`Icons.ios_share`), Delete `page-viewer-delete-page` (`Icons.delete_outline`,
  `danger: true`). A null callback disables that button.

- [ ] **Step 1: Failing test** — pump `EditorToolbar` (dark theme) with a counter
  closure per callback; assert all 6 keys present, each with its label; tapping
  `page-viewer-rotate` fires `onRotate`; tapping `page-viewer-delete-page` fires
  `onDelete`; a null `onCrop` leaves `page-viewer-edit` present but inert.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** a `SafeArea(top:false)` + `Container`
  (`color: context.ream.paper`, top `Border(top: BorderSide(color: line))`) with a
  `Row(mainAxisAlignment: spaceAround)` of the 6 keyed `EditorToolbarButton`s.
- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): EditorToolbar (6-action dark bar)`).

---

## Task 6: `PageViewerScreen` restructure + host-test migration  *(Wave 2 — single owner)*

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Modify (tests, failing-first): `page_viewer_screen_test.dart`,
  `page_viewer_rotate_test.dart`, `page_viewer_view_text_test.dart`,
  `page_viewer_h4_test.dart`, `page_viewer_split_test.dart`,
  `page_viewer_merge_test.dart`, `page_viewer_print_test.dart`,
  `page_viewer_protect_test.dart`, `page_viewer_export_all_test.dart`,
  `page_viewer_q1_test.dart`, `page_viewer_i1_test.dart`,
  `page_viewer_share_extras_test.dart`, `delete_page_test.dart`,
  `share_routing_test.dart`, and the donation `donation_banner_wiring_test.dart`
  (remove the "page viewer shows the donation banner" assertion).
- Consumes: Tasks 1–5.

**Target structure:**
- Wrap the returned `Scaffold` in
  `AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child:
  Theme(data: ReamTheme.dark(), child: Scaffold(...)))` — dark editor + light
  status-bar icons, both auto-reverting on pop.
- `appBar: EditorTopBar(title: _name, onBack: () => Navigator.pop(context),
  trailing: <the ⋯ PopupMenuButton>)`. The overflow keeps key
  `page-viewer-page-menu` but now holds **only** Rename (`page-viewer-rename`),
  Merge (`page-viewer-merge`), Split (`page-viewer-split`), Delete-document
  (`page-viewer-delete`).
- Body unchanged (loading/error/empty/`PageView`+strip), except:
  - Overlay `PageCounterPill(current: _current + 1, total: pages.length)` with
    `key: Key('page-viewer-page-counter')` at top-right of the viewer via a
    `Stack`/`Positioned`, shown when `pages.length > 1`.
  - The `PageThumbnailStrip` now renders on the dark surface (already dark).
- Replace `bottomNavigationBar: DonationBanner()` with
  `bottomNavigationBar: EditorToolbar(onCrop:…, onRotate:…, onText:…, onRetake:…,
  onShare: _openShareMenu, onDelete:…)`, wiring each to the existing handlers
  (`_editCrop(_pages![_current])`, `_rotatePage`, `_viewText`, `_retakePage`,
  `_confirmAndDeletePage`), each guarded by the existing enable conditions
  (null callback when `_loading||_error||_exporting||pages empty`).
- **`_openShareMenu`** (new): shows a menu/sheet (a `PopupMenuButton` opened
  programmatically, or `showModalBottomSheet`) offering Export-PDF
  (`page-viewer-export`→`_exportPdf`), Share-image (`page-viewer-export-image`→
  `_exportPageAsImage`), Share-all (`page-viewer-export-all-images`→
  `_exportAllImages`), Print (`page-viewer-print`→`_print`), Protect
  (`page-viewer-protect`→`_protect`), and `shareExtraMenuItems(...)` (link/fax).
  Keep the exact item keys so tests only change which control opens the menu.
- Remove the old `AppBar`, its icon actions, and the moved overflow items.
- Remove the `DonationBanner` import if now unused.

- [ ] **Step 1: Migrate host tests failing-first.** For each listed file, retarget
  finders: actions now on the toolbar (Crop/Rotate/Text/Retake/Delete-page) are
  tapped directly via their keys (drop the `tap(Key('page-viewer-page-menu'))`
  first); share/export-family actions (export-pdf/image/all/print/protect/link/fax)
  are reached by first tapping `Key('page-viewer-share')` (then the same item key);
  merge/split/rename/delete-document still open `page-viewer-page-menu`. Wrap any
  test pumping `PageViewerScreen` under a bare `MaterialApp` so it still renders
  (the `context.ream` fallback covers it, but prefer `theme: ReamTheme.light()` at
  the app level — the screen self-scopes dark). Remove the donation-banner-in-viewer
  assertion. Run the batch and **paste failures**:

```bash
cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart \
  test/features/library/page_viewer_rotate_test.dart \
  test/features/library/page_viewer_view_text_test.dart \
  test/features/library/page_viewer_h4_test.dart \
  test/features/library/delete_page_test.dart
```
Expected: FAIL (old finders/structure gone).

- [ ] **Step 2: Implement the restructure** per the target above, keeping every
  handler and enable-guard. Add imports for the new widgets + `ream_theme.dart` +
  `package:flutter/services.dart` (SystemUiOverlayStyle).
- [ ] **Step 3: Run the migrated tests — expect PASS.** Then the full library test
  batch (all `page_viewer_*`, `delete_page`, `share_routing`, `merge_documents`,
  `split_document`, `replace_page`, `rotate_page`). Paste results.
- [ ] **Step 4: Full host suite + analyze + format:**

```bash
cd apps/mobile && flutter test && flutter analyze && dart format lib test
```
Expected: green except the 2 known OpenCV-env failures; "No issues found!".

- [ ] **Step 5: Commit** (`feat(library): restructure PageViewerScreen to Ream dark
  editor (top bar, toolbar, counter)`).

---

## Task 7: BDD step migration + regen  *(Wave 3)*

**Files:**
- Modify shared steps in `apps/mobile/test/step/` that reach relocated actions:
  `i_rotate_the_page.dart`, `i_open_the_text_view.dart`,
  `i_delete_the_current_page.dart`, the retake step used by `h4_delete_retake`,
  the crop/re-edit step used by `e3_reedit`, `i_export_the_page_as_an_image.dart`,
  `i_export_the_page_as_an_image_at_medium_quality.dart`,
  `i_export_all_pages_as_images.dart`, `i_print_the_document.dart`,
  `i_protect_with_a_password.dart`, and any share-extras step.
- Regenerate: `dart run build_runner build --delete-conflicting-outputs`.

**Interfaces:** steps are shared across all 12 viewer BDD features — update the tap
target only (toolbar button or Share menu), not the assertions.

- [ ] **Step 1:** For each step, change the control it taps: toolbar actions →
  `tester.tap(find.byKey(const Key('page-viewer-<action>')))` directly; share/export
  actions → first `tap(Key('page-viewer-share'))`, `pumpAndSettle`, then the item
  key. Read one existing step for the exact style. Do NOT weaken assertions.
- [ ] **Step 2:** Regenerate; confirm no build_runner errors and the generated
  viewer `*_test.dart` still compile.
- [ ] **Step 3:** `flutter analyze` clean; `flutter test` host suite green (2
  opencv-env only). Host does not run `integration_test/` — device is Task 8.
- [ ] **Step 4:** analyze + format + commit (`test(library): migrate viewer BDD
  steps to the Ream toolbar/share menu`).

---

## Task 8: Device verification + dark-palette validation  *(Wave 3)*

Run the viewer BDD features on the real Android device (RZCY51D0T1K) and the iOS
18.3 simulator; validate/tune the dark palette.

- [ ] **Step 1:** `cd apps/mobile && flutter devices` — record ids. If a platform
  is unavailable, name the gap (real iOS hardware is a known named gap; the sim is
  used).
- [ ] **Step 2: Android** — run the viewer features:

```bash
cd apps/mobile && for f in b3_view_and_delete k1_rotate_page h4_delete_retake \
  h2_page_thumbnail_strip h3_page_reorder o4_recognized_text; do
  flutter test integration_test/${f}_test.dart -d RZCY51D0T1K --timeout 240s || break
done
```
Expected: each PASS. Paste summaries.

- [ ] **Step 3: iOS sim** — same loop with `-d <ios-sim-udid>`. Paste summaries.
- [ ] **Step 4: Dark-palette check.** `flutter run -d RZCY51D0T1K`, open a document,
  screenshot the editor; confirm contrast of `ink`/`muted`/`line` on the dark
  surface, green active thumb, red Delete, readable page counter. If any token
  reads poorly, adjust the **dark** set in `lib/theme/ream_colors.dart` (update the
  token test), re-run the affected host + device tests, and commit
  (`fix(theme): tune ReamColors.dark for the editor`). Repeat on the iOS sim.
- [ ] **Step 5:** Report exact commands + green output + a screenshot per platform.
  Only then is Phase 2a done.

---

## Self-review (author checklist — completed)

- **Spec coverage:** dark theme scoping (Task 6 wrap), 6-icon toolbar (Tasks 1,5,6),
  top bar (Task 3,6), page counter (Task 2,6), green strip (Task 4), Share menu +
  overflow reorg + banner removal + action-key preservation (Task 6), system UI
  (Task 6), BDD migration (Task 7), device + dark-palette validation (Task 8).
- **Placeholder scan:** none — real code for the small widgets; the integration
  task lists exact keys, handlers, and structure.
- **Type consistency:** `EditorToolbarButton`, `EditorToolbar` (onCrop/onRotate/
  onText/onRetake/onShare/onDelete), `PageCounterPill(current,total)`,
  `EditorTopBar(title,onBack,trailing)`, and the action keys are used identically
  across producing (Tasks 1–5) and consuming (Task 6) tasks.
