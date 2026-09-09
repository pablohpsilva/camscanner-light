# P01 — Native pipeline OOM safety

**Tier 1 (Safety) · Effort M · Risk Med · Depends on: none · Device verification: Android + iOS (both mandatory)**

> HIGHEST-PRIORITY CRASH RISK. A native OpenCV OOM aborts the process
> *uncatchably* (SIGABRT/SIGKILL — no Dart `catch` runs), so the fallback seam
> cannot save us. This plan bounds working resolution *before* the float pass so
> the crash never fires.

## Global constraints (honored by this plan)

- **Behavior-preserving.** The public seams — `PageProcessor.process`,
  `ImageWarper.warp`, `EnhancerMode` — do not change signature or semantics. The
  ~25k-LOC suite stays GREEN. The only observable change is that some
  ultra-high-resolution inputs are processed at a bounded working resolution
  (still ≥ the existing flat-output cap `kDefaultFlatMaxDimension = 3500`), which
  is already the shipped behavior for cropped paths — see the parity note below.
- **CV cannot run under plain host `flutter test`** (`libdartcv` does not load).
  Pure Dart math added here (a downscale-decision helper) gets failing-first host
  unit tests; everything touching `cv.Mat` / `img.Image` sampling is proven on a
  **real Android device AND a real iOS device**. To host-run the OpenCV-adjacent
  tests, source `scripts/setup-cv-host-test.sh` and export the `DARTCV_LIB_PATH` /
  `DYLD_LIBRARY_PATH` it prints; a plain host run failing on CV load is
  environmental, not a regression.
- **Auto-enhance parity is a gate.** The project records an on-device native↔Dart
  parity mean of **0.151**. Any change that alters the resolution the auto
  flat-field sees must re-verify parity ≤ 0.151 on device (`np2`). Because the
  flat-field is scale-tolerant by construction (background estimated on a 512 px
  proxy, `_flatten` upsamples bilinearly), a modest working-resolution cap moves
  the mean only within noise — but it must be *measured*, not assumed.

## Summary

The native full-frame + Auto save path (`native_page_processor.dart`) decodes and
processes at the **raw capture resolution** (up to ~12.5 MP; the memory note caps
camera at 12.5 MP, which is the only reason this hasn't already crashed on larger
sensors). At that size it allocates **five full-resolution `CV_32FC3` float Mats**
(~150 MB *each* at 12.5 MP) plus the decoded `src`, its `clone`, and the output —
a peak north of **1 GB** for one page. The proxy downscale that makes the Dart
path cheap is applied here **only to the background estimate**, never to the
float working buffers or the output. The cropped/warp path is capped
(`kDefaultFlatMaxDimension`), but the *full-frame* branch sets
`warped = src.clone()` **uncapped**.

