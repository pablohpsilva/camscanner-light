# CamScanner-light `apps/mobile` — Architectural Refactor: Overview & Before/After Comparison

> Scope: **`apps/mobile/` only.** Goal: make the app **safer** and **faster** through a
> behaviour-preserving refactor that fixes broken SOLID/DRY/KISS practices — decomposed into
> **15 small, independent, parallelizable plans** (never one big chunk). **No test may break, no
> build may break.** Every plan keeps public APIs/interfaces stable so the existing test suite
> stays green.

---

## 1. How this analysis was produced (and why you can trust the findings)

| Phase | Agents | What they did |
|---|---|---|
| **Audit** | 5 parallel subagents | Read the real source across the 5 natural subsystems (persistence, library UI, image pipeline, scan+secondary features, cross-cutting) and produced file:line-anchored findings. |
| **Adversarial verification** | 14 parallel subagents | Each an independent skeptic instructed to **try to refute** every finding; a finding was only kept if the verifier could quote the exact current code. Line numbers were re-checked; counts were re-grepped. |

**Verification outcome:** every finding was **CONFIRMED** or **AMENDED** (details corrected) —
**none was fully refuted**. Crucially, the adversarial pass *downgraded* several items from
"live bug" to "latent risk", so the plans do not overstate:

- **No active memory leaks exist** in the native pipeline — every `Mat` has a disposing owner.
  The three native "leak" findings are latent footguns / wasted allocations, labelled as such.
- `opencv_edge_detector.dart._segmentGray` disposal is **exemplary** (leak-free, double-free-free)
  — it is the *reference standard* the rest of the pipeline should imitate; its only issue is size.
- `current-unclamped` (viewer) is **latent** — split/merge only grow the page list, so no live
  `RangeError` today.
- Filter-strip regen drop and the two-step double-decode are **unreachable with current callers**.

**Sharpened findings** (verification found the audit *understated* the problem):

- Enhancer-mode dispatch is duplicated across **5** switch sites, not 3 — and
  `enhancer_for_mode.dart` literally documents itself as "single source of truth" while
  `DartPageProcessor._enhancerFor` re-implements the same map.
- The native full-frame **Auto** path allocates **five** full-resolution `CV_32FC3` float Mats
  (~150 MB each at 12.5 MP) with **no** downscale guard — confirmed, top crash risk.

---

## 2. Codebase snapshot (the "before")

**Source (`apps/mobile/lib`, excluding `*.g.dart`): ~19 000 LOC**, of which ~7 000 is generated
l10n (`lib/l10n/gen/`). Hand-written feature code is concentrated in the **library** feature (42
files). **Test suite (safety net): ~25 000 LOC** — 179 host `*_test.dart` files, 42 `.feature`
BDD specs, 137 shared step files, 66 `integration_test` device files.

**The debt is concentrated in a handful of hot files:**

| File | LOC | Role today | Primary problems |
|---|---:|---|---|
| `library/drift/drift_document_repository.dart` | **1242** | God repository | 24 interface methods + 9 collaborators; CRUD + FTS + exports(6) + OCR + derivative pipeline + ordering in one class; non-atomic merge/split; full-table scan; 8× duplicated page lookup |
| `library/page_viewer_screen.dart` | **854** | God widget | 16 async actions + 17 repo calls + snackbars + nav + global image-cache wipe; boolean-soup state; reorder race |
| `library/home_screen.dart` | **682** | God widget | startup watchdog + search + selection + zip export orchestration; sort-on-build; owns/leaks Theme/Locale controllers |
| `library/native_page_processor.dart` | **300** | Native CV | OOM float-copies (no size guard); 3 enhancers + warp + LUT + FFI lifecycle in one file; no test seam |
| `library/auto_enhancer.dart` | **293** | Dart CV | full re-implementation of the native auto-enhance (byte-parity duplication) |
| `feedback/feedback_screen.dart` | **294** | Feedback UI | inline origin derivation; result→l10n mapping in the widget |

