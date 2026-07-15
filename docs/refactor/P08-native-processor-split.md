# P08 — Native processor SOLID split + test seam

**Tier 2 (SOLID) · Effort L · Risk Med · Depends on: P01 (soft, same-file lane); coordinate P09 · Device verification: Android + iOS**

## Global constraints (honored by this plan)

- **Behavior-preserving.** `PageProcessor`, `ImageWarper`, `EnhancerMode` seams
  stay stable; the ~25k-LOC suite stays GREEN. The `NativePageProcessor()`
  const-constructor wiring in `library_dependencies.dart` keeps working
  unchanged (a *new* `withRunner` seam is additive, `@visibleForTesting`).
- **CV cannot run under plain host `flutter test`** (`libdartcv` absent). The
  extracted pure math (LUT table build, size decisions) gets failing-first host
  unit tests; anything Mat-typed is verified on a **real Android AND real iOS**
  device. Host CV runs need `scripts/setup-cv-host-test.sh` +
  `DARTCV_LIB_PATH`/`DYLD_LIBRARY_PATH`.
- **Parity gate.** This is a *structural* split — moving code, not changing math.
  Native auto-enhance output must remain byte-identical; re-verify parity mean
  ≤ **0.151** on device (`np2`) after the split.
- **Decomposed into small independent tasks** below.

## Summary

`native_page_processor.dart` (~301 LOC) is a god-file: it bundles isolate +
timeout orchestration, JPEG decode/encode, perspective warp (`_warpStraight`),
**three** enhancers (`_autoFlatField`, `_colorBoost`, `_grayscale`), LUT math
(`_whitePointLut3`), geometry, and Mat lifecycle — while the **Dart** side already
splits the identical responsibilities across `perspective_warper` / `coons_warper`
/ `warp_enhancer` / `*_enhancer`. This asymmetry makes the native path hard to
test (all logic is behind private top-level `cv.Mat`-typed functions that only run
where `libdartcv` loads) and hard to change safely (P01 and P09 both have to reach
into this one file).

The plan **mirrors the Dart decomposition on the native side**
(`native_perspective_warper`, `native_enhancers`) behind a thin
`NativePageProcessor` orchestrator, adds a `withRunner` test seam matching the
one `OpenCvEdgeDetector` already has, and extracts the pure LUT math so it is
host-testable (coordinated with P09, which *unifies* that math with the Dart
copy).

**No active leaks.** Every Mat is disposed by an owning `finally` today; the
`warped`/`src` aliasing below is *correct* — the item is a **latent footgun** to
document, not a bug. The `opencv_edge_detector.dart._segmentGray` disposal is the
**exemplary reference standard** for how the split-out native units should manage
Mat lifecycle; its only shortcoming is size/complexity (out of scope here).

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| `native-processor-god-file` | `native_page_processor.dart` whole file (~301 LOC): `_nativeFn` (~L61), `_autoFlatField` (~L107), `_whitePointLut3` (~L183), `_colorBoost` (~L225), `_grayscale` (~L242), `_warpStraight` (~L255) | One file owns isolate/timeout orchestration + decode/encode + warp + 3 enhancers + LUT math + geometry + Mat lifecycle. The Dart side splits these across `perspective_warper`/`coons_warper`/`warp_enhancer`/`*_enhancer`. Asymmetric, low-cohesion, high-churn (P01 & P09 both edit it). | Hard to test, hard to change safely, merge-conflict magnet across P01/P08/P09. | latent (maintainability) |
| `no-injected-timeout-in-wiring` | `library_dependencies.dart` L64 `NativePageProcessor()` (default 5 s timeout, `native_page_processor.dart` L29); NO `withRunner`-style seam. Contrast `OpenCvEdgeDetector.withRunner(PipelineRunner)` + `typedef PipelineRunner` (`opencv_edge_detector.dart` L16, L34–38) | The native→Dart fallback handoff (`FallbackPageProcessor`) can't be exercised host-side with a fake slow/failing runner — no injection point. The edge detector already demonstrates the pattern. | Fallback/timeout logic (and P01 Task 6) has no host test seam. | latent (testability) |
| `native-fns-untestable` | `_autoFlatField` (~L107), `_whitePointLut3` (~L183, pure math L196–218 entangled with `cv.Mat.fromList` L219 and `flat.data` L184), `_colorBoost` (~L225), `_grayscale` (~L242), `_warpStraight` (~L255) | Pure math (LUT table build, size math) is welded to `cv.Mat` I/O inside private top-level fns → only runs where `libdartcv` loads → untestable under plain host `flutter test`. | The one host-testable part of the native path (LUT/size math) can't be unit-tested. | latent (testability) |
| `warped-src-alias-double-dispose` | `_nativeFn`: full-frame `warped = src.clone()` (~L68–69), both disposed in the outer `finally` (~L98–99) | **Correct today** — `warped` is a distinct clone, so disposing both is fine. But the invariant "`warped != src` in the full-frame branch" is implicit; a future "drop the redundant clone" optimization (see P01 Task 5) that sets `warped = src` would double-free. | Silent double-free / native crash if a future edit aliases `warped` to `src`. | **latent footgun** |

