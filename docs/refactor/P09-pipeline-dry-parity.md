# P09 — Image-pipeline DRY & parity

**Tier 3 (DRY) · Effort M–L · Risk Med · Depends on: P08 (soft, same-file lane); coordinate P01 · Device verification: Android + iOS (parity-sensitive)**

## Global constraints (honored by this plan)

- **Behavior-preserving.** `PageProcessor`, `ImageWarper`, `EnhancerMode` stay
  stable; the ~25k-LOC suite stays GREEN. Every de-duplication must be
  **byte-output-identical** to the winning current implementation — DRY here is a
  *refactor*, never a behavior change.
- **CV cannot run under plain host `flutter test`** (`libdartcv` absent). The
  extracted pure math (white-point LUT table, bilinear sampler, warp geometry,
  mode registry) gets **failing-first host unit tests**; the Mat-typed native
  callers and the `img.Image` warp loops are verified on a **real Android AND
  real iOS** device. Host CV runs need `scripts/setup-cv-host-test.sh` +
  `DARTCV_LIB_PATH` / `DYLD_LIBRARY_PATH`.
- **Parity is THE gate.** Native and Dart auto-enhance are two independent
  implementations of one algorithm that must stay byte-parity (recorded on-device
  mean **0.151**). Any auto-enhance or warp change re-verifies parity ≤ 0.151 on
  **both** devices (`np2`) and keeps `e*`/`g*` GREEN. **Stress: on-device parity
  verification is the gate for auto-enhance and warp changes.**
- **Decomposed into small independent tasks** below; most are new-file extractions
  that can run in parallel.

## Summary

The pipeline carries **two full independent implementations of the auto-enhance
algorithm** (native `cv.Mat` vs Dart `img.Image`) that must stay byte-parity, plus
several smaller duplications: the inverse-bilinear **sampling loop** (perspective
vs Coons), the **convex-quad test** (warper vs detector), the **output-size rule**
(three different distance implementations), the **enhancer isolate boilerplate**
(three enhancers), and the **`EnhancerMode`↔filter dispatch** (five sites — one of
which literally documents itself as "single source of truth" while another is a
true duplicate). There are also two hot-loop micro-inefficiencies. Every item is
extracted into a single shared, host-testable seam; the parity-sensitive ones are
gated on device.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| `dup-native-vs-dart-autoenhance` | native `_autoFlatField` (`native_page_processor.dart` L107–177) + `_whitePointLut3` (L183–219) vs Dart `autoEnhanceOriented` (`auto_enhancer.dart` L81–102) / `_estimateBackground` (L111–144) / `_maxFilter` (L153–197) / `_flatten` (L207–239) / `_whitePointStretch` (L250–293) | Two full independent impls of ONE algorithm that must stay byte-parity. The white-point loop is line-for-line identical (native L205–216 vs Dart L268–283); constants are already shared (`import auto_enhancer.dart show kAuto...`). | Any tweak must be made twice or parity (0.151) silently drifts. | latent (parity footgun) |
| `dup-warp-sampling-loop` | `perspective_warper.dart` L99–124 vs `coons_warper.dart` L120–160 | Identical inverse-bilinear sampling loop (`srcBuf`/`stride`/`xMax`/`yMax`, `x0`/`y0`/`x1`/`y1`/`wx`/`wy` clamp, 3-ch interp, `Uint8List` packing); ONLY the per-pixel source-coord mapper differs. | ~40 duplicated hot-loop lines; bug-fix/perf must be done twice. | latent |
| `dup-convex-quad-and-geometry` | `_isConvex` (`perspective_warper.dart` L143–158) vs `isConvexQuad` (`detector_geometry.dart` L89–106); output-size "max of opposite edges" rule recurs 3× via DIFFERENT distance impls: `_maxEdge` straight-line (`perspective_warper.dart` L137–140), Coons arc-length 16-seg polyline (`coons_warper.dart` L97–109), native `_warpStraight` local dist (`native_page_processor.dart` L255–277) | Convex test is the same cross-product but eps `1e-8` vs `1e-9` and `continue` vs `return false` (**equivalent, not identical**). The size rule is three separate distance formulas — perspective/native use straight-line, Coons uses arc-length (a **real semantic difference**, not an accident). | Divergent eps/semantics; unifying naively would change Coons behavior. | latent (amend: equivalent-not-identical) |
| `dup-enhancer-isolate-boilerplate` | `auto_enhancer.dart` `_autoFn` (L62–75), `color_enhancer.dart` `_colorFn` (L15–26), `grayscale_enhancer.dart` `_grayscaleFn` (L18–33) | Identical `try{ decode; if null return bytes; bakeOrientation; encodeJpg(xOriented(...), quality) } catch { return bytes }`; only the `*Oriented` call + quality differ (auto 95, others 92). | Triplicated isolate/decode/encode/error contract; drift risk. | latent |
| `dup-mode-dispatch` | `warp_enhancer.dart` `enhancerModeOf` (L36–41, reverse map) & mode→`*Oriented` (L66–71); `enhancer_for_mode.dart` (L10–15, self-labeled "single source of truth" at L8); `dart_page_processor.dart` `_enhancerFor` (L70–75, **true duplicate** of `enhancer_for_mode`); `native_page_processor.dart` dispatch (L78–83) | The `EnhancerMode`↔filter mapping lives in **5 places** (amend: 5 sites), including a self-declared SSOT that is contradicted by a verbatim duplicate. | New mode / mapping change touches 5 files; guaranteed drift. | latent |
| `dart-processor-type-sniffing` | `dart_page_processor.dart` L41–43: `warper is HybridWarper \|\| PerspectiveWarper \|\| CoonsWarper` | Branches on concrete types *behind* the `ImageWarper` interface to pick fused vs two-step — a Liskov/OCP smell; a new real warper is silently treated as "stubbed". | Interface leaks; new warpers mis-routed. | latent |
| `perf-coons-closure-per-pixel` | `coons_warper.dart` L130: `top(u)`/`bottom(u)` (`qbez` closures) recomputed per output pixel though they depend only on column `u` | `left`/`right` are already hoisted per-row (L127); `top`/`bottom` are NOT hoisted per-column → `outW*outH` redundant quadratic-Bézier evals. | Wasted CPU on every Coons warp (bent crops). | **live** (waste) |
| `perf-clamp-in-inner-loop` | `perspective_warper.dart` L120 / `coons_warper.dart` L156: `.clamp(0,255)` in the innermost `outW*outH*3` loop | Values are provably in `[0,255]` after bilinear interp of in-range bytes; `.clamp` is redundant (`.round()` still needed). | Redundant branch per channel per pixel across the whole output. | **live** (waste) |

