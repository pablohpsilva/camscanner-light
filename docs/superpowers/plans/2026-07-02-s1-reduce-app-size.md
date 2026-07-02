# S1 — Reduce Android app size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut what an Android user downloads/installs from a 187 MB universal APK to ~57–72 MB per device, via per-ABI delivery + Dart symbol stripping (guaranteed), plus an on-device-gated R8 attempt — with no app behavior change.

**Architecture:** Three independent build-config changes. (1) A reproducible release-build script that emits per-ABI split APKs (sideload) and an App Bundle (Play), both with `--obfuscate --split-debug-info`. (2) R8 code/resource shrinking behind keep rules, gated on an on-device pass and auto-reverted if it can't pass. (3) A `scripts/verify/s1.sh` size/behaviour gate. No Dart/app source changes; all three ABIs retained.

**Tech Stack:** Flutter (Android build), Gradle Kotlin DSL, R8/ProGuard, bash verify harness (`scripts/verify/lib.sh`), ADB, Samsung device `RZCY51D0T1K`.

## Global Constraints

- Platform in scope: **Android only.** No iOS artifact changes.
- **Keep all three ABIs** (`arm64-v8a`, `armeabi-v7a`, `x86_64`) — do not drop any.
- **No app behavior change**; no Dart/`lib/` source edits; no dependency add/remove.
- **ffmpeg removal is OUT of scope** (deferred spike — `libdartcv.so` hard-links ffmpeg via ELF `NEEDED`; excluding the `.so` crashes the app at load).
- Obfuscation symbol maps (`build/symbols/`) MUST be produced on every release build (retention is an operational concern; `build/` is git-ignored).
- R8 is **all-or-nothing**: enabled with keep rules and green on-device, OR fully reverted with a recorded reason. Never a half-applied state.
- On-device gate device: Samsung `RZCY51D0T1K`. Host/analyze must stay green.
- Verify script ends in `verify_summary`; **silence = FAILURE**; `VERIFY_SKIP_DEVICE=1` skips device checks.
- Measured baseline (2026-07-02, real builds): universal APK **187 MB**; splits **arm64 72.5 MB / armv7 57.2 MB / x86_64 82.7 MB**; AAB builds clean (155 MB upload artifact, per-device delivery ≈ split size).

---

### Task 1: Reproducible per-ABI + AAB release build with symbol stripping

Delivers Components 1 & 3 from the spec. No app code changes — this is a build entry point plus obfuscation flags. This task alone takes a real ARM device from 187 MB → ~57–72 MB.

**Files:**
- Create: `scripts/build-release.sh`
- Verify (author in Task 3): `scripts/verify/s1.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `scripts/build-release.sh` — a bash script that, run from repo root, builds all Android release artifacts and prints the marker line `S1 RELEASE BUILD COMPLETE` on success. Outputs:
  - `apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  - `apps/mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
  - `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk`
  - `apps/mobile/build/app/outputs/bundle/release/app-release.aab`
  - `apps/mobile/build/symbols/` (non-empty; obfuscation maps)

- [ ] **Step 1: Write the script**

Create `scripts/build-release.sh`:

```bash
#!/usr/bin/env bash
# Build all Android release artifacts at the smallest per-device size:
#   - per-ABI split APKs (sideload)      -> build/app/outputs/flutter-apk/
#   - App Bundle (Play, per-device split) -> build/app/outputs/bundle/release/
# Both are obfuscated with split debug info; symbol maps land in build/symbols/
# (retain these per release to de-symbolicate crash traces).
#
# Usage (from repo root):  bash scripts/build-release.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APP="$ROOT/apps/mobile"
SYMBOLS="$APP/build/symbols"

cd "$APP"

echo "== [1/2] split-per-abi release APKs =="
flutter build apk --release --split-per-abi \
  --obfuscate --split-debug-info="$SYMBOLS"

echo "== [2/2] release App Bundle (.aab) =="
flutter build appbundle --release \
  --obfuscate --split-debug-info="$SYMBOLS"

