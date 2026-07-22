# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# CamScanner-light — project notes for Claude

Flutter document scanner. Nx monorepo (pnpm), but there is a single app in
`apps/mobile/` — run all Flutter commands from `apps/mobile/`, not the repo root.

## Load-on-demand detail docs

Keep this file lean. The deep, task-specific how-tos live in `docs/claude/` and
are loaded only when the task matches. **Before doing one of these, read the
matching doc — do not reproduce its steps from memory** (that is where stale
recall causes real damage):

- **Releasing to TestFlight / App Store, or anything IAP** → `docs/claude/ios-release.md`
- **Installing a build on a real device** → `docs/claude/device-install.md`
- **Producing an Android release** → `docs/claude/android-release.md`
- **Reviewing / changing persistence, native pipeline, builds, or IAP** →
  `docs/claude/review-checklist.md` (this repo's real, recurring failure modes)

## Ground rules (accuracy over confidence)

- **Verify before you reference.** Confirm a file/symbol actually exists
  (Read/Grep) before naming it in code or in a claim. Don't invent APIs.
- **Evidence before assertions.** Quote the exact command and its output before
  saying "done", "fixed", or "passing". No "should work."
- **Name the platform on every claim.** Host-green ≠ device-verified. Say which.
- **A negative search is not proof.** An empty `grep`/`rg` may be the rtk proxy
  hiding matches, not real absence — confirm negatives with `Read`.
- **Name gaps, never hide them.** If you can't satisfy a requirement, say so
  explicitly and which platform — do not quietly downgrade the definition of done.

## NON-NEGOTIABLE: TDD + BDD required, on Android AND iOS

**Nothing is "done" without both TDD and BDD tests, verified green on Android
and iOS.** This overrides convenience, deadlines, and "it obviously works." No
exceptions — do not mark a task complete, commit a feature/fix, or report
success until every clause below holds.

1. **TDD — test first.** Write the failing unit/widget test BEFORE the
   implementation. Watch it fail (red), write the minimum code to pass (green),
   then refactor. If you're editing existing behavior, add/adjust the failing
   test first. Never write implementation code with no test driving it.
2. **BDD — behavior described in a `.feature`.** Every user-facing behavior gets
   a Gherkin `.feature` file with `bdd_widget_test`-generated `*_test.dart` and
   steps in `test/step/`. Run `build_runner` to regenerate. A feature without a
   `.feature` scenario is not done.
3. **Both platforms.** "Passes on host" is NOT done. Native-dependent behavior
   (camera, opencv_dart, ML Kit, drift/sqlite, PDF, share/print, file I/O) must
   be proven by an `integration_test/*_device_test.dart` run on a **real Android
   device AND a real iOS device** (or, where truly unavailable, an explicit,
   named gap — never a silent one).
4. **Verify, then claim.** State the exact command you ran and paste/summarize
   the green result before saying "done", "fixed", or "passing". Evidence before
   assertions — no "should work".

If any of these cannot be satisfied, STOP and say so explicitly, naming the gap
and the platform — do not quietly downgrade the definition of done. This applies
to every feature, bugfix, and refactor, however small.

## NON-NEGOTIABLE: plans decompose into small, independent, subagent-run tasks

**Every design or plan for any task MUST be broken into small, self-contained
tasks that have no dependencies on each other, so they can be handed to
subagents and executed in parallel.** Maximizing subagent usage is an explicit
goal of this project — always fan work out to as many subagents as the work
allows.

- **Decompose, don't monolith.** When you produce a design or a plan, express it
  as a set of small tasks, each doing one thing. Prefer more small tasks over
  fewer large ones.
- **Make tasks independent.** Design the decomposition so tasks don't share
  state or block one another. Where a true dependency exists, isolate it into
  its own small task and keep everything else parallelizable.
- **Dispatch to subagents.** Run independent tasks concurrently via subagents
  (see the `superpowers:dispatching-parallel-agents` and
  `superpowers:subagent-driven-development` skills). Default to parallel
  subagents; only fall back to sequential work when a hard dependency forces it.
- **Still bound by the rules above.** Parallelism never waives the TDD + BDD,
  both-platforms, and verify-then-claim requirements — each subagent's output
  must meet the same definition of done.

## Commands

All from `apps/mobile/` unless noted.

```bash
flutter pub get                 # install deps (also runs on checkout)
flutter analyze                 # lint (flutter_lints); zero-warning bar
dart format lib test            # format

# Code generation (drift *.g.dart AND bdd_widget_test *_test.dart from *.feature)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs

# Tests — see "Testing" for the host/device split
flutter test                                     # all HOST tests under test/
flutter test test/features/library/home_screen_test.dart   # one file
flutter test --plain-name 'saves a document'     # one test by name
flutter test integration_test/k1_rotate_page_device_test.dart -d <device-id>  # on-device

flutter run -d <device-id>      # run the app on a device/simulator

# Builds & release — read the matching docs/claude/ doc first
flutter build ios --release && flutter install -d <ios-device-id>   # device: BUILD then install
bash scripts/verify-artifact.sh   # assert a build is Release (not a Debug stub) + print size
bash scripts/build-ios-release.sh # App Store IPA  (see docs/claude/ios-release.md)
bash scripts/build-release.sh     # Android split-APK + AAB (see docs/claude/android-release.md)
```

## Architecture

Feature-first under `lib/features/`: **scan** (camera → edge detection →
capture/review), **library** (documents, editing, export, OCR, PDF, sharing —
the bulk of the app), **donation**.

- **Composition roots / DI.** Each feature has a const-constructible
  `*Dependencies` class (`scan_dependencies.dart`, `library_dependencies.dart`)
  holding factory typedefs for every collaborator. Production wiring is the
  default; `main.dart` (`runCamScannerApp`) accepts overrides so tests inject
  fakes and integration tests drive deterministic state on a real device. When
  adding a collaborator, thread it through the Dependencies class — do not
  `new` it inline.

- **Persistence (Drift + FTS5).** `drift/app_database.dart` defines `Documents`
  and `Pages`; `app_database.g.dart` is generated. **Image bytes live on disk**
  (`DocumentFileStore`), the DB stores only metadata and **relative** image
  paths (iOS container GUID changes on reinstall — never persist absolute paths).
  Full-text search is a hand-written `doc_fts` FTS5 trigram vtable with triggers,
  built in raw SQL inside `_createFts()` so it runs in both `onCreate` and
  `onUpgrade`; **one row per document** (concatenated page OCR) so multi-word
  `MATCH`/AND works across pages. Bump `schemaVersion` + add an `onUpgrade` step
  for any schema change. (See `docs/claude/review-checklist.md` for the traps.)

- **Image pipeline.** OpenCV work goes through `package:opencv_dart` (dartcv
  FFI, no MethodChannel). The page processor uses a
  `FallbackPageProcessor(primary: NativePageProcessor, fallback: DartPageProcessor)`:
  native runs in a `compute` isolate wrapped in a **timeout** (a wedged native
  isolate can't be killed from Dart) and returns `null` for anything it can't
  handle, so the pure-Dart fallback takes over. OCR is Google ML Kit; PDFs via
  `pdf`/`printing`/`syncfusion_flutter_pdf`.

## Testing

BDD-driven. `bdd_widget_test` generates `*_test.dart` from `*.feature` files;
step implementations are **shared** across widget and integration tests in
`test/step/` (configured in `build.yaml`). Regenerate with `build_runner` after
editing a `.feature` or adding a step.

- **Host tests** live in `test/` and run under `flutter test` on the dev
  machine. The host suite does NOT run `integration_test/`.
- **Device tests** are `integration_test/*_test.dart` (files suffixed
  `_device_test.dart` especially) — they need real native libs (opencv_dart /
  ML Kit) and must run on a device/simulator with `-d <device-id>`.
- **OpenCV on the host:** `libdartcv` does not load under plain `flutter test`.
  To exercise `opencv_edge_detector_test.dart` etc. on a host, run
  `bash scripts/setup-cv-host-test.sh` and export `DARTCV_LIB_PATH` /
  `DYLD_LIBRARY_PATH` as it prints. OpenCV-dependent failures under a plain host
  run are environmental, not real regressions.