The fix is a single **working-resolution cap applied before the float pass**
(and before the Dart warpers' full-res sampling loop), plus removing redundant
full-res allocations (a constant-scalar Mat, a `none`-mode clone). None of these
change output semantics beyond a bounded-resolution downscale that is already the
norm for cropped output.

**Note — no active leaks.** Every `cv.Mat` in `native_page_processor.dart` has a
disposing owner (`finally` blocks dispose `src`, `warped`, the enhancer temporaries,
and the 12-Mat list in `_autoFlatField`). The items below are **OOM / waste
footguns**, not leaks — labeled `live` where they can crash or waste real memory
on a real capture today, none are "memory left dangling."

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| `native-no-input-size-guard` | `native_page_processor.dart` `_nativeFn` `imdecode` (~L64); `_autoFlatField` `srcF = src.convertTo(CV_32FC3)` (~L152); full-frame `warped = src.clone()` (~L69) | Full-frame + Auto never downscales the working buffers. `imdecode` is full-res (≤~12.5 MP); `srcF` is a ~150 MB float copy at 12.5 MP; the proxy downscale (~L128–140) applies ONLY to the background estimate. `_warpStraight` caps at `kDefaultFlatMaxDimension` (~L271) but the full-frame branch is uncapped. | **Top OOM risk.** Native OOM aborts the process uncatchably; the fallback seam cannot recover. | **live** |
| `perf-fullframe-auto-float-copies` | `_autoFlatField` `bgF` (~L144), `floorMat` (~L145), `bgFloored` (~L151), `srcF` (~L152), `flatF` (~L153) | FIVE full-res `CV_32FC3` Mats coexist at peak. `floorMat` is a constant-scalar Mat allocated full-res solely to feed `cv.max(bgF, floorMat)` (~L151) — a scalar-max removes one full-res float alloc outright. | ~150 MB of avoidable float per page at 12.5 MP; shrinks peak by ≥1 full buffer. | **live** (waste) |
| `fallback-double-decode-on-native-fail` | `fallback_page_processor.dart` `process` (L26–32); native `compute(...).timeout(timeout)` with default 5 s (`native_page_processor.dart` L29, L44–49) | On native returning `null` / timing out, the fallback re-runs the ENTIRE Dart pipeline. The native isolate on `TimeoutException` is NOT cancellable (a wedged native isolate can't be killed from Dart), so up to **two full-res pipelines run concurrently** for the whole timeout window. | Doubles peak memory during the wedge window → compounds the OOM risk in row 1. | **live** |
| `dart-warp-no-src-downscale` | `perspective_warper.dart` `src.getBytes(order: rgb)` (L99); `coons_warper.dart` `src.getBytes(order: rgb)` (L120) | Both warpers sample the FULL-RES baked source in the inner loop; the *output* is capped (`kDefaultFlatMaxDimension`) but the *source buffer* is not, so a full-res RGB byte buffer is materialized even for a small output. | Full-res RGB buffer (~37 MB at 12.5 MP) allocated for a bounded output; adds to the fallback-path peak. | **live** (waste) |
| `native-none-clone-leak` | `native_page_processor.dart` `EnhancerMode.none => warpedMat.clone()` (~L82) | For `none` + straight-crop, a redundant full-res copy is made only to be encoded; `warped` could be encoded directly. | One avoidable full-res `CV_8UC3` copy (~37 MB at 12.5 MP). Mislabeled "leak" — it IS disposed; it's pure waste. | **live** (waste, correctly disposed) |

## Definition of done

- A **working-resolution cap** is applied in `_nativeFn` (full-frame branch) and
  in both Dart warpers' source path so no float/RGB working buffer exceeds a
  bounded long side (≥ `kDefaultFlatMaxDimension`, tunable, default = the existing
  output cap). The `imdecode`→float→enhance chain for a 12.5 MP full-frame Auto
  save fits a documented, bounded peak.
- `floorMat` full-res allocation is removed (scalar max), and the `none`-mode
  redundant clone is removed.
- The fallback double-decode window is bounded: native is gated by input size
  (large inputs downscale first) and/or the timeout is shortened so the
  concurrent-pipeline window shrinks.
- **Parity gate:** `np2_native_auto_parity_test.dart` re-run on Android + iOS
  shows parity mean ≤ **0.151**.
- **Green gate:** `np1`, `np2`, `np3`, `e2`, `g3` GREEN on **both** a real Android
  and a real iOS device; full host suite GREEN.
- Pure downscale-decision helper has failing-first host unit tests that pass.

## Before → After (peak memory, one 12.5 MP full-frame + Auto save)

Estimates use ~12.5 MP = 12.5e6 px. `CV_8UC3` ≈ 3 B/px ≈ 37.5 MB;
`CV_32FC3` ≈ 12 B/px ≈ 150 MB. Cap target below = 3500 px long side ≈ ~8 MP for a
4:3 frame ≈ `CV_8UC3` ≈ 24 MB, `CV_32FC3` ≈ 96 MB (illustrative; exact depends on
aspect).

| Buffer (at peak) | Before | After |
|------------------|--------|-------|
| decoded `src` (`CV_8UC3`) | ~37.5 MB (full-res) | ~37.5 MB (decode still full-res; freed right after downscale) |
| working `src'` (downscaled `CV_8UC3`) | — (none; works full-res) | ~24 MB (bounded) |
| `warped` full-frame clone (`CV_8UC3`) | ~37.5 MB | removed for `none`; ~24 MB when needed (from bounded `src'`) |
| `srcF` (`CV_32FC3`) | ~150 MB | ~96 MB (from bounded `src'`) |
| `bgF` (`CV_32FC3`) | ~150 MB | ~96 MB |
| `bgFloored` (`CV_32FC3`) | ~150 MB | ~96 MB |
| `flatF` (`CV_32FC3`) | ~150 MB | ~96 MB |
| `floorMat` (`CV_32FC3`, constant scalar) | ~150 MB | **0** (scalar `cv.max`) |
| **Native peak (single page)** | **~975 MB–1.0 GB** | **~410 MB** |
| Fallback wedge (2 pipelines concurrent) | **~2× → ~2 GB** | bounded input → **~2× of bounded ≈ ~0.8 GB**, shorter window |

After-peak is dominated by the four remaining float Mats; a follow-up (P08/P09
math extraction) can fuse some, but P01's cap alone takes peak below half.

## Tasks (small, independent, subagent-ready)

Each task names its scope, files, test-first step, done criterion, and whether it
is parallel-safe with the others. Tasks 1–5 are independent; Task 6 (device
verification) depends on 1–5 landing.

### Task 1 — Pure downscale-decision helper (host-testable math)
- **Scope:** Add a pure function computing the working-resolution scale/target
  dims from `(srcW, srcH, cap)` — mirrors the existing cap logic in
  `_warpStraight`/`warpPerspectiveToImage` but as a standalone, `cv`-free,
  `img`-free function returning `(scale, targetW, targetH)`.
- **Files:** new `lib/features/library/work_resolution.dart` (pure Dart);
  test `test/features/library/work_resolution_test.dart`.
- **Test-first:** failing unit tests — no downscale when `long ≤ cap`; correct
  proportional target when `long > cap`; both dims clamped to ≥ 2; monotonic.
- **Done:** helper + tests GREEN under plain `flutter test` (no CV needed).
- **Parallel-safe:** yes (new file, no existing behavior touched).

### Task 2 — Cap native full-frame working resolution
- **Scope:** In `_nativeFn`, when `corners == fullFrame`, downscale `src` to the
  Task-1 target *before* `_autoFlatField` / enhancer dispatch (resize into a new
  `src'`, dispose the full-res `src` promptly, run the float pass on `src'`).
  Cropped path already caps in `_warpStraight` — leave it.
- **Files:** `lib/features/library/native_page_processor.dart`.
- **Test-first:** device parity assertion in `np2` (a large fixture) must still
  hold ≤ 0.151; add a fixture large enough that the float pass would previously
  exceed the cap. (Host CV run via `setup-cv-host-test.sh` for a smoke check.)
- **Done:** device `np1`/`np2` GREEN on Android + iOS; peak matches the After table.
- **Parallel-safe:** yes with Tasks 3/4/5 (touches only the full-frame branch);
  serialize *edits* to this file if two tasks land together (see Task 4/5 note).

### Task 3 — Remove `floorMat` full-res allocation (scalar max)
- **Scope:** Replace `floorMat = cv.Mat.fromScalar(...)` + `cv.max(bgF, floorMat)`
  with a scalar-max (`cv.max` against a `cv.Scalar`, or `cv.threshold`/`cv.max`
  scalar overload) so no full-res constant Mat is allocated. Remove `floorMat`
  from the disposal list.
- **Files:** `lib/features/library/native_page_processor.dart` (`_autoFlatField`).
- **Test-first:** parity is the gate — `np2` must stay ≤ 0.151 (scalar max is
  bitwise-equivalent to max-against-constant-Mat).
- **Done:** device `np2` GREEN on both platforms; one fewer float Mat.
- **Parallel-safe:** yes (localized to `_autoFlatField`; coordinate the shared
  disposal list edit with Task 5 if landing together).

### Task 4 — Cap Dart warp source buffer
- **Scope:** Before the sampling loop, if the source long side exceeds a small
  multiple of the output cap, downscale the baked `src` (via `img.copyResize`)
  and adjust `w`/`h`/`stride` accordingly, so `src.getBytes` materializes a
  bounded buffer. Applies to both `warpPerspectiveToImage` and `warpCoonsToImage`.
- **Files:** `lib/features/library/perspective_warper.dart`,
  `lib/features/library/coons_warper.dart`.
- **Test-first:** device `e2_flatten` / `e4_curved_warp` must stay GREEN
  (geometry unchanged; only sampling source resolution is bounded — verify visual
  parity on device). Host unit test on the multiplier decision reuses Task 1.
- **Done:** `e2`, `e4_curved_warp` GREEN on Android + iOS.
- **Parallel-safe:** yes (separate files from Tasks 2/3/5).

### Task 5 — Drop redundant `none`-mode clone
- **Scope:** In `_nativeFn`, encode `warped` directly for `EnhancerMode.none`
  instead of `warpedMat.clone()`; ensure lifecycle stays correct (`warped` is
  already disposed in the outer `finally`; the encoded output is a separate
  buffer). Document the `warped != src` invariant inline (feeds P08's
  double-dispose note).
- **Files:** `lib/features/library/native_page_processor.dart`.
- **Test-first:** `np3` (`none`/straight path) GREEN on device.
- **Parallel-safe:** yes; **note**: Tasks 2/3/5 all edit
  `native_page_processor.dart` — hand them to one subagent as a coordinated
  single-file pass, OR sequence 2→3→5 to avoid edit conflicts. Tasks 1/4 are
  fully independent.

### Task 6 — Bound the fallback double-decode window
- **Scope:** Gate `NativePageProcessor` by input size (very large inputs skip
  native / downscale first) and/or shorten the native timeout, so the window in
  which a wedged native isolate + a running Dart fallback coexist is minimized.
  Keep `FallbackPageProcessor`'s public contract intact.
- **Files:** `lib/features/library/native_page_processor.dart` (and, if a size
  gate is exposed, `library_dependencies.dart` L63–65 wiring — coordinate with
  P08's `withRunner` seam).
- **Test-first:** a host test with a fake slow `PipelineRunner` (needs the P08
  `withRunner` seam) asserting the fallback still produces output and the window
  is bounded. If P08 hasn't landed, gate purely on input size (host-testable
  pure decision) and defer the injected-timeout test to P08.
- **Done:** device `np1` GREEN; documented window bound.
- **Parallel-safe:** independent of Tasks 1/4; coordinates with P08 for the seam.

## Risks & mitigations

- **Risk: capping working resolution shifts auto-enhance output → parity break.**
  Mitigation: cap ≥ existing output cap; flat-field is scale-tolerant (proxy +
  bilinear upsample); **measure** parity via `np2` on both devices, gate ≤ 0.151.
- **Risk: scalar-max not bit-identical to Mat-max.** Mitigation: OpenCV scalar
  `max` is defined identically per-element; if any drift, keep the Mat but
  allocate it at proxy scale — still removes the full-res alloc.
- **Risk: downscaling the warp source softens output.** Mitigation: use a small
  *multiple* of the output cap for the source (super-sampling headroom), verify
  sharpness on device against `e2`/`e4` fixtures.
- **Risk: file-edit conflicts** across Tasks 2/3/5. Mitigation: single coordinated
  pass per the Task 5 note. **Coordinate with P08** (same file restructure) — run
  **P01 first**, then P08 rebases onto the hardened file (stated in P08).

## Verification commands

Discover device ids: `flutter devices`. Substitute `<android-id>` / `<ios-id>`.

```bash
# From apps/mobile/
# Host math (Task 1 helper) — no CV needed:
flutter test test/features/library/work_resolution_test.dart

# Host CV-adjacent smoke (optional): source the CV env first
bash ../../scripts/setup-cv-host-test.sh      # prints DARTCV_LIB_PATH / DYLD_LIBRARY_PATH to export

# Device — Android (native pipeline + parity + none/color/gray + flatten + auto):
flutter test integration_test/np1_native_pipeline_test.dart      -d <android-id>
flutter test integration_test/np2_native_auto_parity_test.dart   -d <android-id>   # parity ≤ 0.151
flutter test integration_test/np3_native_color_gray_test.dart    -d <android-id>
flutter test integration_test/e2_flatten_test.dart               -d <android-id>
flutter test integration_test/e4_curved_warp_test.dart           -d <android-id>
flutter test integration_test/g3_auto_color_test.dart            -d <android-id>

# Device — iOS (same set, mandatory):
flutter test integration_test/np1_native_pipeline_test.dart      -d <ios-id>
flutter test integration_test/np2_native_auto_parity_test.dart   -d <ios-id>       # parity ≤ 0.151
flutter test integration_test/np3_native_color_gray_test.dart    -d <ios-id>
flutter test integration_test/e2_flatten_test.dart               -d <ios-id>
flutter test integration_test/e4_curved_warp_test.dart           -d <ios-id>
flutter test integration_test/g3_auto_color_test.dart            -d <ios-id>

# Full host suite (must stay green):
flutter test
flutter analyze
```
