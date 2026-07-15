# P02 — Timeouts Everywhere (no async flow can hang forever)

**Tier 1 (Safety) · Effort S–M · Risk Low · Depends on: P00 `withIsolateTimeout` (+ `AppLogger`) · Device verification: both (real Android AND real iOS)**

## Summary

P02 adopts the `withIsolateTimeout<T>()` helper from P00 (plus targeted `.timeout(...)`
guards on native/HTTP async) so that no async flow in the app can hang indefinitely: a
stalled network POST, a wedged native OpenCV isolate, a slow ML-Kit `processImage`, or a
never-returning PDF open. The overriding rule is **success-path behavior must not change**
— timeouts only add a bounded failure edge, mapped to the existing error/offline states.
Every task tests **both** the normal path (fast fake → same result as today) **and** the
timeout path (slow fake → bounded, mapped failure).

## Global constraints (apply to every task in this plan)

- **Behavior-preserving.** Public APIs stay stable so the ~25k-LOC suite (179 host test
  files, 42 `.feature` BDD specs, 66 integration tests) stays GREEN. Timeouts are chosen
  generously (see per-task durations) so no currently-passing normal-path test can trip
  them; where a duration must be injectable for tests, it is added as a const-defaulted
  constructor/parameter (additive, no breaking change).
- **TDD.** Each task lists failing-first tests added BEFORE implementation — always a pair:
  normal-path (unchanged result) and timeout-path (mapped failure).
- **BDD.** No behavior is *removed*, so no scenario is deleted. Scenarios that must stay
  green: `test/bdd/feedback_validation.feature`; `integration_test/o4_recognized_text.feature`
  (OCR), `c2_pdf_preview.feature` (PDF open), `e2_flatten.feature`/`g1_grayscale.feature`/
  `g3_auto_color.feature`/`g4_filter_picker.feature` (the `compute()`-backed enhance/warp
  paths), `k1_rotate_page.feature` (rotate isolate). Add **one new host BDD scenario**
  `test/bdd/feedback_timeout.feature` ("a stalled submit surfaces the offline message,
  spinner clears") — the only user-visible new behavior.
- **Both platforms.** All of these touch native / IO / async and MUST be verified on a
  real Android AND a real iOS device via the named `integration_test/*_device_test.dart`
  runs below. "Passes on host" is not done here.
- **Small independent tasks.** SF-1 (feedback), the ML-Kit OCR timeout, the PDF-open
  timeout, and the compute()-adoption tasks share no state — dispatch to separate
  subagents. The only shared dependency is P00's `withIsolateTimeout`/`AppLogger` (already
  landed before P02 starts).

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| SF-1a | `feedback_service.dart:44` — `await httpClient.post(base.replace(path: '/challenge'))` | POST has **no** `.timeout(...)`. | A stalled TCP connection never returns → the outer `submit()` never completes. | LIVE |
| SF-1b | `feedback_service.dart:69-73` — `await httpClient.post(base.replace(path: '/feedback'), ...)` | POST has **no** `.timeout(...)`. Contrast `feedback_availability.dart:28` which **does** `.timeout(timeout)` (3s default). | Same stall; and because `feedback_screen.dart:60/73` sets `_submitting=true` in a `try/finally`, a hung POST leaves the submit spinner up **forever** (the `finally` only runs when `submit()` returns). | LIVE |
| OCR-TMO | `mlkit_ocr_engine.dart:31-33` — `await recognizer.processImage(InputImage.fromFilePath(...))` | No timeout on the native ML-Kit call. | A wedged native recognizer hangs the OCR future indefinitely (OCR runs off the UI isolate but still blocks the awaiting flow / any progress UI). | LIVE (robustness) |
| PDF-TMO | `pdf_preview_screen.dart:52` — `await widget.opener(widget.pdfPath)` | No timeout on the PDF-document open. | A never-returning opener leaves `_loading=true` forever (spinner never resolves; `_error` never set). | LIVE (robustness) |
| CMP-10 | 10 UNGUARDED `compute()` sites: `warp_enhancer.dart:30`, `perspective_warper.dart:23`, `coons_warper.dart:23`, `drift_document_repository.dart:606`, `auto_enhancer.dart:58`, `color_enhancer.dart:12`, `grayscale_enhancer.dart:14`, `filter_picker_strip.dart:112` | These `compute()` calls have no timeout. `native_page_processor.dart:47` and `opencv_edge_detector.dart:44` are the only guarded ones. | A wedged native/codec isolate (cannot be killed from Dart) hangs the enhance/warp/rotate/thumbnail future. `drift_document_repository.dart:606` is an **unguarded full JPEG decode/encode** in the rotate path. | LIVE (robustness) |
| DART-FALLBACK | `DartPageProcessor` awaits `warpAndEnhance` (`dart_page_processor.dart:44`), `warper.warp` (`:57`), and `enhance(...)` (`:34,:49,:64`) | The pure-Dart fallback pipeline has no timeout of its own; each of those ultimately re-enters an unguarded `compute()` from CMP-10. | Same hang class in the fallback path. | LIVE (robustness) |