**Architecture today (2.5 layers, no domain layer):** feature-first (`scan`, `library`,
`donation`, `settings`, `feedback`) + cross-cutting `theme`/`l10n`. There is a widget layer and a
persistence layer but **no domain/use-case layer** — business logic lives either in screens or in
the God repository. State uses `ChangeNotifier` controllers (`ThemeController`, `LocaleController`,
`SaveController`) — but that clean pattern was applied only to *save*, not the other ~15
repo-calling flows. No centralized logger, no `FlutterError.onError`.

### Strengths to preserve (do **not** refactor these)

- The **`*Dependencies` composition-root** pattern (const-constructible, override-for-tests).
- The **`DocumentRepository` interface** (a clean DIP seam) and **`DocumentFileStore`** (the single,
  disciplined owner of relative image paths).
- The **`SaveController`** ChangeNotifier state machine — the template new controllers should copy.
- The **Ream semantic theme tokens** (`ReamColors`, `context.ream`).
- `opencv_edge_detector.dart` + `detector_geometry.dart` — exemplary Mat lifecycle + a pure,
  host-testable geometry module.
- `opencv_dart` pinned to **exactly 2.1.0** (2.2.x builds from source, 5–8× slower).
- The **DB deliberately on the root/UI isolate** (a documented native-assets/sqlite workaround) —
  keep it there.

---

## 3. Verified findings — master list (grouped by plan)

Legend — **L** = live defect, **~L** = latent (correct today, hardening). Locations are the
**current, verified** file:line.

### Tier 1 — Safety (crash / hang / corruption)

| Plan | ID | Location | Defect | L/~L |
|---|---|---|---|:--:|
| P01 | native-no-input-size-guard | `native_page_processor.dart:64,152` | full-frame Auto converts full-res (12.5 MP) to `CV_32FC3` with no downscale → ~150 MB floats, OOM | L |
| P01 | perf-fullframe-auto-float-copies | `native_page_processor.dart:144-154` | 5 full-res float Mats; `floorMat` scalar-max removable | L |
| P01 | fallback-double-decode-on-native-fail | `fallback_page_processor.dart:26-32` | native null re-runs whole Dart pipeline; wedged native isolate uncancellable → 2 pipelines at once | L |
| P01 | dart-warp-no-src-downscale | `perspective_warper.dart:99`, `coons_warper.dart:120` | full-res `getBytes` with no source downscale | L |
| P01 | native-none-clone-leak | `native_page_processor.dart:82` | redundant full-res `warpedMat.clone()` for none+crop (waste, not leak) | L |
| P02 | SF-1 | `feedback_service.dart:44,69-73` | submit POSTs have no `.timeout` (availability does at `:28`) → permanent spinner | L |
| P02 | no-timeout-native-async | `mlkit_ocr_engine.dart:31-33`, `pdf_preview_screen.dart:52` | ML Kit + PDF opener unbounded | L |
| P02 | unbounded-compute | 8 of 10 `compute()` sites | Dart isolates + fallback pipeline have no timeout | L |
| P03 | SAFE-01 | `drift_document_repository.dart:1024-1058, 1107-1145` | merge copies files outside txn (orphans); split inserts+files fully outside txn (duplicated pages) | L |
| P03 | SAFE-02 | `drift_document_repository.dart:75-133, 790-838` | heavy IO/scrub/flat held inside the DB write transaction | L |
| P04 | reorder-race | `page_viewer_screen.dart:409-433` | reorder bypasses the `_editing` single-flight; races concurrent edits | L |
| P04 | current-unclamped | `page_viewer_screen.dart:82,532,552` | `_current` not re-clamped after `_load()` (grow-only today) | ~L |
| P04 | blocking-sync-io | `mlkit_ocr_engine.dart:28,57` | `writeAsBytesSync` of a multi-MB image on the UI isolate | L |
| P04 | sharing-flag-no-finally-notify | `home_screen.dart:85,308-382` | `_sharing` never `setState`-backed → no busy UI during long export/share | L |
| P04 | SF-4 | `id_scan_screen.dart:56-61` | back-capture cancel silently discards the already-captured front | L |

