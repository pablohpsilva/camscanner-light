# P06 — Extract view controllers from God widgets

**Tier 2 (SOLID) · Effort L · Risk Med · Depends on: P00 (AppLogger for `runGuarded` logging) · Device verification: real Android AND real iOS**

## Summary

`page_viewer_screen.dart` (854 LOC) and `home_screen.dart` (682 LOC) are God
widgets: their `State` classes mix business logic (repository calls, async
orchestration, state machines) with rendering. The fix is to extract
`ChangeNotifier` collaborators — `PageViewerController`, `LibraryController` —
plus small domain helpers (`SelectionExporter`, a shared async-action runner)
that the widgets drive through `ListenableBuilder`. This mirrors the **proven
in-house pattern already in the repo**: `save_controller.dart`
(`SaveController extends ChangeNotifier`) — a small state machine with a
double-tap guard, dispose-safety, and no widget references. It is already wired
into `HomeScreen._onImport` via a `ListenableBuilder`
(home_screen.dart:210-241), so the integration shape is established and tested.

The public constructors and routes of both screens stay **identical**, so the
existing widget + BDD suites keep passing. The payoff is that the async action
logic becomes unit-testable **without pumping a widget** — exactly what
`SaveController`'s own unit tests already demonstrate.

Extraction is done incrementally: one action family per task, each behind a
green suite, so no single task rewrites a whole God widget.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
| --- | --- | --- | --- | --- |
| pv-god-widget | `page_viewer_screen.dart` `_PageViewerScreenState` L65–854 | 16 async action methods (`_reloadAfterEdit`:119, `_exportPdf`:129, `_rename`:160, `_confirmAndDelete`:180, `_confirmAndDeletePage`:215, `_exportPageAsImage`:265, `_exportAllImages`:290, `_print`:314, `_protect`:331, `_retakePage`:379, `_persistReorder`:419, `_rotatePage`:460, `_editCrop`:470, `_editFilter`:493, `_splitAfter`:515, `_mergeAnother`:541) + 17 `widget.repository.*` call sites, all interleaved with snackbars, navigation and the image-cache wipe | Business logic can only be exercised by pumping the widget; no isolated unit coverage of the repository orchestration; single class violates SRP | live |
| home-god-widget | `home_screen.dart` `_HomeScreenState` L65–682 | Repository construction (`_init`:114) + cold-start watchdog (`_load`:127, `_failStartup`:145, `_retry`:156) + FTS search race guard (`_onQueryChanged`:263–279) + multi-select export with zip-vs-pdf decision and entry-name derivation (`_exportSelected`:346–382; `if (ids.length == 1)` at :359–372; `p.basename(f.path)` at :365) | Repo lifecycle, search state, selection state and the export policy are all fused into the widget; the zip-vs-pdf rule is untestable without a pumped widget + fake share/archiver | live |
| setstate-state-machine | `page_viewer_screen.dart` loose booleans `_loading`:68, `_error`:69, `_exporting`:70, `_editing`:75, `_imageEpoch`:81; derived `_actionsDisabled`:564–565 | Four independent booleans can represent illegal combinations (e.g. `_loading && _error`); the project has a prior "opens but never loads" incident where a stuck flag wedged the UI | Correctness/robustness: illegal states representable; renders are a chain of ternaries (:724–733) | live (illegal combos are latent bugs, but the loose-flag design is live) |
| dup-load-state-machine | `page_viewer_screen.dart`:724–733 + error `_buildError`:777–794 (retry → `_load`); `recognized_text_screen.dart`:129–211 (retry = re-run OCR `_recognize`, semantically different); `pdf_preview_screen.dart`:93–105 (NO retry button, just error text) | Three loading/error/empty scaffolds are **similar but not identical** — forcing them into one widget would create false uniformity | Some DRY opportunity, but the semantic differences (retry-load vs retry-OCR vs no-retry) are real and must be preserved | live (structural), differences are real |
| duplicated-error-toast | 32 `showSnackBar` sites across 8 files (page_viewer 16; home 5; recognized_text 3; scan_screen 2; id_scan 2; donation 2; share_menu_button 1; feedback 1). Skeleton `setState(loading=true) → try → if(!mounted) return → catch(_) → showSnackBar → finally { clear }` repeats: e.g. `_exportPdf`:133–157, `_rename`:160–178, home `_renameDocument`:290–306 | The same try/catch/finally-with-toast boilerplate is copy-pasted; `catch (_)` swallows the error with no logging (no diagnosability on device) | High duplication; silent error swallowing; every site re-implements the mounted-check dance | live |
| home-owns-controllers | `home_screen.dart`:73–77 constructs fallback `ThemeController(store: InMemoryThemeModeStore())` / `LocaleController(store: InMemoryLocaleStore())` when none injected; `dispose()`:104–108 disposes only `_searchController` | The app-wide theme/locale controllers are **never disposed**, and the in-memory fallback silently means settings **don't persist** (the fallback store is not the real one) | Latent resource leak + silent settings-not-persisted trap if a caller forgets to inject | latent (leak) / live (silent non-persistence when fallback taken) |

