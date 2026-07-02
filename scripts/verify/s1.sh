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
  local abi="$1" ceil="$2"
  local f="$APK_DIR/app-$abi-release.apk"
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
# NOTE: BSD grep (macOS) does NOT support \s — use [[:space:]] (as lib.sh does).
if grep -qE "isMinifyEnabled[[:space:]]*=[[:space:]]*true" "$GRADLE"; then
  # R8 enabled -> proguard rules must exist and be referenced.
  if [ -s "$PRO" ] && grep -q "proguard-rules.pro" "$GRADLE" && grep -qE "isShrinkResources[[:space:]]*=[[:space:]]*true" "$GRADLE"; then
    pass "R8 enabled and fully wired (minify+shrink+proguard-rules.pro)"
  else
    fail "R8 half-applied: isMinifyEnabled=true but shrink/proguard wiring incomplete"
  fi
else
  # R8 reverted -> proguard rules must be gone and shrink off (clean revert).
  if [ ! -e "$PRO" ] && grep -qE "isShrinkResources[[:space:]]*=[[:space:]]*false" "$GRADLE"; then
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
