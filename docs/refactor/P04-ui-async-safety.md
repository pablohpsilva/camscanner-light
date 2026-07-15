# P04 — UI Async-Safety Bugs (reorder race, unclamped index, blocking IO, silent drops)

**Tier 1 (Safety) · Effort S–M · Risk Med · Depends on: none · Device verification: both (real Android AND real iOS)**

## Summary

P04 fixes a cluster of targeted UI async-safety defects: a page-reorder that bypasses the
single-flight guard every other edit respects (a real race), a synchronous multi-MB image
write on the UI isolate before OCR, a share flow with no busy UI (double-tap / no
feedback), an ID-scan flow that silently discards an already-captured front page, and a
latent unclamped page index. Each fix is small, independently shippable, and behavior-
preserving except where the current behavior is the bug. **This plan pairs conceptually
with P06 (controllers) but is independently shippable as pinpoint bugfixes — it does not
require P06 to land first.**

## Global constraints (apply to every task in this plan)

- **Behavior-preserving where the behavior is correct.** Public APIs/interfaces of the
  screens stay stable so the ~25k-LOC suite (179 host test files, 42 `.feature` BDD specs,
  66 integration tests) stays GREEN. The only intended behavior *changes* are the four
  live bugs (reorder race, blocking IO, missing busy UI, silent front-page drop) — each
  gets a new test asserting the corrected behavior; everything else must stay green.
- **TDD.** Each task adds a failing-first test that reproduces the bug BEFORE the fix.
- **BDD.** Scenarios that must stay green / be extended:
  `integration_test/h3_page_reorder.feature` (reorder), `id_scan.feature` (ID capture),
  `o4_recognized_text.feature` (OCR write path), `r1_share_document.feature` +
  `r4_share_documents_zip.feature` (Home share/export), `m1_split_document.feature` +
  `l1_merge_documents.feature` (split/merge, for the index-clamp hardening). Add new
  scenarios: an ID-scan "cancel back after front captured" scenario, and a Home
  "share shows busy state" assertion (see tasks).
- **Both platforms.** Every fix here touches on-device async/IO/native flows and MUST be
  verified on a real Android AND a real iOS device via the named `integration_test`
  device runs. Host green is not done.
- **Small independent tasks.** T1–T5 touch different files/screens
  (`page_viewer_screen.dart`, `mlkit_ocr_engine.dart`, `home_screen.dart`,
  `id_scan_screen.dart`) and share no state — dispatch each to a separate subagent. The
  page-viewer tasks (T1 reorder-race + T5 index-clamp) touch the same file, so serialize
  those two on one subagent or coordinate the diff; everything else is fully parallel.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| REORDER-RACE | `page_viewer_screen.dart:409-417` (`_reorderPages`) → `:419-433` (`_persistReorder`, `// ignore: discarded_futures` at `:415`) | `_reorderPages` does `setState(() => _pages = ordered)` then **fire-and-forgets** `_persistReorder`. It does NOT check/set `_editing` (`:75`), the single-flight guard that `_runEdit` (`:440-458`), `_rotatePage` (`:462`), `_editCrop` (`:471`), `_editFilter` (`:494`) all respect. | A reorder can run **concurrently** with a `_runEdit` full-res regeneration → the same "revert"/stale-image race the single-flight was built to prevent (see field doc `:71-74`). | LIVE |