### Tier 2 — SOLID / God-object decomposition

| Plan | ID | Location | Defect | L/~L |
|---|---|---|---|:--:|
| P05 | GOD-01 | `drift_document_repository.dart` (class) | 24 methods, 9 collaborators, 5 responsibilities | L |
| P05 | SAFE-06 | `…:145-230` | FTS sanitization embedded in the repo (untestable) | L |
| P05 | SOLID-02 | `…:53-54,60` | ctor default-constructs Syncfusion/ImageLibrary/DartPageProcessor concretes | L |
| P05 | TEST-01 | `…:606,1231-1242` | `compute(rotateAndBakeJpeg)` hardwired, not injectable | L |
| P05 | CPLX-01 | `…:583-642` | `_writeFlat` mixes 4 concerns with null-driven fallbacks | L |
| P06 | pv-god-widget | `page_viewer_screen.dart:65-854` | 16 async actions + 17 repo calls in the State | L |
| P06 | home-god-widget | `home_screen.dart` | startup + search + selection + zip export in the State | L |
| P06 | setstate-state-machine | `page_viewer_screen.dart:68-82` | loose parallel booleans; illegal combos representable | L |
| P06 | dup-load-state-machine | viewer/recognized-text/pdf-preview | similar (not identical) load/error/retry blocks | L |
| P06 | duplicated-error-toast | 32 `showSnackBar` / 8 files (viewer 16) | repeated try/catch/finally/toast skeleton | L |
| P06 | home-owns-controllers | `home_screen.dart:73-77` | manufactures + leaks Theme/Locale controllers; fallback = no persistence | L |
| P07 | DUP-1 | `scan_screen.dart:41-149`, `id_scan_screen.dart:35-103` | duplicated scanner+SaveController orchestration | L |
| P07 | DUP-2 | `scan_screen.dart:97-117`, `home_screen.dart:211-241` | duplicated review-and-save wiring (snackbar 2×) | L |
| P07 | SOC-2 | `scan_screen.dart:36-177` | batch-save state machine lives in the widget State | L |
| P07 | SOC-1 | `donation_screen.dart:27-49` | inline `launchUrl`/`Clipboard`, no seam → untestable | L |
| P07 | TST-2 | `capture_review_screen.dart:17-37` | real-`FileImage` default risks host-test hang | ~L |
| P08 | native-processor-god-file | `native_page_processor.dart` | isolate + warp + 3 enhancers + LUT + FFI in one file | L |
| P08 | no-injected-timeout-in-wiring | `library_dependencies.dart:64` | no `withRunner` seam (edge detector has one) → fallback untestable | L |
| P08 | native-fns-untestable | `native_page_processor.dart:107-255` | private Mat-typed fns; pure LUT math entangled with FFI | L |
| P08 | warped-src-alias-double-dispose | `native_page_processor.dart:68-69,98-99` | invariant `warped != src` undocumented (footgun) | ~L |

### Tier 3 — Duplication / DRY