## Definition of done

- `NativePageProcessor` becomes a **thin orchestrator** (isolate + timeout +
  dispatch) delegating to `native_perspective_warper` (warp) and
  `native_enhancers` (auto/color/grayscale), mirroring the Dart module layout.
- `NativePageProcessor.withRunner(runner, {timeout})` (`@visibleForTesting`)
  exists, matching the `OpenCvEdgeDetector` pattern; the native→Dart fallback and
  timeout are host-testable with a fake `PipelineRunner`.
- Pure LUT/size math is extracted into `cv`-free functions with failing-first
  host unit tests (the *table computation* is shared with the Dart side per P09 —
  see the coordination note).
- The `warped != src` lifecycle invariant is asserted/documented so a future
  edit can't introduce a double-free (an `assert(!identical(warped, src))` before
  disposal, or a comment + guarded disposal).
- **Parity ≤ 0.151** on Android + iOS (`np2`); `np1`/`np3` GREEN both platforms;
  full host suite + `flutter analyze` GREEN.

## Before → After

| Aspect | Before | After |
|--------|--------|-------|
| Files owning the native path | 1 (`native_page_processor.dart`, ~301 LOC) | orchestrator + `native_perspective_warper` + `native_enhancers` + pure `*_lut`/size math (each small, single-responsibility) |
| Native ↔ Dart module symmetry | asymmetric (Dart split, native monolith) | symmetric (native mirrors `perspective_warper`/`warp_enhancer`/`*_enhancer`) |
| Fallback/timeout test seam | none (`NativePageProcessor()` only) | `withRunner(runner,{timeout})`, `@visibleForTesting`, mirrors edge detector |
| Host-testable native math | 0% (all behind `cv.Mat` private fns) | LUT table + size math unit-tested on host |
| `warped`/`src` double-free risk | implicit invariant, unguarded | asserted/documented invariant |
| Public seams / wiring | `PageProcessor`/`ImageWarper`/`EnhancerMode`, `NativePageProcessor()` | **unchanged** (additive `withRunner` only) |

## Coordination note (P01 & P09 touch the same file)

P08 **restructures** the same `native_page_processor.dart` that **P01 hardens**
(OOM caps) and **P09 de-duplicates** (shared LUT/warp math). To avoid churn and
merge pain:

- **Sequence P01 first**, then P08 rebases the split onto the hardened file — OR
  do P01 + P08 as **one coordinated single-file pass** (recommended if one
  subagent owns the file). State this explicitly to whoever schedules the work.
- P09's LUT extraction (`dup-native-vs-dart-autoenhance`) should consume P08's
  extracted `native_enhancers` seam — i.e. **P08 extracts, P09 unifies**. If P09
  runs first, P08 wires the split module to call P09's shared function.

## Tasks (small, independent, subagent-ready)

Tasks 1–2 are pure extraction (host-testable, fully independent). Tasks 3–5 edit
`native_page_processor.dart` — **serialize them or give the file to one
subagent** (and coordinate with P01/P09 per the note). Task 6 is device verify.

### Task 1 — Extract pure native size math
- **Scope:** Pull `_warpStraight`'s output-size + cap computation (~L256–277) into
  a pure `cv`-free function `nativeWarpOutputSize(corners, w, h, cap)` returning
  `(pxW, pxH)`. `_warpStraight` calls it, then only does the `cv` transform/warp.
- **Files:** new `lib/features/library/native_warp_geometry.dart`;
  test `test/features/library/native_warp_geometry_test.dart`.
- **Test-first:** failing host tests — edge-pair max rule, ≥2 clamp, cap scaling.
  (This is a candidate to *merge* with P09's `dup-convex-quad-and-geometry`
  unification — flag it; keep behavior byte-identical if merged.)
- **Done:** function + host tests GREEN under plain `flutter test`.
- **Parallel-safe:** yes (new file).

### Task 2 — Extract pure white-point LUT-table math
- **Scope:** Extract the pure table-building loop from `_whitePointLut3`
  (~L196–218) into `cv`-free `whitePointLut3Table(histograms) -> List<int>` (the
  768-element BGR table), leaving `_whitePointLut3` to only read `flat.data`
  (~L184), build histograms, call the pure fn, and wrap in `cv.Mat.fromList`
  (~L219). **This is the exact function P09 unifies with the Dart copy** — name
  and shape it so P09 can point both sides at it.
- **Files:** new `lib/features/library/white_point_lut.dart` (or P09's shared
  module if P09 lands first); test
  `test/features/library/white_point_lut_test.dart`.
- **Test-first:** failing host tests on the table (identity default, clip/anchor,
  span scaling) — derived from the algorithm in `auto_enhancer.dart`
  `_whitePointStretch` (L250–293) so it's the single reference.
- **Done:** host tests GREEN; `_whitePointLut3` calls it (device parity unchanged).
- **Parallel-safe:** yes (new file); **coordinate with P09** to avoid two shared
  modules.