echo "== artifact sizes =="
ls -lh build/app/outputs/flutter-apk/*-release.apk 2>/dev/null | awk '{print $5, $9}'
ls -lh build/app/outputs/bundle/release/*.aab 2>/dev/null | awk '{print $5, $9}'
echo "== symbol maps (retain per release) =="
ls -1 "$SYMBOLS" 2>/dev/null | sed 's/^/  /'

echo "S1 RELEASE BUILD COMPLETE"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/build-release.sh`

- [ ] **Step 3: Run it and verify artifacts + sizes**

Run: `bash scripts/build-release.sh`
Expected: ends with `S1 RELEASE BUILD COMPLETE`; three `*-release.apk` printed with sizes in the ~55–85 MB range (arm64 ≈ 72 MB, not 187 MB); one `app-release.aab` printed; `build/symbols/` lists non-empty `app.android-*.symbols` files.

- [ ] **Step 4: Confirm each split carries exactly one ABI (completeness)**

Run:
```bash
cd apps/mobile
for a in arm64-v8a armeabi-v7a x86_64; do
  f=build/app/outputs/flutter-apk/app-$a-release.apk
  echo "$a: abis=$(unzip -l "$f" | grep -oE 'lib/[^/]+/' | sort -u | tr '\n' ' ') libapp=$(unzip -l "$f" | grep -c 'libapp.so')"
done
```
Expected: each line shows only its own `lib/<abi>/` and `libapp=1` (single-ABI, complete).

- [ ] **Step 5: Commit**

```bash
git add scripts/build-release.sh
git commit -m "build(s1): reproducible per-ABI + AAB release build with obfuscation/symbol strip"
```

---

### Task 2: R8 minify + resource shrink (keep rules, on-device gated, auto-revert)

Delivers Component 2. Attempts to shrink the ~17 MB dex + resources. **Hard gate:** the R8 release build must succeed AND the arm64 release APK must install + launch on `RZCY51D0T1K` AND the on-device OCR path must be smoke-verified. If any fails and cannot be fixed with additional keep rules within this task, **revert this task entirely** (Steps 7–8) and record the reason — Tasks 1 & 3 still ship the −61% win.

**Files:**
- Create: `apps/mobile/android/app/proguard-rules.pro`
- Modify: `apps/mobile/android/app/build.gradle.kts` (the `release` build type block, currently `isMinifyEnabled = false` / `isShrinkResources = false`)

**Interfaces:**
- Consumes: `scripts/build-release.sh` (Task 1) to produce the R8 release artifacts.
- Produces: `android/app/build.gradle.kts` release block with `isMinifyEnabled = true`, `isShrinkResources = true`, `proguardFiles(...)` referencing `proguard-rules.pro` — OR, on revert, the original `false/false` block with no ProGuard reference (recorded reason in the task report). Task 3's verify script asserts these two states are internally consistent.

- [ ] **Step 1: Write the keep rules**

Create `apps/mobile/android/app/proguard-rules.pro`:

```proguard
# --- S1 R8 keep rules ---------------------------------------------------------
# R8 is enabled to shrink the Java/Kotlin dex + resources. These rules keep the
# reflection/JNI entry points R8 cannot see and silence optional classes that
# are referenced but intentionally NOT bundled.

# Flutter embedding (flutter ships consumer rules; explicit for safety).
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# ML Kit text recognition: the Latin recognizer is bundled; the plugin also
# references optional CJK/Devanagari/Japanese/Korean recognizers that are NOT
# bundled (Latin-only build). Keep the ML Kit + GMS surface and silence the
# missing optional classes so R8 neither fails on them nor strips the Latin OCR
# path. (This is the exact failure the old build.gradle comment warned about.)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# opencv_dart JNI/loader side (native FFI symbols are untouched by R8).
-keep class dev.rainyl.** { *; }
-dontwarn dev.rainyl.**

# Flutter plugin implementations reached via registration/reflection
# (camera, pdfx, printing, share_plus, permission_handler, sqlite3/drift).
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.plugins.**
```

- [ ] **Step 2: Enable R8 in the release build type**

In `apps/mobile/android/app/build.gradle.kts`, replace the current `release { ... }` block body:

```kotlin
        buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
            // Disable R8/minification: ...   (old comment)
            isMinifyEnabled = false
            isShrinkResources = false
        }
```

with:

```kotlin
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
            // R8 shrinks the Java/Kotlin dex + resources. Keep rules for ML Kit
            // (optional CJK/Devanagari recognizers are referenced but not
            // bundled), Flutter plugins, and opencv_dart JNI live in
            // proguard-rules.pro. Gated on an on-device OCR/export smoke.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
```

- [ ] **Step 3: Build the R8 release artifacts**

Run: `bash scripts/build-release.sh`
Expected: ends with `S1 RELEASE BUILD COMPLETE` (R8 ran without a `Missing class` / `R8: ...` build failure). If the build FAILS on a missing class, add the reported package to `proguard-rules.pro` as `-dontwarn <package>.**` and re-run. If it cannot be made to build after keep-rule additions, go to Step 7 (revert).

- [ ] **Step 4: Record the R8 size delta**

Run:
```bash
ls -lh apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | awk '{print $5}'
```
Expected: arm64 split ≤ 72.5 MB (the pre-R8 baseline); note the exact figure in the task report. R8 output varies — no fixed target is asserted, only "not larger than baseline".

- [ ] **Step 5: On-device install + launch proof (startup class-load gate)**

With `RZCY51D0T1K` connected:
```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
D=RZCY51D0T1K
"$ADB" -s "$D" install -r apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
"$ADB" -s "$D" shell monkey -p com.camscannerlight.mobile -c android.intent.category.LAUNCHER 1
sleep 8
"$ADB" -s "$D" shell dumpsys activity activities | grep -i ResumedActivity | grep -c camscannerlight
```
Expected: the final count is `1` (the obfuscated/R8 release app is the resumed activity — proves it did not crash on startup from a stripped/renamed class).

- [ ] **Step 6: On-device OCR + export smoke (deep-path gate)**

Release builds have no Dart VM service, so the OCR path cannot be auto-asserted against the release APK (known limitation — see VERIFICATION.md style). Perform a manual smoke on `RZCY51D0T1K` using the installed R8 release APK: scan a text page → confirm edge detection → run OCR (recognize text) → export PDF → share as image. Capture a screenshot of the recognized-text screen showing correct text and of the share sheet. Record PASS + attach the two screenshots in the task report.
Expected: OCR returns correct Latin text and export/share both work on the R8 build. If OCR throws / returns empty (ML Kit class stripped) and keep-rule additions don't fix it, go to Step 7 (revert).

- [ ] **Step 7 (only if Steps 3/5/6 cannot pass): Revert R8**

Restore the original release block in `build.gradle.kts` (`isMinifyEnabled = false`, `isShrinkResources = false`, no `proguardFiles`) and delete `proguard-rules.pro`. Record in the task report exactly which step failed and the R8 error. Then re-run `bash scripts/build-release.sh` and re-confirm Task 1's artifacts. Skip Step 8's "enabled" commit message; commit the revert instead:
```bash
git add apps/mobile/android/app/build.gradle.kts
git rm apps/mobile/android/app/proguard-rules.pro
git commit -m "build(s1): revert R8 (documented) — <failing step + reason>; per-ABI split win retained"
```

- [ ] **Step 8: Commit (R8 enabled path)**

```bash
git add apps/mobile/android/app/proguard-rules.pro apps/mobile/android/app/build.gradle.kts
git commit -m "build(s1): enable R8 minify + resource shrink with ML Kit/plugin keep rules"
```

---

### Task 3: Verify script `scripts/verify/s1.sh` + plans index row

The step's binding gate. Encodes S1's acceptance criteria as asserts on `scripts/verify/lib.sh`; ends in `verify_summary`. The final task of every plan.

**Files:**
- Create: `scripts/verify/s1.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md` (add the S1 row)

**Interfaces:**
- Consumes: `scripts/build-release.sh` (Task 1); the R8 state of `apps/mobile/android/app/build.gradle.kts` (Task 2).
- Produces: `scripts/verify/s1.sh`, executable, exits 0 only when every S1 criterion holds.

- [ ] **Step 1: Write the verify script**

Create `scripts/verify/s1.sh`:

```bash
#!/usr/bin/env bash
# Verify S1 (reduce Android app size) acceptance criteria.
# Run from repository root: bash scripts/verify/s1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device install/launch check.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== S1 verification =="

require_tool flutter
require_tool unzip

APK_DIR="apps/mobile/build/app/outputs/flutter-apk"
AAB="apps/mobile/build/app/outputs/bundle/release/app-release.aab"
SYMBOLS="apps/mobile/build/symbols"

# 1) Build all release artifacts from a clean invocation (SILENCE=FAILURE).
assert_cmd "release build script completes" "S1 RELEASE BUILD COMPLETE" \
  bash "$ROOT/scripts/build-release.sh"

# 2) Three split APKs exist, each single-ABI, each under its size ceiling.
#    Ceilings are set well below the 187 MB universal and above observed
#    57-83 MB so drift is caught without being brittle.
check_split() { # <abi> <ceiling_bytes>
  local abi="$1" ceil="$2" f="$APK_DIR/app-$abi-release.apk"
  if [ ! -f "$f" ]; then fail "split APK missing: $abi"; return; fi
  local abis bytes
  abis="$(unzip -l "$f" 2>/dev/null | grep -oE 'lib/[^/]+/' | sort -u | tr -d ' ' | tr '\n' ',')"
  bytes="$(wc -c < "$f" | tr -d ' ')"
  if [ "$abis" != "lib/$abi/," ]; then fail "$abi split not single-ABI (got [$abis])"; return; fi
  if [ "$bytes" -lt "$ceil" ]; then
    pass "$abi split single-ABI and $((bytes/1024/1024))MB < $((ceil/1024/1024))MB ceiling"
  else
    fail "$abi split $((bytes/1024/1024))MB EXCEEDS $((ceil/1024/1024))MB ceiling"
  fi
}
check_split arm64-v8a   $((100*1024*1024))
check_split armeabi-v7a $((120*1024*1024))
check_split x86_64      $((120*1024*1024))

# 3) App Bundle exists (Play per-device delivery path builds).
if [ -s "$AAB" ]; then pass "release App Bundle present"; else fail "release .aab missing/empty"; fi

# 4) Obfuscation ran: symbol maps produced.
if [ -d "$SYMBOLS" ] && [ -n "$(ls -A "$SYMBOLS" 2>/dev/null)" ]; then
  pass "obfuscation symbol maps present (build/symbols non-empty)"
else
  fail "build/symbols missing/empty — obfuscation did not run"
fi

# 5) R8 state is internally consistent (no half-applied state).
GRADLE="apps/mobile/android/app/build.gradle.kts"
PRO="apps/mobile/android/app/proguard-rules.pro"
if grep -qE "isMinifyEnabled\s*=\s*true" "$GRADLE"; then
  # R8 enabled -> proguard rules must exist and be referenced.
  if [ -s "$PRO" ] && grep -q "proguard-rules.pro" "$GRADLE" && grep -qE "isShrinkResources\s*=\s*true" "$GRADLE"; then
    pass "R8 enabled and fully wired (minify+shrink+proguard-rules.pro)"
  else
    fail "R8 half-applied: isMinifyEnabled=true but shrink/proguard wiring incomplete"
  fi
else
  # R8 reverted -> proguard rules must be gone and shrink off (clean revert).
  if [ ! -e "$PRO" ] && grep -qE "isShrinkResources\s*=\s*false" "$GRADLE"; then
    pass "R8 cleanly reverted (minify off, no proguard-rules.pro) — split win retained"
  else
    fail "R8 half-reverted: isMinifyEnabled=false but shrink/proguard remnants remain"
  fi
fi

# 6) No app behavior change: analyze stays clean.
assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

# 7) On-device: the arm64 release APK installs and launches (startup proof).
if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device install/launch skipped (must pass on RZCY51D0T1K before gate)"
else
  D="${S1_DEVICE:-RZCY51D0T1K}"
  "$ADB" -s "$D" install -r "$APK_DIR/app-arm64-v8a-release.apk" >"$EVIDENCE_DIR/s1-install.log" 2>&1
  "$ADB" -s "$D" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 8
  RES="$("$ADB" -s "$D" shell dumpsys activity activities 2>/dev/null | grep -i ResumedActivity | grep -ci camscannerlight)"
  "$ADB" -s "$D" exec-out screencap -p >"$EVIDENCE_DIR/s1-release-launch.png" 2>/dev/null
  if [ "$RES" -ge 1 ] 2>/dev/null; then
    pass "arm64 R8/obfuscated release APK installs + launches on $D (resumed activity; screenshot s1-release-launch.png)"
  else
    fail "release APK did not become resumed activity on $D [silence=fail] (see $EVIDENCE_DIR/s1-install.log)"
  fi
fi

echo "== S1 verification complete =="
verify_summary
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/verify/s1.sh`

- [ ] **Step 3: Run the verify script (skipping device first for a fast structural pass)**

Run: `VERIFY_SKIP_DEVICE=1 bash scripts/verify/s1.sh`
Expected: `GATE: PASS` with the split/AAB/symbols/R8-consistency/analyze checks green and a WARN that device was skipped.

- [ ] **Step 4: Run the full verify script on-device**

Run: `bash scripts/verify/s1.sh` (with `RZCY51D0T1K` connected)
Expected: `GATE: PASS` including the install/launch check; evidence PNG at `.superpowers/verify/s1-release-launch.png`.

- [ ] **Step 5: Add the S1 row to the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add an S1 row to the ordered plan list matching the existing row format, linking `2026-07-02-s1-reduce-app-size.md`, noting: "Reduce Android app size — per-ABI split + AAB + symbol strip (187 MB → ~72 MB arm64); R8 <enabled|reverted per gate>; ffmpeg removal deferred (libdartcv hard-links it)." Fill `<enabled|reverted>` from Task 2's outcome.

- [ ] **Step 6: Commit**

```bash
git add scripts/verify/s1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(s1): verify script (split/AAB/symbols/R8 gate) + plans index row"
```

---

## Self-Review (author checklist — completed)

**Spec coverage:**
- Per-ABI split APKs + AAB, all three ABIs → Task 1 (`build-release.sh`). ✓
- `--split-debug-info` + `--obfuscate` symbol stripping → Task 1 Steps 1/3; verified in Task 3 check 4. ✓
- R8 minify + resource shrink with keep rules, on-device gated, auto-revert, no half-applied state → Task 2 (all steps + revert path); consistency asserted in Task 3 check 5. ✓
- ffmpeg deferred (not implemented) → Global Constraints + no task. ✓
- `scripts/verify/s1.sh` under independent verifier + plans index row → Task 3. ✓
- `flutter analyze` clean / no behavior change → Task 3 check 6; no `lib/` edits anywhere. ✓
- Size thresholds (drift guard, looser than observed) → Task 3 check 2, rationale inline. ✓

**Placeholder scan:** No TBD/TODO-as-work; the only `TODO` text is the pre-existing signing-config comment carried verbatim in the gradle block (not a plan placeholder). Every code/command step shows exact content. ✓

**Type/name consistency:** `S1 RELEASE BUILD COMPLETE` marker, artifact paths, `com.camscannerlight.mobile` app id, `RZCY51D0T1K` device, `isMinifyEnabled/isShrinkResources/proguard-rules.pro` names identical across Tasks 1–3. ✓