## Definition of done

- **One** host-testable pure function computes the white-point LUT table, fed by
  BOTH native (→ `cv.Mat.fromList`) and Dart (→ direct per-channel apply);
  parity ≤ 0.151 preserved on device. **(Shared with P08 Task 2 — same module.)**
- **One** `sampleBilinearInto(out, w, h, srcBuf, stride, outW, outH, mapToSrc)`
  drives both perspective and Coons sampling; only the `mapToSrc` closure differs.
- A shared `warp_geometry` module holds the convex test and the output-size rule,
  **preserving the arc-length-vs-straight-line distinction** (parameterized, not
  flattened); eps/`continue`-vs-`return` differences reconciled to one documented
  choice that keeps every current caller's behavior.
- **One** `runOrientedEnhance(bytes, op, {quality})` replaces the three
  enhancer isolate bodies (op = the `*Oriented` transform; quality per mode).
- **One** `EnhancerMode` registry that all 5 dispatch sites derive from; the
  `dart_page_processor._enhancerFor` verbatim duplicate is deleted in favor of
  `enhancer_for_mode`.
- `dart_page_processor` no longer type-sniffs concrete warpers — capability is on
  the seam (`bool supportsFusedEnhance` or a `warpAndEnhance` capability).
- Coons `top`/`bottom` precomputed per-column; redundant inner-loop `.clamp`
  removed (both proven equivalent on device).
- **Gate:** `np2` parity ≤ 0.151 on Android + iOS; `e1`–`e5`, `e4_curved_warp`,
  `g1`/`g3`/`g4` GREEN on both devices; full host suite + `flutter analyze` GREEN.

## Before → After