## Definition of done

- Both feedback POSTs (`:44`, `:69`) carry a `.timeout(...)`; a `TimeoutException` is
  mapped to `FeedbackOffline` (same result the existing offline branch already produces at
  `feedback_service.dart:76`). Timeout duration is an injectable const-defaulted field on
  `FeedbackService` (default e.g. 15s, comfortably above any real submit).
- The feedback submit spinner (`_submitting`) is proven to clear on a stalled connection
  (new BDD + widget test with an injected slow `http.Client`).
- `mlkit_ocr_engine.dart` `processImage` and `pdf_preview_screen.dart` opener each carry a
  timeout mapped to their existing failure state (empty/failed OCR result; `_error=true`
  preview state).
- All 10 CMP-10 `compute()` sites route through P00's `withIsolateTimeout`/
  `computeWithTimeout` with per-site durations; the two already-guarded sites are refactored
  to use the same helper (DRY) **without changing their existing 5s semantics**.
- Every migrated site has a normal-path test (identical result to today) AND a
  timeout-path test (bounded failure / `null` fallback, mapped exactly as the site's
  existing `catch` already does).
- `flutter analyze` zero-warning; full host suite green; the named device tests green on
  Android AND iOS.

## Before → After

| Flow | Before | After |
|------|--------|-------|
| Feedback `/challenge` + `/feedback` POST | no timeout → hangs; spinner stuck forever | `.timeout(15s)` → `TimeoutException`→`FeedbackOffline`; spinner clears |
| ML-Kit `processImage` | no timeout | `.timeout(N s)` → maps to existing empty/failed OCR result |
| PDF `opener(pdfPath)` | no timeout → spinner forever | `.timeout(N s)` → existing `_error=true` state |
| 10 `compute()` sites | unbounded | `withIsolateTimeout(..., timeout: <per-site>)` → returns `null`/falls back exactly as today's `catch` |
| 2 guarded `compute()` sites | ad-hoc `.timeout` | same 5s semantics, now via shared helper |
| Success path | (baseline) | **unchanged** — verified by paired normal-path tests |

## Tasks

### T1 — Feedback POSTs: add timeouts, map to `FeedbackOffline` (SF-1a/SF-1b)
- **Scope.** Add an injectable `Duration timeout` (const-defaulted, e.g. 15s) to
  `FeedbackService`. Apply `.timeout(timeout)` to both `httpClient.post(...)` calls
  (`:44`, `:69`). Add `on TimeoutException` (before the existing `on
  http.ClientException`) returning `const FeedbackOffline()` — reuse the exact result the
  offline branch already returns so the UI copy is unchanged (`l10n.feedbackOffline`,
  `feedback_screen.dart:21`).
- **Files.** `lib/features/feedback/feedback_service.dart`;
  `test/features/feedback/feedback_service_test.dart`.
- **Test-first.** (a) normal path: a fast fake `http.Client` returns 201 → `FeedbackSuccess`
  (unchanged); (b) timeout path: a fake client whose `post` never completes → with a short
  injected `timeout` the call returns `FeedbackOffline` within the bound (use `fakeAsync`
  or a `Completer` that never completes + a small timeout). Watch fail, implement.
