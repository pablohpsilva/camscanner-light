# P00 — Shared Primitives (logging seam, isolate-timeout helper, temp-file service)

**Tier 0 (foundation) · Effort S–M · Risk Low · Depends on: none (this is the SEQUENCING ROOT) · Device verification: host-only for P00 itself (adopters verify on device)**

## Summary

P00 introduces three small, injectable infrastructure primitives as **purely additive
code**: an `AppLogger` error-reporting seam (plus a `FlutterError.onError` install in
`main()`), a `withIsolateTimeout<T>()` helper that wraps `compute()` with a timeout, and a
`TempFileWriter` service that owns temp-dir create/write/cleanup. Nothing existing is
rewired — P00 ships the primitives and their tests only, so no caller changes and no
behavior change. P02, P06, P10, and P14 are the plans that *consume* these primitives;
adopting them at call sites is deliberately out of scope here.

## Global constraints (apply to every task in this plan)

- **Behavior-preserving.** Public APIs/interfaces stay stable so the existing ~25k-LOC
  suite (179 host test files, 42 `.feature` BDD specs, 66 integration tests) stays GREEN.
  P00 adds new files/symbols only; it must not touch any existing call site, so no test
  or build may break.
- **TDD.** Every task below lists failing-first unit tests to add BEFORE implementation.
- **BDD.** P00 is infrastructure with no new user-facing behavior, so it adds **no new
  `.feature` scenarios**. It must keep every existing scenario green — in particular the
  feedback/validation, feature-flag, and startup-related specs that touch the
  `*Dependencies` composition roots P00 threads `AppLogger` through.
- **Both platforms.** P00's primitives are host-unit-testable (pure Dart + `dart:io`
  temp dirs). `TempFileWriter` touches the filesystem and MUST additionally be smoke-run
  on a real Android AND a real iOS device by whichever plan first adopts it (P10/P14) —
  named here as an explicit hand-off, not a silent gap.
- **Small independent tasks.** Tasks T1–T7 share no state and can each go to a separate
  subagent. The only ordering note: `main()` wiring (T3) reads the `AppLogger` interface
  from T1, and the composition-root threading (T2) also reads T1 — so land T1 first, then
  T2/T3 in parallel. Everything else is fully independent.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| LOG-1 | 59 `catch (_)` blocks across `lib/` (verified count) | Errors are swallowed with zero reporting. There is **no `Logger`, no `reportError`, no `FlutterError.onError`, no Crashlytics/Sentry** anywhere in `lib/`. | On-device failures (a wedged crop, a failed export, a swallowed OCR error) leave no diagnosable trace. | latent (hardening — no crash, but blind) |
| LOG-2 | `home_screen.dart:147` (`debugPrint('HomeScreen cold-start failed while $step: $error')`) | The **only** `debugPrint` in the codebase; ad-hoc, unstructured, not injectable, stripped in release. | Cold-start diagnostics are lost in release builds and can't be routed to a reporter. | latent (hardening) |
| TMO-1 | 10 `compute()` sites; only 2 guarded — `native_page_processor.dart:44` (`.timeout` at `:47`) and `opencv_edge_detector.dart:20` (guarded at `:44`). 8 UNGUARDED: `warp_enhancer.dart:30`, `perspective_warper.dart:23`, `coons_warper.dart:23`, `drift_document_repository.dart:606`, `auto_enhancer.dart:58`, `color_enhancer.dart:12`, `grayscale_enhancer.dart:14`, `filter_picker_strip.dart:112`. | The timeout pattern is copy-pasted per-site (and mostly missing). No shared helper exists to make "guarded `compute`" the default. | latent (P00 only *defines* the helper; the live risk is fixed in P02) | 
| TMP-1 | 7 duplicated `Directory.systemTemp.createTemp` sites — `drift_document_repository.dart:367,400,436,489,538`; `mlkit_ocr_engine.dart:27`; `file_archiver.dart:46` | Temp-dir creation + write + best-effort cleanup is hand-rolled and duplicated 7×; cleanup style differs per site (some `deleteSync`, some `try/catch`). | Duplicated I/O boilerplate; inconsistent cleanup; no single injectable seam for tests to intercept temp writes. | latent (P00 defines + tests; adoption is P10/P14) |