### Task 3 — Split enhancers into `native_enhancers`
- **Scope:** Move `_autoFlatField` (~L107), `_colorBoost` (~L225), `_grayscale`
  (~L242) into a new `native_enhancers.dart` (top-level, isolate-sendable, same
  Mat-lifecycle discipline as `_segmentGray` — the reference standard).
  `native_page_processor.dart` imports them. No math change.
- **Files:** new `lib/features/library/native_enhancers.dart`;
  edit `native_page_processor.dart`.
- **Test-first:** device parity `np2`/`np3` (structural move → identical output).
- **Done:** `np2` ≤ 0.151, `np3` GREEN on both devices.
- **Parallel-safe:** **no** vs Tasks 4/5 (same source file) — serialize; safe vs
  Tasks 1/2. Coordinate with P01/P09.

### Task 4 — Split warp into `native_perspective_warper`
- **Scope:** Move `_warpStraight` (~L255) into `native_perspective_warper.dart`
  (using Task 1's pure size fn); orchestrator calls it. No math change.
- **Files:** new `lib/features/library/native_perspective_warper.dart`;
  edit `native_page_processor.dart`.
- **Test-first:** device `np1` (straight-crop warp path) GREEN.
- **Parallel-safe:** **no** vs Tasks 3/5 (same file) — serialize; depends on Task 1.

### Task 5 — Add `withRunner` seam + guard the alias invariant
- **Scope:** Add `typedef` for the native isolate runner + `NativePageProcessor`
  default runner and `@visibleForTesting NativePageProcessor.withRunner(runner,
  {timeout})`, mirroring `OpenCvEdgeDetector` (L16, L29–38). Add
  `assert(!identical(warped, src))` (or guarded disposal) before the outer
  `finally` disposes both (~L98–99) to lock the `warped != src` invariant.
- **Files:** `native_page_processor.dart`;
  test `test/features/library/native_page_processor_fallback_test.dart` (fake
  slow/failing runner → asserts null/timeout path without `libdartcv`).
- **Test-first:** failing host test injecting a never-completing runner → `process`
  returns null within `timeout`; a failing runner → null.
- **Done:** host fallback/timeout test GREEN (no CV); wiring
  (`library_dependencies.dart` L64) still constructs `NativePageProcessor()`
  unchanged. **Feeds P01 Task 6** (bounding the double-decode window).
- **Parallel-safe:** **no** vs Tasks 3/4 (same file) — serialize.

### Task 6 — Device verification of the split
- **Scope:** Run the native + auto/warp device suite on Android + iOS; confirm
  parity and no lifecycle regressions post-split.
- **Files:** none (verification only).
- **Done:** `np1`/`np2`/`np3` + `e2`/`g3` GREEN on both; parity ≤ 0.151.
- **Parallel-safe:** runs after 1–5 land.

## Risks & mitigations

- **Risk: extraction subtly changes math → parity break.** Mitigation: move code
  verbatim, no reformulation; gate on `np2` ≤ 0.151 on both devices.
- **Risk: a future "drop the clone" optimization aliases `warped=src` → double
  free.** Mitigation: Task 5's `assert(!identical(...))` + comment; coordinate
  directly with **P01 Task 5** (which removes a clone) so both land together.
- **Risk: two shared LUT modules (P08 Task 2 vs P09) diverge.** Mitigation: P08
  extracts, P09 unifies against the *same* file — assign both to coordinated
  owners; if P09 lands first, P08 imports P09's module.
- **Risk: file-edit conflicts (Tasks 3/4/5 + P01 + P09).** Mitigation: one
  subagent owns `native_page_processor.dart`; P01 runs first (or same pass).

## Verification commands

```bash
# From apps/mobile/
# Host (pure math + fallback seam, no CV):
flutter test test/features/library/native_warp_geometry_test.dart
flutter test test/features/library/white_point_lut_test.dart
flutter test test/features/library/native_page_processor_fallback_test.dart

# Optional host CV smoke: source env first
bash ../../scripts/setup-cv-host-test.sh   # export the printed DARTCV_LIB_PATH / DYLD_LIBRARY_PATH

# Device — Android:
flutter test integration_test/np1_native_pipeline_test.dart     -d <android-id>
flutter test integration_test/np2_native_auto_parity_test.dart  -d <android-id>   # parity ≤ 0.151
flutter test integration_test/np3_native_color_gray_test.dart   -d <android-id>
flutter test integration_test/e2_flatten_test.dart              -d <android-id>
flutter test integration_test/g3_auto_color_test.dart           -d <android-id>

# Device — iOS (mandatory):
flutter test integration_test/np1_native_pipeline_test.dart     -d <ios-id>
flutter test integration_test/np2_native_auto_parity_test.dart  -d <ios-id>       # parity ≤ 0.151
flutter test integration_test/np3_native_color_gray_test.dart   -d <ios-id>
flutter test integration_test/e2_flatten_test.dart              -d <ios-id>
flutter test integration_test/g3_auto_color_test.dart           -d <ios-id>

# Whole-suite gate:
flutter test
flutter analyze
```