- **Done-criteria.** Both tests green; existing feedback service/screen tests green.
- **Parallel-safe?** Yes (self-contained file).

### T2 — Feedback screen: prove the submit spinner clears on stall (new BDD)
- **Scope.** No production change beyond T1; this task adds the behavioral proof. New host
  BDD `test/bdd/feedback_timeout.feature` scenario: given a stalled submit, when the user
  taps submit, then the offline snackbar shows and the submit control is re-enabled (i.e.
  `_submitting` is false again). Generate the `*_test.dart` via `build_runner`; add any
  new step to `test/step/`.
- **Files.** `test/bdd/feedback_timeout.feature`, generated `test/bdd/feedback_timeout_test.dart`,
  step(s) in `test/step/`, a fake slow `http.Client` injected via `FeedbackDependencies`.
- **Test-first.** The `.feature` scenario IS the failing test — write it, run
  `dart run build_runner build --delete-conflicting-outputs`, watch it fail (spinner stuck
  today if run against un-timed-out code / passes only after T1), implement steps.
- **Done-criteria.** New scenario green; `test/bdd/feedback_validation.feature` still green.
- **Parallel-safe?** Yes; logically sequenced after T1 (needs the timeout), so mark
  **depends on T1**.

### T3 — ML-Kit OCR: timeout `processImage` (OCR-TMO)
- **Scope.** Add an injectable `Duration timeout` (const-defaulted) to `MlKitOcrEngine`.
  Wrap `recognizer.processImage(...)` at `:31` with `.timeout(timeout)`; on
  `TimeoutException`, return the same shape the engine returns for "nothing recognized"
  (`OcrResult(text: '', words: const [])`) — do NOT throw, so callers behave as today for
  an unreadable image. Keep the `finally` (recognizer close + temp cleanup) intact.
  (Note: the sync temp-write at `:28` is P04's concern, not P02 — do not touch it here.)
- **Files.** `lib/features/library/ocr/mlkit_ocr_engine.dart`; OCR engine test (host uses a
  fake through the `OcrEngine` seam) + device coverage.
- **Test-first.** Since ML-Kit is native, host-test the timeout at the seam: a fake
  `OcrEngine`/injected recognizer that never completes → bounded empty `OcrResult`. Watch
  fail, implement. Real recognition is device-verified.
- **Done-criteria.** Host timeout test green; `o4_recognized_text` normal OCR unchanged on
  device (Android + iOS).
- **Parallel-safe?** Yes.

### T4 — PDF preview: timeout the document open (PDF-TMO)
- **Scope.** In `pdf_preview_screen.dart._open()` (`:50`), wrap
  `await widget.opener(widget.pdfPath)` (`:52`) with `.timeout(...)` (injectable const
  default). On timeout, fall into the existing `catch (_)` behavior (`_loading=false;
  _error=true`) — i.e. route the `TimeoutException` into the same error state already
  rendered, so no new UI copy is needed.
- **Files.** `lib/features/library/pdf_preview_screen.dart`;
  `test/features/library/pdf_preview_screen_test.dart`.
- **Test-first.** (a) normal path: a fast fake opener → controller set, spinner gone
  (unchanged); (b) timeout path: an opener that never completes → after the bound,
  `_error=true` and the error UI shows. Watch fail, implement.
- **Done-criteria.** Both host tests green; `c2_pdf_preview` normal preview unchanged on
  device (Android + iOS).
- **Parallel-safe?** Yes.

### T5 — Adopt `withIsolateTimeout` at the two-step warp path (`perspective_warper.dart:23`, `coons_warper.dart:23`)
- **Scope.** Route the `compute()` in `perspective_warper.dart:23` and
  `coons_warper.dart:23` through P00's helper with a generous per-site timeout (these are
  full-image warps — size-bounded because camera max is 12.5MP; pick e.g. 12s). On
  timeout, return the value each site already returns for failure (the warpers' never-throws
  contract → `null` so the caller de-shadows the un-warped frame, matching
  `dart_page_processor.dart:57-64`).
