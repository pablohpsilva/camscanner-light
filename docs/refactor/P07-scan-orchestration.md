# P07 — Scan orchestration extraction

**Tier 2 (SOLID) · Effort M · Risk Med · Depends on: none · Device verification: Android + iOS (both available)**

Companion to `00-overview-and-comparison.md` and `01-roadmap.md`. This plan extracts the batch
save/add-page state machine that is **independently duplicated** across the two scan entry points
(`scan_screen.dart`, `id_scan_screen.dart`) into a plain-Dart use-case, and gives the untestable
inline I/O seams (URL launch, clipboard, image-size resolution) a proper collaborator so their
failure branches become unit-testable.

---

## Summary

Two scan flows — the general document scan (`scan_screen.dart`) and the ID scan
(`id_scan_screen.dart`) — hand-roll the **same** orchestration: create a scanner + `SaveController`
in `initState`, kick a `_run` off a post-frame callback, guard every `await` with
`if (!mounted) return`, capture with `CropCorners.fullFrame`, then **save the first page and loop
`addPage` for the rest**, and dispose the controller. The state machine (page count, captured pages,
enhancer, save-failed flag) lives inside `scan_screen`'s `State`. This is classic God-widget
orchestration: the batch logic can only be exercised by pumping a full widget, and the two copies
drift independently.

This plan is **behaviour-preserving**. Public widget constructors and the `SaveController` /
`ScanDependencies` shapes stay stable so `capture_review_screen_test.dart` (510 LOC), the scan BDD
(`scan_platform.feature`, `id_scan.feature`), and the feedback/donation/settings/`test/bdd/*`
suites stay GREEN. We extract logic **behind** the existing widgets; the widgets become thin renderers
over a controller they already own in spirit.

Five moves:

1. **DUP-1 / SOC-2** — extract a plain-Dart `ScanBatchController` use-case (save-first-then-loop
   `addPage`), reused by both scan screens; unit-testable without a widget pump.
2. **DUP-2** — extract a `ReviewAndSave` wrapper widget owning the `SaveController` +
   `ListenableBuilder` + null-result snackbar, shared by `scan_screen._pickFilter` and
   `home_screen._onImport` (exactly **2** call sites, corrected from an earlier "3×" claim).
3. **SOC-1** — inject a `UrlLauncher`/`Clipboard` seam into `donation_screen.dart` so
   `_openKofi`/`_copyAddress` failure + snackbar branches are testable.
4. **TST-2** — give `capture_review_screen._resolveImageSize` a test-safe default and promote the
   **duplicated** resolver in `edit_crop_screen.dart` into one shared `ImageSizeResolver`.

---

## Verified findings

| ID | Current location | What's wrong | Impact | Live/latent |
|---|---|---|---|---|
| **DUP-1** | `scan_screen.dart:41-149` & `id_scan_screen.dart:35-103` | Both independently duplicate scanner + `SaveController` orchestration: create `_scanner`+`SaveController` in `initState` (scan :44-45, id :38-39), `addPostFrameCallback(_run)` (scan :46, id :40), guard every `await` with `if(!mounted)return`, capture `CropCorners.fullFrame` (scan :127,143; id :64), save-first-then-loop-`addPage` (scan `_saveAll` :119-149; id save :66 + addPage :77), dispose controller (scan :153, id :107) | Save/add-page logic only testable via full widget pump; the two copies drift; a fix to one silently misses the other | **live** |
| **DUP-2** | `scan_screen.dart` `_pickFilter:97-117` & `home_screen.dart` `_onImport:211-241` | Both build `ListenableBuilder(listenable: saveController, … CaptureReviewScreen(saving:…, onAccept:…))`; `commonErrorSaveDocument` snackbar-on-null appears exactly **2×** (home :230, scan `_saveAll:134`) — **not 3×** (scan `_pickFilter` has no snackbar; `id_scan` uses `idScanErrorSave`) | Review/save wiring copy-pasted; a change to the review→save contract must be made twice | **live** |
| **SOC-2** | `scan_screen.dart` State: fields `_pageCount`/`_pages`/`_enhancer`/`_saveFailed` (:36-39), `_run:49-87`, `_retry:89-93`, `_saveAll:119-149`, save-failed UI in `build` (:160-177) | The `State` owns a full batch-save state machine mixed with rendering | Cannot unit-test the state transitions; `build` branches on machine state | **live** |
| **SOC-1** | `donation_screen.dart` `_openKofi:27-41` & `_copyAddress:43-49` | `launchUrl` (:32) / `Clipboard.setData` (:44) / `Uri.tryParse` (:28) called inline in a `StatelessWidget` — no seam | Failure/snackbar branches (bad URL, launch refused) are untestable | **live** |
| **TST-2** | `capture_review_screen.dart` `_resolveImageSize:17-37` (+ duplicate in `edit_crop_screen.dart:17-37`) | Default resolves a real `FileImage` stream (:19) — injectable, but the **default** couples to the image cache and risks host-test hangs; the resolver is duplicated verbatim in two files | Host tests must inject to avoid a real decode; two copies to maintain | **latent** |

---

## Definition of done