| BLOCKING-IO | `mlkit_ocr_engine.dart:28` — `File('${dir.path}/img.jpg')..writeAsBytesSync(imageBytes)`; also `dir.deleteSync(recursive:true)` at `:57` | A multi-MB image is written **synchronously on the UI isolate** before OCR (and deleted sync after). | Frame jank / momentary UI freeze on every OCR (each recognized-text/PDF-with-text export). | LIVE (perf) |
| SHARE-BUSY | `home_screen.dart:85` — `bool _sharing = false;` is a **plain field** (never `setState`-backed); set/reset in `_shareDocument:308-326` and `_exportSelected:346-382` (reset in `finally`) | `_sharing` drives no busy UI — no spinner, no disabled control — during share/export. Contrast `page_viewer_screen.dart:70` `_exporting` which **is** `setState`-backed and disables the toolbar (`_actionsDisabled:564`). | User can double-tap share/export (re-entry is guarded by the flag, so the second tap is silently ignored with **no feedback**) and gets no progress indication on a slow export. | LIVE (UX) |
| SF-4-IDSCAN | `id_scan_screen.dart:56-61` — when back capture is cancelled (`back == null`), `navigator.pop()` with **no snackbar**; the front was already captured at `:48-53` and is only saved later (`:66`) | Cancelling the BACK step **silently discards the already-captured FRONT**. Contrast a *failed back-save* which shows `idScanErrorBackRetake` (`:84-89`). | User captures the front, cancels the back, and their front photo vanishes with no explanation. | LIVE (UX/data) |
| CURRENT-UNCLAMPED | `page_viewer_screen.dart:82` (`int _current = 0`); clamped only after page-delete (`:254`). `_splitAfter:532` and `_mergeAnother:552` call `_load()` (list length changes) **without** re-clamping `_current`. | `_current` is re-clamped in exactly one place (delete). Split/merge reload the list without touching `_current`. | Split and merge only **grow** the list, so `_current` never exceeds the new length → **no live RangeError today**. Hardening only. | LATENT |

## Definition of done

- Reorder is routed through the same single-flight as every other edit (checks/sets
  `_editing`), so it cannot race a concurrent `_runEdit` regeneration — proven by a test
  that would fail on today's code.
- ML-Kit OCR writes the temp image with `await writeAsBytes` (async) and cleans up
  asynchronously — no `*Sync` file IO on the UI isolate.
