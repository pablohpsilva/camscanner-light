# P11 — Share-action model + feature-flag gating unification

**Tier 3 (DRY) · Effort M · Risk Low · Depends on: none (P06 optional — cleaner if the controller exists, but this stands alone) · Device verification: real Android AND real iOS**

## Summary

The share/extra-action menu is implemented three times with copy-pasted,
stringly-typed dispatch, and per-action feature-flag gating is spread across 25
`features.*` reads plus a hand-written OR-chain that must be kept in sync by
hand. This plan introduces a single **`ShareAction` model** (an enum-backed value
carrying label, icon, feature flag, and handler) built once and rendered onto any
surface (bottom sheet, popup menu), dispatched by the enum rather than raw
strings. Per-action gating and the umbrella "any share available" predicate are
**derived** from the filtered action list instead of a hand-maintained boolean.

The page_viewer overflow/share logic is also pulled out of the widget into pure,
unit-testable functions (`overflowItems(FeatureFlags)`,
`shouldShowShareButton(FeatureFlags)`) with a stateless renderer.

Keys and visible labels are preserved so the widget/BDD suites stay green — the
change is structural (one source of truth), not behavioral.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
| --- | --- | --- | --- | --- |
| share-menu-duplication | 3 surfaces: `page_viewer_screen.dart` `_openShareMenu`:628–706 (bottom-sheet `ListTile`s + `switch`:691–705 — the OUTLIER, does NOT use `shareExtraMenuItems`); `documents_list_view.dart` popup:83–117; `share_menu_button.dart`:63–89 (these two partly share `shareExtraMenuItems`) | The share-link/fax action set + dispatch is copy-pasted and stringly-typed (`kShareLinkValue`/`kFaxValue` → `handleShareExtra`); page_viewer re-implements the whole sheet by hand instead of reusing the shared helper | Add/rename/re-gate a share action → edit 3 places, easy to drift; raw-string dispatch is un-typo-checked | live |
| overflow-menu-in-screen | `page_viewer_screen.dart` `_buildOverflowMenu`:582–622 (returns `null` when all flags off :583–584) + `_openShareMenu`:628–706 mixes bottom-sheet UI with `await _exportPdf()` etc. | Menu-composition rules (which items show, when the whole menu is null) are entangled with rendering and action execution inside the State class | Can't unit-test "which items appear for a given FeatureFlags" without pumping the widget | live |
| feature-flag-gating | 25 `features.*` reads (page_viewer 21, documents_list_view 2, pdf_preview 2); hand-written OR-chain `_showShareButton`:570–578 (`share && (exportPdf \|\| shareImage \|\| exportAllImages \|\| print \|\| protectWithPassword \|\| shareLink \|\| fax)`); 7 `if (features.x)` menu guards at :637,644,651,658,665,672,679; toolbar gates :749–755 | The umbrella "is any share action available" predicate is a hand-maintained OR that must be edited every time a share sub-action is added; the same flags are read in the OR AND in each `if` guard (double source of truth) | A new share action added to the sheet but forgotten in the OR-chain → an empty sheet can be opened (or a live action hidden) | latent (drift risk) — the OR is currently correct but is manually coupled to the 7 guards |

## Definition of done

- A `ShareAction` model exists: an `enum ShareActionKind` plus a value type
  carrying `{ kind, label (l10n), icon, featureFlag selector, handler }`. The
  list of available actions is built **once** from `FeatureFlags` + l10n.
- Any surface renders from that list: `documents_list_view` popup,
  `share_menu_button` popup, and page_viewer's bottom sheet all consume the same
  `List<ShareAction>` and dispatch via `kind`, not raw strings. `handleShareExtra`
  is reached through the model, not re-implemented.
- Pure functions `overflowItems(FeatureFlags)` and
  `shouldShowShareButton(FeatureFlags)` exist and are unit-tested **without
  pumping a widget**; a stateless renderer turns them into UI.
- `anyShareAvailable` is **derived** from the filtered `ShareAction` list
  (`actions.isNotEmpty`), replacing the hand-written OR-chain at :570–578. The 7
  per-item `if (features.x)` guards are removed in favor of building only the
  enabled actions.
- Existing menu item **keys and labels are unchanged** (e.g.
  `page-viewer-export`, `page-viewer-share-link`, `document-<id>-fax`,
  `share-menu-share`), so `page_viewer_screen_test.dart`,
  `documents_list_view_test.dart`, `pdf_preview` tests and all `.feature` BDD
  scenarios stay green.
- Device-verified on real Android AND real iOS that every share surface opens,
  lists the correct enabled actions for the default FeatureFlags, and dispatches
  correctly (share/export path AND the unavailable-toast path).

## Before → After

| Aspect | Before | After |
| --- | --- | --- |
| Share action definition | Duplicated across 3 surfaces; page_viewer hand-rolls its own `ListTile`s + `switch` | One `List<ShareAction>` built from FeatureFlags + l10n |
| Dispatch | Raw strings (`'export-pdf'`, `kShareLinkValue`) → `switch` / `if v ==` | By `ShareActionKind` enum → handler on the model |
| "Any share available?" | Hand-written OR-chain (:570–578) coupled to 7 `if` guards | `actions.isNotEmpty` — single source of truth |
| Per-action gating | 7 inline `if (features.x)` in the sheet + repeated flag reads | Actions filtered by their `featureFlag` once |
| page_viewer menu logic | Inside `_buildOverflowMenu`/`_openShareMenu` in the State | Pure `overflowItems(FeatureFlags)` / `shouldShowShareButton(FeatureFlags)` + stateless renderer |
| Testable without widget? | No | Yes — action-list building + gating are plain unit tests |
| Item keys/labels | (baseline) | Unchanged — behavior-preserving |