| Concern | Before | After |
|---------|--------|-------|
| Auto-enhance impls | 2 full (native + Dart); white-point loop line-for-line duplicated | 1 shared pure LUT-table fn feeds both; rest stays byte-parity |
| Bilinear sampling loop | 2 copies (perspective, Coons) | 1 `sampleBilinearInto(...mapToSrc)` |
| Convex-quad test | 2 (eps 1e-8 vs 1e-9; `continue` vs `return false`) | 1 shared, documented eps/semantics |
| Output-size rule | 3 distance impls (straight/arc-length/local) | 1 module, arc-length vs straight-line **parameterized** (behavior preserved) |
| Enhancer isolate body | 3 copies (auto/color/gray) | 1 `runOrientedEnhance(bytes, op, {quality})` |
| Mode↔filter dispatch | 5 sites (incl. a self-declared SSOT + a true duplicate) | 1 registry; duplicate deleted |
| Warper routing | concrete-type `is` checks behind `ImageWarper` | explicit `supportsFusedEnhance` capability on the seam |
| Coons `top`/`bottom` | per-pixel Bézier eval | per-column precompute |
| Inner-loop `.clamp(0,255)` | per channel per pixel | removed (provably in range) |
| Public seams | `PageProcessor`/`ImageWarper`/`EnhancerMode` | **unchanged** (capability flag is additive) |

## Coordination note

`dup-native-vs-dart-autoenhance` (Task 1) shares its extracted LUT module with
**P08 Task 2** — assign both to coordinated owners so there is ONE
`white_point_lut.dart`. Tasks that edit `native_page_processor.dart` (Task 1's
native caller) must coordinate with **P01** (OOM caps) and **P08** (file split):
run P01 first, land P08's split, then P09 points the split native enhancer at the
shared math. If P09's math extraction lands before P08's split, P08 imports it.

## Tasks (small, independent, subagent-ready)

Tasks 1–8 are mostly independent new-file extractions. Where a task edits
`native_page_processor.dart`, serialize with P01/P08 per the coordination note.

### Task 1 — Unify white-point LUT-table math (parity-critical)
- **Scope:** Extract the pure per-channel white-point table build (identity
  default, clip, `kAutoBlackAnchor`, linear span) into one `cv`-free fn consuming
  three 256-bin histograms → 256×3 table. Native `_whitePointLut3` (L196–218)
  wraps it in `cv.Mat.fromList`; Dart `_whitePointStretch` (L266–285) applies it
  per channel. **Same module as P08 Task 2.**
- **Files:** new/shared `lib/features/library/white_point_lut.dart`;
  edit `native_page_processor.dart`, `auto_enhancer.dart`;
  test `test/features/library/white_point_lut_test.dart`.
- **Test-first:** failing host tests (identity default; clip picks white point;
  anchor; span scaling; monotonic table) derived from current Dart math as the
  reference.
- **Done:** host tests GREEN; **device `np2` parity ≤ 0.151 on Android + iOS**;
  `g3` GREEN both.
- **Parallel-safe:** touches native file → coordinate with P01/P08; otherwise yes.

### Task 2 — Extract `sampleBilinearInto`
- **Scope:** Factor the identical inverse-bilinear inner loop
  (`perspective_warper.dart` L99–124, `coons_warper.dart` L120–160) into
  `sampleBilinearInto(out, srcBuf, w, h, stride, outW, outH, Offset Function(int dx,int dy) mapToSrc)`.
  Perspective passes `hInv`-apply as the mapper; Coons passes its Coons-patch map.
- **Files:** new `lib/features/library/bilinear_sampler.dart`;
  edit `perspective_warper.dart`, `coons_warper.dart`;
  test `test/features/library/bilinear_sampler_test.dart`.
- **Test-first:** failing host tests — identity map returns the source; known
  4-corner map returns known interpolated values.
- **Done:** host tests GREEN; device `e2`/`e4_curved_warp` GREEN both platforms.
- **Parallel-safe:** yes (independent files from Tasks 1/4/5/6).

### Task 3 — Shared `warp_geometry` (convex + size rule)
- **Scope:** One module with the convex-quad test (reconcile eps `1e-8`/`1e-9`
  and `continue`/`return false` to one documented choice preserving BOTH callers'
  behavior) and the output-size rule **parameterized by distance strategy**
  (`straightLine` vs `arcLength16`) so perspective/native use straight-line and
  Coons keeps arc-length — the semantic difference is preserved, not erased.
  Replaces `_isConvex`, `isConvexQuad`, `_maxEdge`, Coons `arc`, native size math.