| Plan | ID | Location | Defect | L/~L |
|---|---|---|---|:--:|
| P09 | dup-native-vs-dart-autoenhance | `native_page_processor.dart:107-219` vs `auto_enhancer.dart:81-293` | two byte-parity impls of one algorithm | L |
| P09 | dup-warp-sampling-loop | `perspective_warper.dart:99-124` vs `coons_warper.dart:120-160` | identical bilinear sampler | L |
| P09 | dup-convex-quad-and-geometry | `perspective_warper.dart:143-158` / `detector_geometry.dart:89-106` (+3 size rules) | equivalent-not-identical geometry copied | L |
| P09 | dup-enhancer-isolate-boilerplate | `auto_/color_/grayscale_enhancer.dart` | identical decode/bake/encode/catch scaffold | L |
| P09 | dup-mode-dispatch | **5** switch sites | EnhancerMode↔filter map duplicated (incl. self-declared "single source of truth") | L |
| P09 | dart-processor-type-sniffing | `dart_page_processor.dart:41-43` | `is HybridWarper\|Perspective\|Coons` behind the interface | L |
| P09 | perf-coons-closure-per-pixel | `coons_warper.dart:130` | `top(u)/bottom(u)` recomputed per pixel | L |
| P09 | perf-clamp-in-inner-loop | `perspective_warper.dart:120`, `coons_warper.dart:156` | redundant `.clamp` in hottest loop | ~L |
| P10 | DUP-01 | 8 sites (`:314…918`) | page-lookup+throw copy-pasted (2 throw a different exception) | L |
| P10 | DUP-02 | `…:1024-1053, 1107-1137` | merge/split page-copy loop duplicated | L |
| P10 | DUP-03 | `…:653-656` vs `:292-296` | enhancer-mode decode duplicated | L |
| P10 | DUP-04 | `…:367,400,436,489,538` | temp-export boilerplate + **inconsistent** rethrow | L |
| P10 | SAFE-05 | `…:1027, 1109` | inline path strings bypass `DocumentFileStore` | L |
| P10 | CPLX-02 | `…:861-886` | delete renumber is a row-by-row UPDATE loop | L |
| P10 | SAFE-03 | `…:108,816,1181,1196` | silent `catch(_)` hides flat/OCR failures | L |
| P11 | share-menu-duplication | 3 surfaces (`:628-706`, `:83-117`, `:63-89`) | stringly-typed share dispatch duplicated | L |
| P11 | overflow-menu-in-screen | `page_viewer_screen.dart:582-706` | flag-reads + layout + dispatch fused in the State | L |
| P11 | feature-flag-gating | 25 `features.*` reads; OR-chain `:571-578` | per-flag gating scattered; hand-kept OR chain | L |
| P14 | dependencies-inconsistency | 3 DI styles + `main.dart:48-55` | inconsistent injection conventions | L |
| P14 | DEAD-1 | `gallery_picker.dart`, `scan_dependencies.dart` | `GalleryPicker` misplaced in scan (only library uses it) | L |
| P14 | error-swallowing-observability | `native_page_processor.dart:48,95` + enhancer/warper catches | silent `catch{return bytes}` in the pipeline hide native-crash vs corrupt-input vs timeout (repo catches → P10 SAFE-03) | L |
| P14 | DUP-4 / DUP-3 / SOC-3 / SOC-4 / SF-2 / SF-3 | feedback/donation | env-read dup, nav dup, mapping-in-widget, inline origin, fragile parse, unescaped siteKey | L/~L |

### Tier 4/5 — Performance & Hygiene

| Plan | ID | Location | Defect | L/~L |
|---|---|---|---|:--:|
| P12 | PERF-01 | `drift_document_repository.dart:251-260` | `_summaries` scans the **entire** pages table every home load | L |
| P12 | PERF-02 | `…:392-457,505-514` | N+1 export queries + re-selects | L |
| P12 | sort-on-build | `home_screen.dart:636,343-344` | full-library re-sort on every `setState` | L |
| P13 | full-res-decode | `page_viewer_screen.dart:815-819` | full-res `Image.file`, no `cacheWidth` | L |
| P13 | imagecache-clear-global | `page_viewer_screen.dart:119-127` | global image-cache wipe on every edit | L |
| P13 | PERF-1-double-read | `capture_review_screen.dart:100,113` | full-res JPEG read off disk twice | L |
| P13 | PERF-2-detection-wasted | `capture_review_screen.dart:108-125` | detection runs even after user interaction | L |
| P13 | kSlot-magic-number | `page_thumbnail_strip.dart:56` | `kSlot` derived from unshared literals (drift) | ~L |
| P15 | theme-token-bypass | 3 non-theme `Color(0x)` in `lib/features` (+1 in `lib/theme/widgets`), 24 `Colors.`, 28 `TextStyle(` (`lib/features`; 32/36 across all `lib`) | tokens bypassed | L |
| P15 | dup-date-format | `documents_list_view.dart:166-170` vs `document_grid_card.dart:127-143` | grid uses hardcoded English months → **i18n regression**; different date field | L |
| P15 | analysis-options-minimal | `analysis_options.yaml` | only `flutter_lints`; no `unawaited_futures` | ~L |
| P15 | pubspec-loose-pins | `pubspec.yaml:35` | `intl: any` unpinned; 3 PDF stacks | ~L |