## Definition of done

- `PageViewerController extends ChangeNotifier` owns pages / loading / error /
  editing / exporting / current + every `repository.*` call currently in
  `_PageViewerScreenState`. The widget renders via `ListenableBuilder` and holds
  **no** business logic — only navigation, dialog invocation, and rendering.
- `LibraryController extends ChangeNotifier` owns repo lifecycle + list / search
  / sort / selection state; `SelectionExporter` (a plain domain helper, no
  widgets) owns the zip-vs-pdf decision and entry-name derivation.
- A shared `sealed ViewState<T>` (`Loading` / `Error(msg)` / `Loaded(data)` /
  `Empty`) replaces the loose page_viewer booleans; renders become a `switch`.
- A generic `runGuarded({action, errorMessage})` / `AsyncActionController` owns
  the loading flag + mounted check + try/catch/finally + toast, and **logs via
  P00 AppLogger** (no more silent `catch (_)`). A `context.showErrorSnack(msg)`
  extension collapses the 32 raw `showSnackBar` sites.
- Theme/locale controllers are **injected** (or provided at app root); if a
  fallback is kept it is disposed in `dispose()`.
- Public constructors/routes of both screens are unchanged. All existing widget
  tests (`page_viewer_screen_test.dart` ~518 LOC, `home_screen_test.dart` 383 +
  branch tests, `documents_list_view_test.dart`), BDD `.feature` suites, and
  `integration_test/*` stay **green**.