- **Files.** `lib/features/library/perspective_warper.dart`,
  `lib/features/library/coons_warper.dart`; their tests.
- **Test-first.** normal-path parity (same output bytes as today for a fixture) + timeout
  path (injected slow compute fn → `null`, caller falls back). Watch fail, implement.
- **Done-criteria.** Tests green; `e1_crop`/`e2_flatten` unchanged on device (both platforms).
- **Parallel-safe?** Yes (two independent files; can be one subagent each).

### T6 — Adopt `withIsolateTimeout` at the fused warp+enhance path (`warp_enhancer.dart:30`)
- **Scope.** Wrap the `compute(_warpEnhanceFn, ...)` at `warp_enhancer.dart:30` with the
  helper (generous timeout, e.g. 12s). On timeout return `null` (the function's documented
  never-throws/`null`-on-failure contract at `warp_enhancer.dart:20-23`), so
  `DartPageProcessor` (`:44`) falls back to enhancing the un-warped frame exactly as it
  does on any current failure.
- **Files.** `lib/features/library/warp_enhancer.dart`; its test.
- **Test-first.** normal parity + timeout→`null`→fallback. Watch fail, implement.
- **Done-criteria.** Tests green; `e2_flatten`/`e4_mixed_reedit` unchanged on device.
- **Parallel-safe?** Yes.

### T7 — Adopt `withIsolateTimeout` at the three enhancer `compute()` sites (`auto_enhancer.dart:58`, `color_enhancer.dart:12`, `grayscale_enhancer.dart:14`)
- **Scope.** Wrap each `enhance()` `compute()` with the helper (generous timeout). These
  currently return the enhanced `Uint8List` with no failure branch, so on timeout throw a
  well-typed error and let the *callers'* existing `catch (_)` (e.g.
  `dart_page_processor.dart:34-38,:49,:64`) fall back to the un-enhanced bytes — preserving
  the "never lose a page" contract. Verify the callers already catch (they do:
  `:34-38`, `:49`, `:64`).
- **Files.** `lib/features/library/auto_enhancer.dart`, `color_enhancer.dart`,
  `grayscale_enhancer.dart`; their tests.
- **Test-first.** For each: normal parity + timeout throws → verify `DartPageProcessor`
  returns the input bytes (page not lost). Watch fail, implement.
- **Done-criteria.** Tests green; `g1_grayscale`/`g3_auto_color` unchanged on device (both platforms).
- **Parallel-safe?** Yes (three independent files).

### T8 — Adopt `withIsolateTimeout` at the rotate isolate (`drift_document_repository.dart:606`)
- **Scope.** Wrap the `compute(rotateAndBakeJpeg, ...)` (unguarded full JPEG
  decode/encode) at `:606` with the helper. Preserve the existing failure contract: today
  a `null` result throws `DocumentSaveException('regenerate: undecodable base image')`
  (`:610-612`); on timeout throw the same (or a clearly-typed timeout) exception so callers
  surface the existing rotate-error UI (`page_viewer_screen.dart:467` `viewerRotateError`).
- **Files.** `lib/features/library/drift/drift_document_repository.dart`; repository test.
- **Test-first.** normal rotate parity + timeout → the rotate flow raises and the
  page-viewer shows `viewerRotateError` (widget test with an injected slow compute). Watch
  fail, implement.
- **Done-criteria.** Tests green; `k1_rotate_page` unchanged on device (Android + iOS).
- **Parallel-safe?** Yes.

