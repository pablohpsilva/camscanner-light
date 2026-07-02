# S1 — Reduce Android app size (design)

**Date:** 2026-07-02
**Status:** Approved (design)
**Sub-project:** Release engineering — Android artifact size
**Depends on:** nothing functional; touches only Android build config + release commands.

## Purpose

Shrink what a user actually downloads/installs on Android. The current release
artifact is a **187 MB universal APK** that bundles native libraries for three
CPU ABIs at once, even though any single device uses exactly one. This step
delivers per-ABI artifacts (so each device gets only its slice), attempts R8
code/resource shrinking behind an on-device gate, and strips residual Dart
symbols — without dropping any ABI and without changing app behavior.

## Measured baseline (real builds, 2026-07-02)

Universal (current) release APK: **187 MB**. Native libs dominate it; every
`.so` ships ×3 (x86_64, arm64-v8a, armeabi-v7a).

A real `flutter build apk --split-per-abi --release` produced:

| Split APK | Size | vs 187 MB |
| --- | --- | --- |
| `app-arm64-v8a-release.apk` | 72.5 MB | −61% |
| `app-armeabi-v7a-release.apk` | 57.2 MB | −69% |
| `app-x86_64-release.apk` | 82.7 MB | −56% |

So per-ABI delivery alone takes a real ARM phone from 187 MB to ~57–72 MB with
**zero code change**. Material icons are already tree-shaken (1.6 MB → 4.9 KB);
nothing to gain there.

Largest native contributors per ABI (arm64 figures, uncompressed): `libdartcv.so`
≈ 23 MB (OpenCV, `opencv_dart`), `libflutter.so` ≈ 12 MB, ML Kit OCR pipeline
≈ 11 MB, `libapp.so` (Dart AOT) ≈ 9 MB, ffmpeg stack ≈ 7 MB, `libsqlite3.so`
≈ 1.7 MB. Java/Kotlin dex (`classes.dex` + `classes2.dex`) ≈ 17 MB, shipped
un-shrunk because R8 is currently disabled.

## Scope

- **In:**
  1. Per-ABI delivery for both channels: an Android App Bundle (`.aab`) for
     Play (per-device delivery), and split-per-ABI APKs for direct/sideload
     install. **All three ABIs retained.**
  2. R8 minification + resource shrinking, gated on a successful build **and**
     an on-device smoke pass; reverted (with a recorded reason) if it cannot be
     made to pass cleanly.
  3. Dart symbol stripping via `--split-debug-info` + `--obfuscate`.
  4. A canonical release-build script and a `scripts/verify/s1.sh` size gate.
- **Out:**
  - Dropping any ABI (product decision: keep all three).
  - **ffmpeg removal from `opencv_dart`** — see "Deferred" below.
  - Switching ML Kit to an unbundled (Play-services-delivered) model, or any
    change to OCR/scan runtime behavior.
  - iOS artifact size (this step is Android-only).

## Component 1 — Per-ABI delivery (guaranteed win)

Flutter's own tooling performs the ABI split; **no Gradle `splits {}` block is
added** (it would duplicate/parallel what the Flutter tool already does and can
conflict). The deliverables are reproducible commands plus a size gate:

- **Sideload APKs:** `flutter build apk --split-per-abi --release` → three
  per-ABI APKs under `build/app/outputs/flutter-apk/`.
- **Play bundle:** `flutter build appbundle --release` → one `.aab` under
  `build/app/outputs/bundle/release/`; Play delivers only the device's ABI +
  density + language.
- A canonical script `scripts/build-release.sh` runs both with the symbol-strip
  flags (Component 3), so the release is reproducible from one entry point.

**Verification:** `scripts/verify/s1.sh` asserts (a) all three split APKs exist,
(b) each split is materially smaller than a universal build (each < 120 MB, and
the arm64 split < 100 MB — thresholds chosen well below the 187 MB universal and
above the observed 57–83 MB so drift is caught without being brittle), and
(c) the `.aab` exists. Sizes are read from the built files; SILENCE = FAILURE.

## Component 2 — R8 minify + resource shrink (conditional, on-device gated)

Today `android/app/build.gradle.kts` sets `isMinifyEnabled = false` and
`isShrinkResources = false` with a comment: naive R8 breaks because the ML Kit
text plugin references optional CJK/Devanagari recognizer classes that the
Latin-only bundle does not include. There is **no `proguard-rules.pro`** today.