## Definition of done

- `AppLogger` abstract interface + a default `PrintAppLogger` (or `SilentAppLogger` for
  tests) exist, unit-tested.
- `AppLogger` is threaded through `ScanDependencies`, `LibraryDependencies`, and
  `FeedbackDependencies` as a const-defaulted factory typedef — with the production
  default preserving today's behavior (a no-op/print logger), so **no existing test that
  constructs a default `*Dependencies` changes**.
- `main()` installs `FlutterError.onError` to forward to the default `AppLogger`, and the
  one `home_screen.dart:147` `debugPrint` is replaced by a call **through the injected
  logger** (behavior-preserving: default logger still prints in debug).
- `withIsolateTimeout<T>()` exists with unit tests for the normal path, the timeout path,
  and the isolate-error path. **No call site is migrated in P00.**
- `TempFileWriter` exists with create/write/cleanup + unit tests. **No call site is
  migrated in P00.**
- `flutter analyze` is zero-warning; `flutter test` is fully green.

## Before → After

| Aspect | Before | After (P00) |
|--------|--------|-------------|
| Error reporting seam | none (59 silent `catch (_)`) | `AppLogger` interface injectable via all 3 `*Dependencies`; global `FlutterError.onError` installed in `main()` |
| Ad-hoc logging | 1 raw `debugPrint` in `home_screen.dart:147` | routed through injected `AppLogger` (default still prints in debug) |
| Guarded `compute` | copy-pasted at 2 sites, missing at 8 | single `withIsolateTimeout<T>()` helper available (adoption deferred to P02) |
| Temp files | 7 duplicated `createTemp` blocks | `TempFileWriter` service available (adoption deferred to P10/P14) |
| Call sites | unchanged | **unchanged** (P00 is additive; existing tests untouched) |

## Tasks

### T1 — Define `AppLogger` interface + default implementations
- **Scope.** New file `lib/core/logging/app_logger.dart` (create `lib/core/` if absent).
  Define `abstract class AppLogger { void error(Object error, {StackTrace? stackTrace, String? context}); }`
  plus `class PrintAppLogger implements AppLogger` (prints in debug, no-op-safe in
  release) and `class SilentAppLogger implements AppLogger` (test double, records calls).
  Keep the surface minimal — one `error(...)` method; do not add levels we don't need yet
  (KISS).
- **Files.** `lib/core/logging/app_logger.dart` (new); `test/core/logging/app_logger_test.dart` (new).
- **Test-first.** Write `app_logger_test.dart` asserting: `SilentAppLogger` records the
  error/stack/context it was given; `PrintAppLogger.error(...)` does not throw. Run it,
  watch it fail (no class yet), then implement.
- **Done-criteria.** New unit test green; `flutter analyze` clean; no existing file edited.
- **Parallel-safe?** Yes — pure new files. **T2 and T3 depend on this landing first.**

### T2 — Thread `AppLogger` through the three `*Dependencies` composition roots
- **Scope.** Add a `final AppLogger Function() logger;` factory typedef field (const-
  defaulted to `() => const PrintAppLogger()`) to `ScanDependencies`,
  `LibraryDependencies`, and `FeedbackDependencies`. Do **not** consume it anywhere yet —
  just make it injectable. Because the default is const and behavior-preserving, every
  existing `const ScanDependencies()` / default-constructed root keeps compiling and
  behaving identically.
- **Files.** `lib/features/scan/scan_dependencies.dart`,
  `lib/features/library/library_dependencies.dart`,
  `lib/features/feedback/feedback_dependencies.dart`; matching `test/` files for each root
  (add one assertion per root).
- **Test-first.** For each root add a test: "default root exposes a non-null `logger()`
  and it is a `PrintAppLogger`" and "an override is honored" (`copyWith`/constructor
  override returns the injected fake). Watch fail, implement.