- `ScanBatchController` exists as a plain-Dart use-case (no Flutter widget imports beyond model
  types), with unit tests covering: save-first-then-loop-`addPage`, the mid-batch save failure path,
  and the `CropCorners.fullFrame` capture contract — **no widget pump required**.
- Both `scan_screen.dart` and `id_scan_screen.dart` drive `ScanBatchController` instead of holding
  their own copy of the state machine; their public constructors and `ScanDependencies` fields are
  unchanged.
- `ReviewAndSave` wrapper widget exists and is used by both `scan_screen._pickFilter` and
  `home_screen._onImport`; the null-result snackbar (`commonErrorSaveDocument`) lives in **one**
  place.
- `donation_screen.dart` takes an injected `UrlLauncher`/`Clipboard` seam (default = production impl,
  wired through `DonationDependencies`/existing DI); the bad-URL and launch-refused branches have
  unit tests.
- `ImageSizeResolver` is a single shared collaborator; `capture_review_screen` and `edit_crop_screen`
  both use it; the production default does not decode a real file under host tests (test-safe
  default or decode-via-injected-`readBytes`).
- **TDD**: each extraction lands its failing unit test first. **BDD**: `scan_platform.feature` and
  `id_scan.feature` stay green unchanged. **Device**: scan save-loop verified on real Android **and**
  iOS.
- `flutter analyze` clean (zero-warning bar). `capture_review_screen_test.dart` (510 LOC) unchanged
  and green.

---

## Before → After

| Concern | Before | After |
|---|---|---|
| Batch save/add-page logic | Duplicated in `scan_screen._saveAll` and `id_scan_screen` save+addPage | One `ScanBatchController` use-case, both screens call it |
| Scan state machine | Fields + methods on `scan_screen` `State`, entangled with `build` | Controller holds state; screen renders `controller.state` |
| Review + save wiring | `ListenableBuilder`+`CaptureReviewScreen`+snackbar in 2 call sites | One `ReviewAndSave` wrapper widget |
| Null-save snackbar | 2 hand-rolled copies (home :230, scan :134) | 1 place inside `ReviewAndSave` |
| Donation URL/clipboard | `launchUrl`/`Clipboard.setData` inline in a `StatelessWidget` | Injected `UrlLauncher`/`Clipboard` seam, failure branches tested |
| Image-size resolution | `_resolveImageSize` duplicated in review + crop screens; default decodes real file | One `ImageSizeResolver`; host-safe default |
| Testability | Save logic needs a widget pump | Save logic is a plain-Dart unit test |

---

## Tasks

Each task is independent and subagent-ready. Order within a task: **write the failing test first**,
then the minimum implementation, then refactor. Tasks 1–4 touch different files and are
parallel-safe; Task 5 depends on Task 1 landing the controller.

### Task 1 — Extract `ScanBatchController` use-case (DUP-1 + SOC-2)
- **Scope**: Create a plain-Dart `ScanBatchController` taking `List<CapturedImage>` + the page
  enhancer, driving save-first-then-loop-`addPage`, exposing a state (`idle`/`saving`/`saved`/
  `failed`, page count/index). No widget imports.
- **Files**: new `lib/features/scan/scan_batch_controller.dart`; new
  `test/features/scan/scan_batch_controller_test.dart`.
- **Test-first**: unit test — given N captured images, asserts one `save` then N-1 `addPage` in
  order; a save failure surfaces `failed` and does **not** call `addPage`; capture uses
  `CropCorners.fullFrame`.
- **Done**: controller green in isolation; no `flutter_test` widget pump used.
- **Parallel-safe**: yes (new files only).

### Task 2 — Rewire `scan_screen.dart` onto `ScanBatchController` (SOC-2, consumes Task 1)
- **Scope**: Replace `_pageCount`/`_pages`/`_enhancer`/`_saveFailed` (:36-39), `_run` (:49-87),
  `_retry` (:89-93), `_saveAll` (:119-149) with delegation to `ScanBatchController`; `build` renders
  `controller.state` (save-failed UI :160-177 driven by state). Constructor + `ScanDependencies`
  unchanged.
- **Files**: `lib/features/scan/scan_screen.dart`; existing `scan_screen` widget test if present.
- **Test-first**: adjust/add a widget test asserting the save-failed UI still renders on a controller
  `failed` state; watch it fail against the un-wired screen.
- **Done**: `scan_platform.feature` green; save-failed retry path green.
- **Parallel-safe**: yes after Task 1 (only `scan_screen.dart`).

### Task 3 — Rewire `id_scan_screen.dart` onto `ScanBatchController` (DUP-1, consumes Task 1)
- **Scope**: Replace the id-scan copy (`initState` :38-39, `addPostFrameCallback` :40, capture
  `CropCorners.fullFrame` :64, save :66 + `addPage` :77, dispose :107) with `ScanBatchController`;
  keep `idScanErrorSave` as the id-scan error string.
- **Files**: `lib/features/scan/id_scan_screen.dart`.
- **Test-first**: `id_scan.feature` stays the driver; add a step assertion if the save path changed
  observable timing; watch red then green.