## Tasks

Each task is independent, subagent-runnable, TDD-first, and keeps every suite
green.

1. **Introduce the `ShareAction` model + `ShareActionKind` enum.**
   Scope: new `lib/features/library/share/share_action.dart`. Define the enum
   (export-pdf, share-image, export-all-images, print, protect, share-link, fax)
   and a value type `{ kind, label(BuildContext), icon, isEnabled(FeatureFlags) }`.
   Provide `availableShareActions(FeatureFlags)` returning only enabled actions,
   preserving the existing key strings via a `keyFor(kind, prefix)` helper.
   Test-first: unit test that default FeatureFlags yields the expected ordered
   kinds, that flags hide the right actions, and that `keyFor` matches the
   existing keys (`page-viewer-export`, etc.). No widget pumped.
   Done: green unit test; not yet wired. Parallel-safe: yes (net-new file).

2. **Extract pure `overflowItems`/`shouldShowShareButton` from page_viewer.**
   Scope: new pure functions (same file or a sibling) capturing
   `_buildOverflowMenu`'s null-when-all-off rule (:583–584) and the
   `_showShareButton` predicate (:570–578) — the latter now defined as
   `availableShareActions(f).isNotEmpty && f.share`.
   Test-first: unit tests over FeatureFlags permutations (all off → no button /
   null menu; single flag on → button shown). No widget pumped.
   Done: green; equivalence to the current booleans proven. Parallel-safe: yes
   (after task 1 for `availableShareActions`).

3. **Render the page_viewer bottom sheet from the model (the outlier).**
   Scope: `page_viewer_screen.dart` `_openShareMenu`:628–706. Replace the
   hand-built `ListTile`s + 7 `if` guards + `switch` with a loop over
   `availableShareActions(features)`; dispatch by `kind`. Keep every `Key` and
   l10n label identical. Route each kind to its existing handler
   (`_exportPdf`/`_exportPageAsImage`/…/`handleShareExtra`).
   Test-first: page_viewer widget test — the same items appear for default flags
   and dispatch to the same behavior (assert via existing keys). BDD share
   scenarios stay green.
   Done: green; the outlier now uses the shared model. Parallel-safe: after 1
   (independent of documents_list_view / share_menu_button work).

4. **Render `documents_list_view` popup from the model.**
   Scope: `documents_list_view.dart`:83–117. Replace the inline
   share/share-link/fax `PopupMenuItem`s with the model, keyed
   `document-<id>-...` as today; keep rename as-is.
   Test-first: `documents_list_view_test.dart` stays green (same keys/labels);
   add a case asserting fax/share-link visibility follows `features`.
   Done: green. Parallel-safe: after 1; independent of task 3.

5. **Render `share_menu_button` popup from the model.**
   Scope: `share_menu_button.dart`:63–89. Have `shareExtraMenuItems` /
   `ShareMenuButton` build from the model with `keyPrefix: 'share-menu'`.
   Test-first: any existing share_menu tests + pdf_preview/recognized_text usage
   stay green.
   Done: green. Parallel-safe: after 1; independent of tasks 3,4.

6. **Delete the hand-written OR-chain and per-item `if` guards.**
   Scope: page_viewer `_showShareButton`:570–578 replaced by task-2's derived
   predicate; the 7 `if (features.x)` at :637–685 removed (now handled by
   `availableShareActions`). Toolbar gate `showShare:` (:754) points at the
   derived predicate.
   Test-first: full page_viewer suite green; add a regression test that adding a
   hypothetical enabled action would flip `anyShareAvailable` (guards against
   future drift).
   Done: green; single source of truth. Parallel-safe: after 2,3.

## Risks & mitigations

- **A key or label changes and breaks a BDD/widget test.** Mitigation: the model
  reproduces the existing key strings via a `keyFor` map asserted in task 1;
  labels come from the same l10n getters. Diff item keys before/after.
- **Dispatch order / item order changes visibly.** Mitigation: define
  `ShareActionKind`'s declaration order to match the current on-screen order
  (export-pdf, share-image, export-all-images, print, protect, share-link, fax)
  and iterate in that order.
- **The bottom sheet (page_viewer) and the popups (list view, share button) have
  different item widget types.** Mitigation: the model exposes `label`/`icon`/
  `key`; each surface keeps its own widget wrapper (`ListTile` vs
  `PopupMenuItem`) — the model supplies data, not the widget, so no surface is
  forced into the wrong control.
- **`handleShareExtra`'s unavailable-toast path.** Mitigation: keep share-link/fax
  routed through `handleShareExtra` exactly; device-verify the toast still shows
  on both platforms.

## Verification commands

```bash
# From apps/mobile/
flutter analyze
dart format lib test
dart run build_runner build --delete-conflicting-outputs

# Host: model/gating unit tests (no widget) + surface regressions
flutter test test/features/library/share/share_action_test.dart
flutter test test/features/library/page_viewer_screen_test.dart
flutter test test/features/library/documents_list_view_test.dart
flutter test                                   # full host suite green

# Device (both platforms) — every share surface opens + dispatches
flutter test integration_test/<share_menu>_device_test.dart -d <android-device-id>
flutter test integration_test/<share_menu>_device_test.dart -d <ios-device-id>
```