- **Done-criteria.** Three roots expose `logger`; all existing dependency-root tests still
  green (they must, since the default is unchanged behavior).
- **Parallel-safe?** Yes across the three roots (independent files) once T1 has landed.

### T3 — Install `FlutterError.onError` + retire the lone `debugPrint`
- **Scope.** In `main()` (`lib/main.dart:16`), after `WidgetsFlutterBinding
  .ensureInitialized()`, set `FlutterError.onError = (details) { logger.error(details
  .exception, stackTrace: details.stack, context: 'FlutterError'); FlutterError
  .presentError(details); };` using a default `PrintAppLogger` (keep `presentError` so
  the red-screen/console behavior in debug is unchanged). Separately, replace
  `home_screen.dart:147` `debugPrint(...)` with a call through the injected
  `libraryDependencies.logger()` (falls back to today's print behavior by default).
- **Files.** `lib/main.dart`, `lib/features/library/home_screen.dart`; tests in
  `test/features/library/` for the home-screen path.
- **Test-first.** Add a widget/unit test that injects a `SilentAppLogger` into
  `LibraryDependencies` and asserts a forced cold-start failure calls `logger.error(...)`
  with the step context (was previously only `debugPrint`). Watch fail, implement.
  For `FlutterError.onError`, add a unit test that pumps a `FlutterError.reportError` and
  asserts the installed handler forwards to the logger (guard: restore the previous
  `FlutterError.onError` in a `finally` in the test body — see the platform-override
  cleanup memory).
- **Done-criteria.** No `debugPrint` remains in `lib/` (grep = 0); cold-start-failure
  scenarios (existing startup BDD/host tests) stay green; `FlutterError.onError` install
  verified by test.
- **Parallel-safe?** Yes once T1 has landed (independent of T2, but both read T1).

### T4 — Define `withIsolateTimeout<T>()`
- **Scope.** New file `lib/core/async/with_isolate_timeout.dart`:
  `Future<T> withIsolateTimeout<T>(FutureOr<T> Function() run, {required Duration timeout, FutureOr<T> Function()? onTimeout});`
  — internally `Future(() => run()).timeout(timeout, onTimeout: onTimeout)`. Provide a
  thin convenience `computeWithTimeout<Q,R>(ComputeCallback<Q,R> fn, Q message, {Duration timeout})`
  that wraps `compute(fn, message).timeout(...)` and returns `null`-or-throws to match the
  existing guarded pattern in `native_page_processor.dart:47`. Document that a wedged
  native isolate cannot be killed — the timeout only detaches the awaiting future (mirror
  the doc comment already in `native_page_processor.dart:22-26`). **Do not migrate any
  call site.**
- **Files.** `lib/core/async/with_isolate_timeout.dart` (new);
  `test/core/async/with_isolate_timeout_test.dart` (new).
- **Test-first.** Tests: (a) normal path returns the value; (b) a `run` that never
  completes throws `TimeoutException` after `timeout`; (c) `onTimeout` fallback is used
  when provided; (d) an error thrown inside `run` propagates unchanged (not masked by the
  timeout). Use `fakeAsync`/short durations. Watch fail, implement.
- **Done-criteria.** All four unit tests green; helper is pure (no Flutter widget deps).
- **Parallel-safe?** Yes — fully independent new files. **P02 consumes this.**

### T5 — Define `TempFileWriter` service
- **Scope.** New file `lib/core/io/temp_file_writer.dart`. Interface owning the pattern
  duplicated at the 7 sites: `Future<Directory> createTempDir(String prefix)`,
  `Future<File> writeBytes(Directory dir, String name, Uint8List bytes, {bool sync = false})`,
  and `Future<void> cleanup(Directory dir)` (best-effort, swallow-and-log via `AppLogger`).
  Default impl wraps `Directory.systemTemp.createTemp`. Keep the `sync` option so the
  ML-Kit adopter (P02/P10) can move off `writeAsBytesSync` deliberately rather than P00
  silently changing timing.
- **Files.** `lib/core/io/temp_file_writer.dart` (new);
  `test/core/io/temp_file_writer_test.dart` (new).
- **Test-first.** Tests: creates a unique dir per call; `writeBytes` produces a file with
  exact bytes; `cleanup` removes the dir and does not throw if the dir is already gone;
  cleanup failure is reported via an injected `SilentAppLogger`, not rethrown. Watch fail,
  implement.
- **Done-criteria.** All unit tests green on host.
- **Parallel-safe?** Yes — independent new files. **P10/P14 consume this and own the
  on-device verification of temp I/O.**

### T6 — Add `TempFileWriter` to `LibraryDependencies` (injectable, unused)
- **Scope.** Expose a `TempFileWriter Function() tempFiles` factory on
  `LibraryDependencies` (const-defaulted), so the repository/archiver adopters in P10/P14
  can inject a fake. **Not consumed in P00.**
- **Files.** `lib/features/library/library_dependencies.dart` + its dependency-root test.
- **Test-first.** "default exposes a `TempFileWriter`; override honored." Watch fail,
  implement.
- **Done-criteria.** Root test green; no consumer wired yet.
- **Parallel-safe?** Yes (depends on T5 for the type; can start once T5's interface name
  is fixed — treat T5→T6 as the one intra-plan dependency).

### T7 — Docs: mark P00 as the sequencing root
- **Scope.** No code. Confirm in this file (already stated) that P02 (timeouts), P06
  (controllers), P10, and P14 declare `Depends on: P00`. Ensure the primitives' public
  signatures are frozen so downstream plans can be authored against them without churn.
- **Files.** this doc only.
- **Done-criteria.** Signatures of `AppLogger`, `withIsolateTimeout`, `TempFileWriter`
  restated verbatim in the "Before → After" and Tasks sections (done).
- **Parallel-safe?** Yes.

## Risks & mitigations

- **Risk: threading `logger` through const `*Dependencies` breaks `const` construction in
  existing tests.** Mitigation: default the field to a `const`-constructible
  `() => const PrintAppLogger()` factory; verify with `flutter analyze` and by running the
  full dependency-root test set (T2).
- **Risk: `FlutterError.onError` install changes debug red-screen behavior.** Mitigation:
  call `FlutterError.presentError(details)` inside the handler (preserves default
  presentation); cover with a test.
- **Risk: a test globally sets `FlutterError.onError` and leaks into other tests.**
  Mitigation: save/restore in a `finally` inside the test body (not `tearDown`), per the
  platform-override-cleanup project memory.
- **Risk: scope creep into adoption.** Mitigation: P00 explicitly migrates zero call
  sites; adoption lives in P02/P06/P10/P14. Reviewer rejects any P00 diff that edits one
  of the 8 `compute()` or 7 `createTemp` sites.

## Verification commands

Run from `apps/mobile/`.

```bash
# Zero-warning lint bar
flutter analyze

# New primitive unit tests (fail-first, then green)
flutter test test/core/logging/app_logger_test.dart
flutter test test/core/async/with_isolate_timeout_test.dart
flutter test test/core/io/temp_file_writer_test.dart

# Composition-root + home-screen regression (must stay green)
flutter test test/features/library/
flutter test test/features/scan/
flutter test test/features/feedback/

# Full host suite (guardrail: nothing regressed)
flutter test

# Prove the lone debugPrint is gone
grep -rn "debugPrint" lib   # expect: no output
```

P00 has **no device step of its own** (its primitives are host-unit-testable). The
`TempFileWriter` filesystem behavior is verified on a real Android AND iOS device by the
first adopting plan (P10/P14) via their `integration_test/*_device_test.dart` runs, e.g.:

```bash
flutter test integration_test/i1_export_image_device_test.dart -d <android-device-id>
flutter test integration_test/i1_export_image_device_test.dart -d <ios-device-id>
```

This hand-off is named explicitly so the temp-I/O device coverage is not a silent gap.