- **Done**: `id_scan.feature` green; id-scan-specific error string preserved.
- **Parallel-safe**: yes after Task 1 (only `id_scan_screen.dart`).

### Task 4 — Extract `ReviewAndSave` wrapper widget (DUP-2)
- **Scope**: New widget owning `SaveController` + `ListenableBuilder` + `CaptureReviewScreen`
  (`saving`/`onAccept`) + the `commonErrorSaveDocument` null-result snackbar (the exact 2 call sites:
  `home_screen._onImport:211-241`, `scan_screen._pickFilter:97-117` — note `_pickFilter` has **no**
  snackbar, so only home's snackbar folds in; keep behaviour identical per call site).
- **Files**: new `lib/features/library/review_and_save.dart` (or scan-shared); edits to
  `home_screen.dart` and `scan_screen.dart` call sites.
- **Test-first**: widget test asserting a null save result shows `commonErrorSaveDocument` exactly
  once; a success result does not.
- **Done**: both call sites use the wrapper; `capture_review_screen_test.dart` unchanged & green.
- **Parallel-safe**: yes (new file + two narrow call-site edits).

### Task 5 — Inject URL/Clipboard seam into `donation_screen.dart` (SOC-1)
- **Scope**: Introduce a `UrlLauncher`/`Clipboard` collaborator (mirroring scan's `ScannerLauncher`
  seam); default = production `launchUrl`/`Clipboard.setData`. `_openKofi` (:27-41) and
  `_copyAddress` (:43-49) call the seam; wire the default through the existing donation DI.
- **Files**: `lib/features/donation/donation_screen.dart`; new seam file; donation DI class.
- **Test-first**: unit/widget test for bad-URL (`Uri.tryParse` null), launch-refused (seam returns
  false), and copy-success snackbar branches.
- **Done**: failure branches covered; donation tests green; constructor default unchanged for
  callers.
- **Parallel-safe**: yes (donation-only files).

### Task 6 — Shared `ImageSizeResolver` (TST-2)
- **Scope**: Promote `_resolveImageSize` (`capture_review_screen.dart:17-37` and the verbatim
  duplicate `edit_crop_screen.dart:17-37`) into one `ImageSizeResolver` collaborator. Give the
  production default a host-safe path (decode dimensions via the injected `readBytes` instead of a
  live `FileImage` stream, or a resolver that doesn't touch the image cache under test).
- **Files**: new `lib/features/library/image_size_resolver.dart` (or shared util); edits to
  `capture_review_screen.dart` and `edit_crop_screen.dart`.
- **Test-first**: unit test that the default resolves dimensions from bytes without hanging; both
  screens' injection points still accept an override.
- **Done**: one resolver; `capture_review_screen_test.dart` (510 LOC) unchanged & green; no host-test
  hang.
- **Parallel-safe**: yes (independent of Tasks 1–5).

---

## Risks & mitigations

- **Timing/lifecycle regression** — `if (!mounted) return` guards and post-frame ordering are
  load-bearing on real devices. *Mitigation*: `ScanBatchController` stays widget-agnostic and exposes
  a state stream/`ChangeNotifier`; the screen keeps the mounted-guard at the render boundary. Verify
  the save-loop on device (both platforms) before claiming done.
- **Snackbar count drift** — folding two call sites into `ReviewAndSave` risks a double snackbar or a
  lost one. *Mitigation*: the "exactly once on null result" widget test (Task 4) locks the count;
  `_pickFilter` (no snackbar) and home (snackbar) behaviours are preserved per call site.
- **Host-test hang from real decode** — the current `_resolveImageSize` default streams a real
  `FileImage`. *Mitigation*: Task 6 makes the default decode-from-bytes / cache-free; keep the
  injection seam so existing tests can still stub.
- **DI shape churn breaking tests** — donation seam / controller wiring could alter constructor
  signatures. *Mitigation*: all new collaborators get production defaults; public constructors and
  `ScanDependencies` fields stay stable (behaviour-preserving constraint).
- **id-scan error-string divergence** — id-scan uses `idScanErrorSave`, not `commonErrorSaveDocument`.
  *Mitigation*: `ScanBatchController` reports failure as state; the **string** is chosen by each
  screen, preserving the divergence.

---

## Verification commands

Run from `apps/mobile/`.

```bash
# TDD — new use-case + seams (host)
flutter test test/features/scan/scan_batch_controller_test.dart
flutter test test/features/library/                 # review/import + resolver
flutter test test/features/donation/                # url/clipboard seam
flutter test test/features/scan/capture_review_screen_test.dart   # 510 LOC, must stay green

# BDD — scan flows stay green (host)
flutter test test/bdd/                               # includes generated scan feature tests

# Lint / format (zero-warning bar)
flutter analyze
dart format --output=none --set-exit-if-changed lib test

# Device — scan save-loop + native (BOTH platforms, non-negotiable)
flutter test integration_test/scan_save_loop_device_test.dart -d <android-device-id>
flutter test integration_test/scan_save_loop_device_test.dart -d <ios-device-id>
```

Do not claim done until the scan save-loop is green on a real Android device **and** a real iOS
device, and the paste/summary of that green run is recorded per the verify-then-claim rule.