- **Files:** new `lib/features/library/warp_geometry.dart`;
  edit `perspective_warper.dart`, `coons_warper.dart`,
  `native_page_processor.dart`, `detector_geometry.dart`;
  test `test/features/library/warp_geometry_test.dart`.
- **Test-first:** failing host tests — convex/concave/collinear; straight-line vs
  arc-length size for a curved edge (must differ, matching current Coons vs
  perspective). **May merge with P08 Task 1** (`native_warp_geometry`) — flag it.
- **Done:** host tests GREEN; device `e1`/`e2`/`e4_curved_warp`/`np1` GREEN both.
- **Parallel-safe:** edits native file → coordinate with P01/P08.

### Task 4 — `runOrientedEnhance` helper
- **Scope:** Extract the shared isolate body into
  `runOrientedEnhance(bytes, img.Image Function(img.Image) op, {int quality})`:
  decode → null-guard → `bakeOrientation` → `encodeJpg(op(...), quality)` →
  catch→return bytes. `_autoFn`/`_colorFn`/`_grayscaleFn` become one-liners
  (quality 95/92/92).
- **Files:** new `lib/features/library/oriented_enhance.dart`;
  edit `auto_enhancer.dart`, `color_enhancer.dart`, `grayscale_enhancer.dart`;
  test `test/features/library/oriented_enhance_test.dart`.
- **Test-first:** failing host tests — corrupt bytes → returned unchanged; a
  known op is applied; quality passed through.
- **Done:** host tests GREEN; device `g1`/`g3` GREEN both platforms.
- **Parallel-safe:** yes (independent files).

### Task 5 — Single `EnhancerMode` registry + delete duplicate
- **Scope:** Introduce one registry mapping `EnhancerMode` ↔ enhancer ↔
  `*Oriented` op ↔ quality; derive all 5 sites (`enhancerModeOf`,
  `warp_enhancer` mode→op, `enhancer_for_mode`, `dart_page_processor._enhancerFor`
  **[delete — verbatim dup]**, native dispatch) from it.
- **Files:** edit `enhancer_for_mode.dart` (or a new `enhancer_mode_registry.dart`),
  `warp_enhancer.dart`, `dart_page_processor.dart`, `native_page_processor.dart`;
  test `test/features/library/enhancer_mode_registry_test.dart`.
- **Test-first:** failing host test — every mode round-trips mode→enhancer→mode;
  quality per mode; no site diverges.
- **Done:** host tests GREEN; device `g4_filter_picker`/`e5_edit_filter` GREEN both.
- **Parallel-safe:** edits native file → coordinate with P01/P08.

### Task 6 — `supportsFusedEnhance` capability on the seam
- **Scope:** Add `bool get supportsFusedEnhance` (default per implementation) to
  `ImageWarper` (or a `warpAndEnhance` capability); `dart_page_processor` (L41–43)
  reads it instead of `warper is HybridWarper || PerspectiveWarper || CoonsWarper`.
  Stubbed test warpers report `false` → two-step path preserved.
- **Files:** edit `image_warper.dart`, `hybrid_warper.dart`,
  `perspective_warper.dart`, `coons_warper.dart`, `dart_page_processor.dart`;
  tests under `test/features/library/`.
- **Test-first:** failing host test — a fake warper with `supportsFusedEnhance =
  false` takes two-step; real warpers take fused (existing behavior).
- **Done:** host tests GREEN; device `e1`/`e2`/`e3`/`e4`/`e5` GREEN both platforms.
- **Parallel-safe:** yes (does not touch native file).

### Task 7 — Precompute Coons `top`/`bottom` per column
- **Scope:** Hoist `top(u)`/`bottom(u)` into per-column arrays computed once
  (mirroring the per-row `left`/`right` at L127); inner loop indexes them.
- **Files:** `coons_warper.dart`; existing device `e4_curved_warp` covers it.
- **Test-first:** device `e4_curved_warp` output must be byte-identical
  (precompute is arithmetically identical). Add a host golden on
  `warpCoonsToImage` output for a small fixture if CV-free-runnable.