- New controller unit tests exist and pass **without pumping any widget**
  (mirroring `save_controller`'s existing tests).
- Device-verified on real Android AND real iOS for anything touching image
  memory/decoding (the `_reloadAfterEdit` cache path).

## Before → After

| Aspect | Before | After |
| --- | --- | --- |
| page_viewer_screen.dart | 854 LOC widget; State holds 16 async actions + 17 repo calls + snackbars + nav + cache wipe | Thin view (rendering + nav + dialogs) driving `PageViewerController` via `ListenableBuilder` |
| PageViewerController | — | New `ChangeNotifier`: pages/loading/error/editing/exporting/current + all repo orchestration; unit-testable without a widget |
| home_screen.dart | 682 LOC widget; repo lifecycle + watchdog + search race + selection + export policy | View driving `LibraryController` via `ListenableBuilder` |
| LibraryController | — | New `ChangeNotifier`: repo lifecycle + list/search/sort/selection |
| SelectionExporter | — | Pure domain helper: zip-vs-pdf decision + entry-name derivation; unit-testable |
| page_viewer state | 4 loose booleans + `_imageEpoch`, illegal combos representable | `sealed ViewState<T>`; render is a `switch`; illegal states unrepresentable |
| Error toasts | 32 hand-rolled `showSnackBar` + `catch (_)` (silent) | `runGuarded` + `context.showErrorSnack`; errors logged via AppLogger |
| Theme/locale controllers | fallback constructed, never disposed; silent non-persistence | injected or app-root provided; disposed if fallback kept |
| Testable without widget? | No (must pump) | Yes — controllers + SelectionExporter have plain unit tests |

## Tasks

Each task is independent, subagent-runnable, TDD-first (write the failing test
before implementation), and leaves every suite green. Tasks 1–3 are
foundational and parallel-safe with each other; the extraction tasks (5–11) each
carve out one action family and can run in parallel once the primitives exist.

1. **Add `AsyncActionController` / `runGuarded` primitive + `showErrorSnack`
   extension.**
   Scope: new files `lib/features/library/async_action_controller.dart` and a
   `context.showErrorSnack(msg)` extension. `runGuarded({action, errorMessage})`
   owns loading flag + mounted-safety + try/catch/finally + toast, logs the
   caught error via P00 AppLogger.
   Test-first: unit test the controller drives a fake action through
   idle→busy→idle and idle→busy→error, and that it logs on failure — no widget
   pumped.
   Done: green unit test; nothing wired yet. Parallel-safe: yes (net-new file).

2. **Add `sealed ViewState<T>` (Loading/Error(msg)/Loaded(data)/Empty).**
   Scope: new `lib/features/library/view_state.dart`.
   Test-first: unit tests for exhaustive `switch` and equality.
   Done: green; unused by production yet. Parallel-safe: yes (net-new file).

3. **Add `SelectionExporter` domain helper.**
   Scope: new `lib/features/library/selection_exporter.dart` holding the
   zip-vs-pdf decision (`ids.length == 1 → single PDF`; else
   `exportSeparatePdfs` → `p.basename` entry names → zip) as pure logic over
   injected repo/archiver/share collaborators (lift verbatim from
   `_exportSelected`:346–382).
   Test-first: unit tests for the 1-doc PDF path and the N-doc zip path with
   fakes; assert entry names come from `p.basename`.
   Done: green unit test. Parallel-safe: yes (net-new file).

4. **Fix `home-owns-controllers` (inject or dispose).**
   Scope: `home_screen.dart` lines 73–77 + `dispose`:104–108. Either require
   injection (preferred) or, if a fallback is kept, dispose it. Prefer a small,
   behavior-preserving change: keep the fallback but add disposal.
   Test-first: a widget test asserting `dispose()` disposes the fallback
   controllers (spy controller), and a test documenting that injected
   controllers are NOT disposed by HomeScreen (ownership stays with the caller).
   Done: green; no leak. Parallel-safe: yes (isolated to `dispose`/field init).

5. **Extract `PageViewerController` skeleton: load + `ViewState`.**
   Scope: new `lib/features/library/page_viewer_controller.dart` owning
   `_load`/`_reloadAfterEdit` and exposing `ViewState<List<PageImage>>`. Wire
   page_viewer's body to render from it via `ListenableBuilder`. Depends on
   tasks 1,2.
   Test-first: controller unit tests for load-success/load-error and the epoch
   bump on reload — no widget pumped; then keep the widget suite green.
   Done: page_viewer's loading/error/empty/loaded switch is driven by the
   controller. Parallel-safe: sequences after 1,2; independent of 6–11.

6. **Move export actions onto the controller** (`_exportPdf`, `_exportPageAsImage`,
   `_exportAllImages`, `_print`, `_protect`) using `runGuarded`.
   Scope: page_viewer + controller. Navigation (opening `PdfPreviewScreen`) stays
   in the widget; the repo call + exporting flag + toast move to the controller.
   Test-first: controller unit tests per action (success + failure toast/log).
   Done: green; keys/behavior unchanged. Parallel-safe: after 5.

7. **Move edit actions onto the controller** (`_runEdit`, `_rotatePage`,
   `_editCrop`, `_editFilter`, `_retakePage`, single-flight `_editing` guard).
   Scope: page_viewer + controller. Dialog/navigation (crop/filter screens) stay
   in the widget; the repo mutation + `_editing` state + `_reloadAfterEdit` move
   to the controller.
   Test-first: unit test single-flight refusal (second call while editing is a
   no-op) and reload-after-success.
   Done: green. Parallel-safe: after 5 (coordinate with P13 on the cache path).

8. **Move structural actions onto the controller** (`_confirmAndDelete`,
   `_confirmAndDeletePage`, `_splitAfter`, `_mergeAnother`, `_reorderPages` /
   `_persistReorder`, `_rename`).
   Scope: page_viewer + controller. Confirm dialogs stay in the widget; the repo
   call + clamp/reorder/rollback logic move to the controller.
   Test-first: unit tests for delete-last-page-pops, reorder-persist-failure
   rollback (re-`_load`), and split-on-last-page warning.
   Done: green. Parallel-safe: after 5.

9. **Extract `LibraryController` skeleton: repo lifecycle + watchdog + list.**
   Scope: new `lib/features/library/library_controller.dart` owning `_init`,
   `_load`, `_failStartup`, `_retry`, `coldStartStepTimeout`, and the summaries
   list. Wire home body via `ListenableBuilder`. Depends on task 1 (logging).
   Test-first: unit tests for cold-start timeout → named failure, retry, and
   load-success — with a fake repo/library deps; no widget pumped.
   Done: green; watchdog behavior preserved. Parallel-safe: independent of 5–8.

10. **Move search + sort + selection onto `LibraryController`** (`_onQueryChanged`
    race guard, `_query`/`_searchResults`, `_sort`/`nextSort`, `_selectedIds`,
    `_displayed`).
    Scope: home + controller. Preserve the "newer query wins" race guard
    (:274) exactly.
    Test-first: unit test that a stale search result is discarded when a newer
    query has superseded it (race guard), and sort/selection toggles.
    Done: green. Parallel-safe: after 9.

11. **Wire `_exportSelected` to `SelectionExporter` + `runGuarded`.**
    Scope: home `_exportSelected` delegates to the task-3 helper behind
    `runGuarded`; the `_sharing` single-flight guard moves into the controller.
    Test-first: home widget/BDD test still green; the policy itself is covered by
    task 3's unit tests.
    Done: green. Parallel-safe: after 3 and 9.

12. **Collapse remaining raw `showSnackBar` sites to `context.showErrorSnack`.**
    Scope: the residual sites in scan_screen, id_scan, donation, feedback (the
    non-controller surfaces) — mechanical substitution only, no behavior change.
    Test-first: existing suites stay green (same visible text/keys).
    Done: green; `catch (_)` sites now log. Parallel-safe: yes, per-file.

## Risks & mitigations

- **Behavior drift breaking the 518-LOC page_viewer suite.** Mitigation: keep
  widget keys, snackbar l10n strings, and route pushes byte-identical; extract
  behind `ListenableBuilder` without renaming any `Key`. Run the full page_viewer
  suite after every task.
- **`ViewState` migration reintroducing an "opens but never loads" wedge.**
  Mitigation: the sealed type makes `Loading` un-mixable with `Error`; unit-test
  the exhaustive switch; device-verify cold start on both platforms.
- **Controller/widget lifecycle mismatch (dispose while an action is in flight).**
  Mitigation: copy `SaveController`'s `_disposed` guard pattern verbatim; unit
  test that post-dispose `notifyListeners` is suppressed.
- **`_reloadAfterEdit` cache interaction with P13.** Mitigation: task 7 touches
  the same code as P13's `imagecache-clear-global`; sequence them or land P13's
  `ImageCacheInvalidator` first, then have the controller call it. Device-verify
  crop/rotate/filter on both platforms.
- **False DRY on the three load/error scaffolds.** Mitigation: do NOT force
  recognized_text (retry = re-OCR) and pdf_preview (no retry) into the page_viewer
  shape; only share where semantics match (this is the `AsyncStateView` note in
  P06's dup-load finding — provide it, use it where it fits).

## Verification commands

```bash
# From apps/mobile/
flutter analyze
dart format lib test
dart run build_runner build --delete-conflicting-outputs   # regenerate *_test.dart from *.feature

# Host: controller unit tests (no widget pump) + widget/BDD regressions
flutter test test/features/library/page_viewer_controller_test.dart
flutter test test/features/library/library_controller_test.dart
flutter test test/features/library/selection_exporter_test.dart
flutter test test/features/library/page_viewer_screen_test.dart
flutter test test/features/library/home_screen_test.dart
flutter test test/features/library/documents_list_view_test.dart
flutter test                                   # full host suite green

# Device (both platforms) — the reload/cache path touches native decode
flutter test integration_test/k1_rotate_page_device_test.dart -d <android-device-id>
flutter test integration_test/k1_rotate_page_device_test.dart -d <ios-device-id>
```