### T9 — Adopt `withIsolateTimeout` at the filter-thumbnail compute (`filter_picker_strip.dart:112`)
- **Scope.** Wrap `compute(_thumbFn, bytes)` at `:112` with the helper (short timeout —
  it's a thumbnail; e.g. 6s). On timeout, degrade to the strip's existing "no thumbnail"
  behavior (whatever the current `catch`/null path renders) rather than hanging the strip.
- **Files.** `lib/features/scan/widgets/filter_picker_strip.dart`; its widget test.
- **Test-first.** normal thumbnail renders + timeout → placeholder/no-thumb, strip still
  interactive. Watch fail, implement.
- **Done-criteria.** Tests green; `g4_filter_picker` unchanged on device (both platforms).
- **Parallel-safe?** Yes.

### T10 — Refactor the two already-guarded sites onto the shared helper (DRY)
- **Scope.** Rewrite `native_page_processor.dart:44-50` and `opencv_edge_detector.dart:20`
  to call `withIsolateTimeout`/`computeWithTimeout` instead of hand-rolled `.timeout` —
  **keeping the exact 5s default and the `null`-on-timeout/error semantics** (the
  `NativePageProcessor.timeout` field stays a public const-defaulted field). Pure
  refactor: identical behavior, one code path.
- **Files.** `lib/features/library/native_page_processor.dart`,
  `lib/features/scan/opencv_edge_detector.dart`; their tests (unchanged assertions).
- **Test-first.** No new behavior — run the existing tests, refactor, confirm still green
  (add a test only if the current suite doesn't already assert the timeout→`null` edge).
- **Done-criteria.** Existing native/edge tests green unchanged; no behavior delta.
- **Parallel-safe?** Yes; low value if time-boxed — do it after the live-risk tasks.

## Risks & mitigations

- **Risk: a too-tight timeout trips a slow-but-legitimate operation (large page, slow
  device), changing success behavior.** Mitigation: per-task durations are generous and
  **injectable/const-defaulted**; device runs on real Android + iOS confirm the normal
  path never trips; native processing is already size-bounded (12.5MP camera cap per the
  native-pipeline memory).
- **Risk: mapping a timeout to the wrong failure state changes UX.** Mitigation: each task
  routes the `TimeoutException` into the **same** result/branch the site already produces
  on failure (offline / empty OCR / `_error` / `null` fallback) — no new copy, no new
  state, except the one intentional new `feedback_timeout` BDD scenario.
- **Risk: wedged native isolate keeps running after the timeout (can't be killed from
  Dart).** Mitigation: this is inherent (documented in `native_page_processor.dart:22-26`);
  the timeout detaches the awaiting future so the UI recovers — that's the accepted, tested
  behavior, not a regression.
- **Risk: `fakeAsync` vs real `.timeout` interaction in tests.** Mitigation: prefer a
  never-completing `Completer` + a short injected duration and real `await`, or `fakeAsync`
  with `elapse` — pick one per test and keep durations tiny in tests.

## Verification commands

Run from `apps/mobile/`.

```bash
# Regenerate BDD after adding the feedback_timeout scenario
dart run build_runner build --delete-conflicting-outputs

flutter analyze

# Host: paired normal + timeout tests
flutter test test/features/feedback/feedback_service_test.dart
flutter test test/bdd/feedback_timeout_test.dart
flutter test test/features/library/pdf_preview_screen_test.dart
flutter test test/features/library/          # warp/enhance/rotate host tests
flutter test test/features/scan/             # filter strip, edge detector

# Full host suite (regression guardrail)
flutter test

# DEVICE — both platforms (native / IO / async): normal path must be UNCHANGED
flutter test integration_test/o4_recognized_text_device_test.dart -d <android-device-id>
flutter test integration_test/o4_recognized_text_device_test.dart -d <ios-device-id>
flutter test integration_test/c2_pdf_preview_device_test.dart      -d <android-device-id>
flutter test integration_test/c2_pdf_preview_device_test.dart      -d <ios-device-id>
flutter test integration_test/e2_flatten_device_test.dart          -d <android-device-id>
flutter test integration_test/e2_flatten_device_test.dart          -d <ios-device-id>
flutter test integration_test/g3_auto_color_device_test.dart       -d <android-device-id>
flutter test integration_test/g3_auto_color_device_test.dart       -d <ios-device-id>
flutter test integration_test/k1_rotate_page_device_test.dart      -d <android-device-id>
flutter test integration_test/k1_rotate_page_device_test.dart      -d <ios-device-id>
```

State the exact command + paste the green summary before claiming any task done. (If a
`*_device_test.dart` for a named `.feature` does not yet exist, that device gap must be
named explicitly, not skipped silently.)