- **Done:** `e4_curved_warp` GREEN + unchanged output on both devices.
- **Parallel-safe:** yes; **sequence after Task 2** if both edit the Coons loop
  (or fold Task 7 into Task 2's Coons edit).

### Task 8 — Drop redundant inner-loop `.clamp(0,255)`
- **Scope:** Remove `.clamp(0,255)` at `perspective_warper.dart` L120 /
  `coons_warper.dart` L156 (values provably in range post-interp); keep
  `.round()`.
- **Files:** `perspective_warper.dart`, `coons_warper.dart`.
- **Test-first:** device `e2`/`e4_curved_warp` byte-identical output (prove the
  clamp was a no-op).
- **Done:** `e2`/`e4_curved_warp` GREEN + unchanged output on both devices.
- **Parallel-safe:** yes; sequence with Task 2 if both touch the same lines.

## Risks & mitigations

- **Risk: unifying auto-enhance breaks native↔Dart parity (0.151).** Mitigation:
  extract ONLY the pure table math (Task 1), leave the surrounding native/Dart
  glue; gate every landing on `np2` ≤ 0.151 on **both** devices.
- **Risk: flattening the size rule silently changes Coons (arc-length) to
  straight-line.** Mitigation: Task 3 **parameterizes** the distance strategy;
  host test asserts the two strategies differ on a curved edge.
- **Risk: reconciling convex eps (1e-8 vs 1e-9) flips a borderline quad.**
  Mitigation: pick the stricter/looser deliberately, host-test both callers'
  boundary cases, verify `e1`/`e4` on device.
- **Risk: removing `.clamp` / changing loop shape alters output by 1 LSB.**
  Mitigation: device byte-identity check (Tasks 7/8) before claiming done.
- **Risk: capability flag mis-routes a warper.** Mitigation: default preserves
  today's routing; fake-warper host test locks the two-step path.
- **Risk: file conflicts on `native_page_processor.dart` (Tasks 1/3/5 + P01/P08).**
  Mitigation: coordination note — P01 first, P08 split, then P09 points the split
  module at shared math; one owner per file.

## Verification commands

```bash
# From apps/mobile/
# Host (pure extractions, no CV):
flutter test test/features/library/white_point_lut_test.dart
flutter test test/features/library/bilinear_sampler_test.dart
flutter test test/features/library/warp_geometry_test.dart
flutter test test/features/library/oriented_enhance_test.dart
flutter test test/features/library/enhancer_mode_registry_test.dart

# Optional host CV smoke: source env first
bash ../../scripts/setup-cv-host-test.sh   # export the printed DARTCV_LIB_PATH / DYLD_LIBRARY_PATH

# Device — Android (parity + warp + filters):
flutter test integration_test/np1_native_pipeline_test.dart     -d <android-id>
flutter test integration_test/np2_native_auto_parity_test.dart  -d <android-id>   # parity ≤ 0.151
flutter test integration_test/e1_crop_test.dart                 -d <android-id>
flutter test integration_test/e2_flatten_test.dart              -d <android-id>
flutter test integration_test/e4_curved_warp_test.dart          -d <android-id>
flutter test integration_test/e5_edit_filter_test.dart          -d <android-id>
flutter test integration_test/g1_grayscale_test.dart            -d <android-id>
flutter test integration_test/g3_auto_color_test.dart           -d <android-id>
flutter test integration_test/g4_filter_picker_test.dart        -d <android-id>

# Device — iOS (mandatory — same set):
flutter test integration_test/np1_native_pipeline_test.dart     -d <ios-id>
flutter test integration_test/np2_native_auto_parity_test.dart  -d <ios-id>       # parity ≤ 0.151
flutter test integration_test/e1_crop_test.dart                 -d <ios-id>
flutter test integration_test/e2_flatten_test.dart              -d <ios-id>
flutter test integration_test/e4_curved_warp_test.dart          -d <ios-id>
flutter test integration_test/e5_edit_filter_test.dart          -d <ios-id>
flutter test integration_test/g1_grayscale_test.dart            -d <ios-id>
flutter test integration_test/g3_auto_color_test.dart           -d <ios-id>
flutter test integration_test/g4_filter_picker_test.dart        -d <ios-id>

# Whole-suite gate:
flutter test
flutter analyze
```