- Create `android/app/proguard-rules.pro` with:
  - `-dontwarn` + `-keep` for the ML Kit text-recognition optional recognizer
    classes (Chinese/Devanagari/Japanese/Korean) so R8 neither fails on the
    missing references nor strips the Latin path.
  - `-keep` rules for the other plugins that use reflection/JNI entry points:
    `camera`, `pdfx`, `drift`/`sqlite3_flutter_libs`, `share_plus`,
    `permission_handler`, `printing`, and `opencv_dart` (JNI).
- Set `isMinifyEnabled = true` and `isShrinkResources = true` in the release
  build type.
- **Gate (hard):** the release build must succeed **and** an on-device smoke
  run on Samsung `RZCY51D0T1K` must pass the full path — launch → scan a page →
  edge detect → OCR → export PDF → export/share image. If either fails and
  cannot be fixed with additional keep rules within this step, **revert
  Component 2** (restore `isMinifyEnabled = false`, `isShrinkResources = false`,
  remove/neutralize the rules) and record the reason in the task report and the
  plans index row. Components 1 and 3 stand on their own regardless.
- Expected saving: a few MB off the ~17 MB dex + a small resource trim, per
  split. The exact figure is measured post-build, not asserted to a fixed
  number (R8 output varies).

## Component 3 — Dart symbol stripping

- Build with `--split-debug-info=build/symbols --obfuscate` (folded into
  `scripts/build-release.sh`). This strips residual symbol/name information from
  `libapp.so` (~1–2 MB/ABI) and writes de-symbolication maps under
  `build/symbols/`.
- The symbol maps MUST be retained per release to de-obfuscate future crash
  traces; `scripts/build-release.sh` writes them to a stable, git-ignored
  `build/symbols/` path and prints the location.
- **Verification:** `scripts/verify/s1.sh` asserts the `build/symbols/`
  directory is non-empty after a release build (proves obfuscation ran).

## Deferred — ffmpeg removal (separate future spike)

Investigation (2026-07-02): `libdartcv.so` (from `opencv_dart` 1.4.5) declares
hard ELF `NEEDED` entries on `libavcodec`, `libavformat`, `libavutil`,
`libswscale`, `libavfilter`, `libswresample`. The dynamic linker resolves these
at load time, so **excluding the ffmpeg `.so` files via packaging rules would
crash the app on first OpenCV call**. The app itself uses only OpenCV
core + imgproc (`imdecode`, `cvtColor`, `gaussianBlur`, `canny`, `findContours`,
`contourArea`, `arcLength`, `approxPolyDP`, `isContourConvex`) — no videoio —
so ffmpeg is functionally dead weight (~7 MB/ABI). Removing it requires
rebuilding libdartcv with `-DWITH_FFMPEG=OFF` / videoio disabled, i.e. forking
or patching `opencv_dart`'s CMake native build. That is fragile (a pub-cache
patch is wiped on every `pub get`; a fork carries maintenance burden) and
disproportionate now that the per-ABI split already delivers the large win.
**Tracked as a separate spike; not built in S1.**

## Testing strategy

Build configuration has no unit surface; the executable gate is the verify
script plus the on-device smoke.

- **`scripts/verify/s1.sh`** (repo root, sourcing `scripts/verify/lib.sh`,
  ending in `verify_summary`), run under the independent verifier:
  - the three split APKs exist and meet the size thresholds above;
  - the `.aab` exists;
  - `android/app/proguard-rules.pro` exists and `build.gradle.kts` reflects the
    chosen R8 state (either minify-on if the gate passed, or minify-off with the
    documented revert — the script asserts the two are consistent with a
    `S1_R8=on|off` marker file written by the build step, so a half-applied
    state fails);
  - `build/symbols/` is non-empty (obfuscation ran);
  - device checks skippable via `VERIFY_SKIP_DEVICE=1`.
- **On-device smoke (Samsung `RZCY51D0T1K`):** install the arm64 split (or the
  R8 build) and run scan → detect → OCR → export PDF → share image; this is the
  hard gate for Component 2 and reconfirms Components 1/3 produce a working app.

## Definition of Done

- `flutter build apk --split-per-abi` and `flutter build appbundle` both
  produce artifacts via `scripts/build-release.sh`; arm64 split ≤ ~73 MB
  (vs 187 MB universal), all three ABIs present, `.aab` present.
- R8: either enabled with keep rules and green on-device, **or** cleanly
  reverted with a recorded reason — never a half-applied state.
- `--split-debug-info` + `--obfuscate` applied; symbol maps retained under
  `build/symbols/`.
- ffmpeg removal documented as a deferred spike (not implemented).
- `scripts/verify/s1.sh` passes under the independent verifier from a clean
  build; plans index S1 row added.
- `flutter analyze` clean; no app behavior change (on-device smoke green).