- Home `_sharing` becomes a `setState`-backed status that disables the share/export
  control and shows a busy indicator while a share/export is in flight (parity with
  page-viewer's `_exporting`).
- Cancelling the ID-scan BACK step no longer silently loses the front: either offer to
  save front-only or show an explanatory snackbar (chosen behavior fixed in T4; tested).
- `_current` is clamped centrally wherever `_pages` is (re)assigned, closing the latent
  gap for split/merge (framed as hardening).
- `flutter analyze` zero-warning; full host suite green; named device tests green on
  Android AND iOS.

## Before → After

| Behavior | Before | After |
|----------|--------|-------|
| Page reorder | fire-and-forget, bypasses `_editing` single-flight → can race an edit | routed through the single-flight (sets/checks `_editing`); no race |
| OCR temp write | `writeAsBytesSync` (blocks UI isolate) + `deleteSync` | `await writeAsBytes` + async cleanup; no UI-isolate stall |
| Home share/export | `_sharing` plain field → no busy UI, silent double-tap ignore | `setState`-backed status → disabled control + spinner (parity w/ `_exporting`) |
| ID-scan cancel-back | silently pops, front photo discarded | front-only save offered OR explanatory snackbar; no silent data loss |
| `_current` clamp | clamped only on delete | clamped centrally on every `_pages` assignment (split/merge safe) |

## Tasks

### T1 — Route page reorder through the single-flight guard (REORDER-RACE)
- **Scope.** In `page_viewer_screen.dart`, make `_reorderPages`/`_persistReorder` respect
  `_editing`: refuse re-entry while an edit/reorder is running, flip `_editing` for the
  duration of the persist, and reload/rollback on failure — i.e. drive the persist through
  the same `_runEdit`-style single-flight the other edits use (`:440-458`). Keep the
  optimistic `setState(() => _pages = ordered)` for snappy UI, but guard the persistence
  and the concurrent-edit window. Preserve the existing failure UX
  (`viewerReorderPagesError` snackbar + `_load()` rollback, `:427-431`).
- **Files.** `lib/features/library/page_viewer_screen.dart`;
  `test/features/library/page_viewer_screen_test.dart`.
- **Test-first.** Add a widget test: start a slow reorder persist, then attempt a
  `_rotatePage` (or another `_runEdit`) while it's in flight, and assert the second edit is
  refused (single-flight) — this FAILS on today's code where reorder ignores `_editing`.
  Also assert the reorder still persists and the toolbar re-enables afterward. Watch fail,
  implement.
- **Done-criteria.** New race test green; `h3_page_reorder` still green host + device.
- **Parallel-safe?** Yes, but **shares the file with T5** — put T1+T5 on one subagent or
  land T1 first and rebase T5.

### T2 — Make ML-Kit OCR file IO asynchronous (BLOCKING-IO)
- **Scope.** In `mlkit_ocr_engine.dart`, replace `File(...)..writeAsBytesSync(imageBytes)`
  (`:28`) with `await file.writeAsBytes(imageBytes)`, and replace `dir.deleteSync(...)`
  (`:57`) with `await dir.delete(recursive: true)` inside the existing best-effort
  `try/catch` in the `finally`. Behavior (which file, then `processImage`) is unchanged —
  only the isolate-blocking is removed. (Note: this deliberately does NOT adopt
  `TempFileWriter` — that is P10/P14; keep the change surgical.)
- **Files.** `lib/features/library/ocr/mlkit_ocr_engine.dart`; OCR engine test at the seam.
- **Test-first.** Because the engine is native, host-assert the contract at the `OcrEngine`
  seam is unchanged (fake returns same `OcrResult`). Add a note that the async-write
  behavior is device-verified (no crash, no jank) under `o4_recognized_text`.
- **Done-criteria.** No `writeAsBytesSync`/`deleteSync` remain in the file (grep = 0);
  `o4_recognized_text` recognizes text unchanged on Android + iOS.
- **Parallel-safe?** Yes (independent file).

### T3 — Home share/export busy state (SHARE-BUSY)
- **Scope.** In `home_screen.dart`, convert `_sharing` (`:85`) into a `setState`-backed
  status (mirror `page_viewer_screen.dart:70` `_exporting`: set inside `setState`, reset in
  a `finally` with `if (mounted) setState(...)`). While `_sharing` is true, disable the
  share/export triggers and show a busy indicator (reuse whatever affordance the app
  already uses; do not invent new copy). Cover both `_shareDocument:308-326` and
  `_exportSelected:346-382`. Keep the existing re-entry guard semantics (a second tap is
  still ignored) but now it's *visibly* disabled.
- **Files.** `lib/features/library/home_screen.dart`;
  `test/features/library/home_screen_test.dart` (+ possibly a small BDD assertion).
- **Test-first.** Widget test: trigger `_shareDocument` with a slow fake `share`/repo,
  assert the control is disabled and a busy indicator is shown while in flight, and both
  clear in the `finally` — FAILS today (plain field drives no UI). Watch fail, implement.
- **Done-criteria.** Busy-state test green; `r1_share_document`, `r4_share_documents_zip`
  still green host + device.
- **Parallel-safe?** Yes (independent file).

### T4 — ID-scan: don't silently discard the front on back-cancel (SF-4-IDSCAN)
- **Scope.** In `id_scan_screen.dart`, when `back == null` (`:58-61`), stop silently
  `pop()`-ing. Chosen behavior (decide + document in the diff; recommend the smaller,
  data-preserving option): **save the front-only as a single-page document** (reuse
  `_saveController.save(front, ...)` then `markAsIdCard` best-effort) OR, if product
  prefers, show an explanatory snackbar (new l10n key, e.g. `idScanCancelledBackKeptFront`
  / `idScanFrontDiscarded`) before popping. Whichever is chosen, the front photo must not
  vanish without the user understanding why. Keep the existing back-save-failure path
  (`idScanErrorBackRetake`, `:84-89`) unchanged.
- **Files.** `lib/features/scan/id_scan_screen.dart`; if adding copy, the ARB files under
  `lib/l10n/` for all 11 locales (respect the ARB-parity guardrail) + regenerate l10n;
  `test/features/scan/id_scan_screen_test.dart`.
- **Test-first.** Widget/BDD test: fake scanner returns a front then a cancel (empty) for
  back; assert the chosen behavior (front-only doc saved OR explanatory snackbar shown) —
  FAILS today (silent pop, nothing saved, no message). Watch fail, implement.
- **Done-criteria.** New cancel-back test/scenario green; `id_scan` happy-path still green
  host + device; ARB parity guardrail green if copy added.
- **Parallel-safe?** Yes (independent file). If copy is added, coordinate with the l10n
  guardrail test.

### T5 — Clamp `_current` centrally on every `_pages` assignment (CURRENT-UNCLAMPED, hardening)
- **Scope.** In `page_viewer_screen.dart`, introduce a single setter/helper that assigns
  `_pages` and clamps `_current` to `[0, len-1]` (or 0 when empty) in one place, then route
  the delete-clamp (`:254`), `_load` (`:106-109`), `_splitAfter` (`:532`), and
  `_mergeAnother` (`:552`) reloads through it. This removes the special-cased clamp and
  closes the latent split/merge gap. **Framed as hardening — no live RangeError exists
  today** (split/merge only grow the list), so this must not change any current behavior,
  only centralize the invariant.
- **Files.** `lib/features/library/page_viewer_screen.dart`; its test.
- **Test-first.** Add a test that assigns a shorter `_pages` (hypothetical) and asserts
  `_current` is clamped — establishing the invariant the central setter guarantees. Confirm
  split/merge/delete behavior is unchanged. Watch fail, implement.
- **Done-criteria.** Invariant test green; `m1_split_document`, `l1_merge_documents`,
  `b3_view_and_delete` still green host + device.
- **Parallel-safe?** Shares the file with T1 — serialize with T1 on one subagent.

## Risks & mitigations

- **Risk (Med): routing reorder through the single-flight changes reorder timing / UX.**
  Mitigation: keep the optimistic `setState(_pages)` for instant visual reorder; only the
  *persist* and the concurrent-edit window are guarded. Cover with the race test + the
  existing `h3_page_reorder` scenario on device.
- **Risk: making OCR IO async changes ordering subtly (e.g. cleanup timing).** Mitigation:
  keep the exact same steps (write → `processImage` → close+delete in `finally`), only
  swapping sync→async; device-verify `o4_recognized_text` on both platforms.
- **Risk: a visible disabled/busy share control breaks a widget test that taps share
  twice or asserts an always-enabled button.** Mitigation: audit `home_screen_test.dart`
  for such assumptions; update those tests to the corrected (disabled-while-busy) behavior
  as part of T3 (this is a deliberate UX fix, not a regression).
- **Risk (T4): changing the cancel-back behavior surprises users / needs product sign-off
  and new copy in 11 locales.** Mitigation: pick the minimal data-preserving option,
  gate any new l10n key through the ARB-parity guardrail, and keep the happy path
  untouched; document the chosen behavior in the diff.
- **Risk (T5 hardening changes live behavior).** Mitigation: it must not — split/merge only
  grow the list; the central clamp is a no-op for today's inputs. The invariant test plus
  unchanged split/merge/delete scenarios prove it.

## Verification commands

Run from `apps/mobile/`.

```bash
# Regenerate BDD/l10n if T4 adds a scenario or copy
dart run build_runner build --delete-conflicting-outputs

flutter analyze

# Host: the failing-first bug reproductions, now green
flutter test test/features/library/page_viewer_screen_test.dart
flutter test test/features/library/home_screen_test.dart
flutter test test/features/scan/id_scan_screen_test.dart

# Full host suite (regression guardrail)
flutter test

# Prove the blocking IO is gone
grep -n "writeAsBytesSync\|deleteSync" lib/features/library/ocr/mlkit_ocr_engine.dart  # expect: no output

# DEVICE — both platforms (async/IO/native)
flutter test integration_test/h3_page_reorder_device_test.dart   -d <android-device-id>
flutter test integration_test/h3_page_reorder_device_test.dart   -d <ios-device-id>
flutter test integration_test/o4_recognized_text_device_test.dart -d <android-device-id>
flutter test integration_test/o4_recognized_text_device_test.dart -d <ios-device-id>
flutter test integration_test/r1_share_document_device_test.dart -d <android-device-id>   # if present; else name the gap
flutter test integration_test/r1_share_document_device_test.dart -d <ios-device-id>
flutter test integration_test/id_scan_device_test.dart           -d <android-device-id>   # if present; else name the gap
flutter test integration_test/id_scan_device_test.dart           -d <ios-device-id>
flutter test integration_test/m1_split_document_device_test.dart -d <android-device-id>
flutter test integration_test/m1_split_document_device_test.dart -d <ios-device-id>
flutter test integration_test/l1_merge_documents_device_test.dart -d <android-device-id>
flutter test integration_test/l1_merge_documents_device_test.dart -d <ios-device-id>
```

Where a `*_device_test.dart` does not yet exist for a named `.feature` (e.g. `r1_share`,
`id_scan`, `h3_page_reorder`), that device coverage must be **added or named as an explicit
gap** per the both-platforms rule — never silently skipped. State the exact command and
paste the green summary before claiming any P04 task done.