---

## 4. Before → After (architecture)

| Concern | Before | After |
|---|---|---|
| **Layers** | 2.5 (widget + persistence, logic in screens/repo) | 3 (widget → controllers/use-cases → repository/services) |
| **Persistence** | 1 God class, 24 methods, 9 collaborators | thin `DriftDocumentRepository` coordinator + `DocumentSearchService`, `DocumentExporter`, `PageOrderingService`, `PageDerivativePipeline`, `PageDao`, `FtsQuerySanitizer` |
| **Library screens** | 854- & 682-LOC God widgets | thin views + `PageViewerController` / `LibraryController` (+ `SelectionExporter`) |
| **Async / errors** | ad-hoc try/catch/finally/toast ×32; no logging; 8/10 `compute()` unguarded | `runGuarded`/`AsyncActionController` + `AppLogger` + `FlutterError.onError` + `withIsolateTimeout` |
| **Native pipeline** | 1 file (warp+3 enhancers+LUT+FFI), OOM float copies, no test seam | split warpers/enhancers + `withRunner` seam + size-bounded working image + shared pure LUT/geometry |
| **Enhancer-mode map** | 5 switch sites | 1 registry all sites derive from |
| **State** | loose parallel booleans | `sealed ViewState<T>` + `AsyncStateView` |
| **Temp files / paths** | 7 ad-hoc temp sites; inline path strings | `TempFileWriter` + `DocumentFileStore` everywhere |
| **DI** | 3 conventions + inline `main.dart` wiring | one factory-typedef convention; controllers created in the root |
| **Theme / i18n** | 4 hardcoded colors, grid date hardcoded English | tokens everywhere; one locale-aware date formatter |

### Metrics scorecard (targets)

| Metric | Before | Target |
|---|---:|---:|
| Largest file (LOC) | 1242 | < 400 |
| God widgets > 500 LOC | 2 | 0 |
| `compute()` without timeout | 8 / 10 | 0 / 10 |
| Centralized logger / `FlutterError.onError` | none | yes |
| `showSnackBar` call sites | 32 | ~1 helper + call-throughs |
| EnhancerMode dispatch sites | 5 | 1 |
| Duplicated page-lookup blocks | 8 | 1 helper |
| Non-atomic multi-entity ops | 2 (merge/split) | 0 |
| Home-load page reads | O(all pages) | O(#documents) |
| Peak native memory, 12.5 MP Auto | ~500 MB+ | bounded (< working-cap) |
| Public API / test-suite changes | — | **0** (behaviour-preserving) |

---

## 5. Non-negotiables carried into every plan

1. **TDD** — failing test first, then minimum code, then refactor.
2. **BDD** — user-facing behaviour keeps its `.feature` scenario, regenerated via `build_runner`.
3. **Both platforms** — native/memory/persistence/UI-memory work verified on a **real Android AND
   iOS device** (both available); host-only where native libs don't load, with the gap named.
4. **Verify, then claim** — paste the green command output before calling anything done.
5. **Behaviour-preserving** — public APIs/interfaces stay stable; the ~25k-LOC suite stays green.

See `01-roadmap.md` for the dependency graph, parallelization waves, and execution order. Each
`PNN-*.md` file is a self-contained plan decomposed into subagent-ready tasks.
