#!/usr/bin/env bash
# Shared verification helpers — see docs/superpowers/VERIFICATION.md
#
# Principle: SILENCE IS FAILURE. A check passes only on an explicit positive
# match (exit code 0 AND the expected marker present). Missing tool, missing
# marker, empty output, or non-zero exit => FAIL. No silent skips.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/.superpowers/verify}"
mkdir -p "$EVIDENCE_DIR"

VERIFY_PASS=0
VERIFY_FAIL=0

_grn() { printf '\033[32m%s\033[0m\n' "$*"; }
_red() { printf '\033[31m%s\033[0m\n' "$*"; }

pass() { VERIFY_PASS=$((VERIFY_PASS + 1)); _grn "PASS: $*"; }
fail() { VERIFY_FAIL=$((VERIFY_FAIL + 1)); _red "FAIL: $*"; }

# require_tool <cmd> : a missing tool is a FAIL, never a skip (rule 4)
require_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "tool present: $1"
    return 0
  fi
  fail "required tool MISSING: $1"
  return 1
}

_slug() { printf '%s' "$1" | tr ' /:' '___'; }

# assert_cmd "<desc>" "<expected-marker>" <command...>
# Runs the command, captures output+exit, asserts exit 0 AND marker present.
assert_cmd() {
  local desc="$1" marker="$2"; shift 2
  local log="$EVIDENCE_DIR/$(_slug "$desc").log" out rc
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" >"$log"
  if [ "$rc" -ne 0 ]; then
    fail "$desc — exit $rc (see $log)"
    return 1
  fi
  if printf '%s' "$out" | grep -qF -- "$marker"; then
    pass "$desc — matched: $marker"
    return 0
  fi
  fail "$desc — marker NOT found: '$marker' [silence=fail] (see $log)"
  return 1
}

# assert_coverage_floor <min_percent> : flutter test --coverage, gate on line %.
assert_coverage_floor() {
  local floor="$1" log="$EVIDENCE_DIR/coverage.log" lcov="$ROOT/apps/mobile/coverage/lcov.info"
  ( cd "$ROOT/apps/mobile" && flutter test --coverage >"$log" 2>&1 ); local rc=$?
  if [ "$rc" -ne 0 ]; then fail "coverage: flutter test --coverage exit $rc (see $log)"; return 1; fi
  if [ ! -s "$lcov" ]; then fail "coverage: lcov.info missing/empty [silence=fail]"; return 1; fi
  local pct; pct="$(awk -F: '/^LF:/{f+=$2} /^LH:/{h+=$2} END{if(f>0) printf "%.1f", 100*h/f; else print "0"}' "$lcov")"
  if awk "BEGIN{exit !($pct >= $floor)}"; then
    pass "coverage: ${pct}% line coverage ≥ floor ${floor}%"; return 0
  fi
  fail "coverage: ${pct}% line coverage BELOW floor ${floor}% (see $log)"; return 1
}

# assert_true "<desc>" <command...> : passes iff command exits 0
assert_true() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; return 0; fi
  fail "$desc — command exited non-zero"
  return 1
}

# assert_file_has "<desc>" "<file>" "<marker>"
assert_file_has() {
  local desc="$1" file="$2" marker="$3"
  if [ -s "$file" ] && grep -qF -- "$marker" "$file"; then
    pass "$desc"; return 0
  fi
  fail "$desc — marker '$marker' not in $file [silence=fail]"
  return 1
}

# verify_summary : prints totals and exits non-zero if any check failed
verify_summary() {
  echo "------------------------------------------------"
  echo "VERIFY SUMMARY: ${VERIFY_PASS} passed, ${VERIFY_FAIL} failed"
  echo "Evidence: $EVIDENCE_DIR"
  if [ "$VERIFY_FAIL" -ne 0 ]; then _red "GATE: FAIL"; exit 1; fi
  _grn "GATE: PASS"; exit 0
}

# ---- Device-launch helpers (app-generic; reused by every step that checks runtime) ----
APP_ID="${APP_ID:-com.camscannerlight.mobile}"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"

_kill_run() { local pid="$1"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; pkill -f "mobile:run" 2>/dev/null; pkill -f "flutter run" 2>/dev/null; }

# Hard build/launch failures that mean the run can never succeed (fail fast).
_FAIL_RE='FAILURE:|Gradle task .* failed|Could not build|No supported devices|command not found|xcodebuild: error|Unable to find'

# Device-state probes (the PRIMARY launch signal — robust to `flutter run` /
# DDS exiting after a successful launch). Negative controls make a positive
# device state proof that THIS run launched the app.
_android_resumed() { "$ADB" -s "$1" shell dumpsys activity activities 2>/dev/null | grep -i ResumedActivity | grep -ci camscannerlight; }

verify_android_run() {
  local dev log="$EVIDENCE_DIR/android-nx-run.log"
  dev="$("$ADB" devices | awk '/emulator-.*device$/{print $1; exit}')"
  if [ -z "$dev" ]; then
    flutter emulators --launch Medium_Phone_API_35 >/dev/null 2>&1
    "$ADB" wait-for-device
    local b=0; until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; b=$((b+3)); [ "$b" -gt 180 ] && break; done
    dev="$("$ADB" devices | awk '/emulator-.*device$/{print $1; exit}')"
  fi
  [ -z "$dev" ] && { fail "android: no emulator available"; return 1; }
  # Negative control (rule 5): force-stop, confirm NOT resumed.
  "$ADB" -s "$dev" shell am force-stop "$APP_ID" 2>/dev/null; sleep 1
  if [ "$(_android_resumed "$dev")" != "0" ]; then
    fail "android: negative control failed (app still resumed pre-launch)"; return 1
  fi
  ( pnpm nx run mobile:run -- -d "$dev" >"$log" 2>&1 ) & local pid=$!
  # PRIMARY signal: poll device state until the app is the resumed activity.
  local launched=0 t=0
  while [ "$t" -lt 300 ]; do
    [ "$(_android_resumed "$dev")" -ge 1 ] 2>/dev/null && { launched=1; break; }
    grep -qE "$_FAIL_RE" "$log" 2>/dev/null && break
    sleep 5; t=$((t + 5))
  done
  if [ "$launched" -eq 1 ]; then
    # The gate PASSES on the resumed-activity signal above. The screenshot is
    # CORROBORATING evidence only — give Flutter time to paint past the native
    # splash. NOTE: `gfxinfo "Total frames rendered"` does NOT track
    # Flutter/Impeller, so a frame-count poll is useless here; a fixed settle is
    # the honest option. The AUTHORITATIVE on-device UI proof is the widget test
    # now and an integration_test later (see VERIFICATION.md known-limitation 3).
    sleep 12
    "$ADB" -s "$dev" exec-out screencap -p >"$EVIDENCE_DIR/android-nx-run.png" 2>/dev/null
    pass "android: \`nx run mobile:run\` launched app (RESUMED after force-stop negative control; screenshot android-nx-run.png is corroborating only)"
  else
    fail "android: app never became the resumed activity [silence=fail] (see $log)"
  fi
  _kill_run "$pid"
}

verify_ios_run() {
  local udid log="$EVIDENCE_DIR/ios-nx-run.log"
  udid="$(xcrun simctl list devices booted | grep -oE '[0-9A-Fa-f-]{36}' | head -1)"
  if [ -z "$udid" ]; then
    udid="$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -oE '[0-9A-Fa-f-]{36}')"
    [ -n "$udid" ] && { xcrun simctl boot "$udid" 2>/dev/null; open -a Simulator; }
    local b=0; while [ -n "$udid" ] && ! xcrun simctl list devices | grep "$udid" | grep -q Booted; do sleep 2; b=$((b+2)); [ "$b" -gt 120 ] && break; done
  fi
  [ -z "$udid" ] && { fail "ios: no simulator available"; return 1; }
  # Negative control (rule 5): terminate any running instance; the per-run log is
  # truncated below (`>"$log"`), so its launch marker proves THIS invocation.
  xcrun simctl terminate "$udid" "$APP_ID" 2>/dev/null; sleep 1
  ( pnpm nx run mobile:run -- -d "$udid" >"$log" 2>&1 ) & local pid=$!
  # PRIMARY signal for iOS: the fresh-log "Dart VM Service is available" marker
  # (reliable on the simulator; launchctl polling is flaky/false-negative while
  # `flutter run` holds the device).
  local launched=0 t=0
  while [ "$t" -lt 360 ]; do
    grep -qE "A Dart VM Service on .* is available|Flutter run key commands" "$log" 2>/dev/null && { launched=1; break; }
    grep -qE "$_FAIL_RE" "$log" 2>/dev/null && break
    kill -0 "$pid" 2>/dev/null || { grep -qE "A Dart VM Service on .* is available" "$log" 2>/dev/null && launched=1; break; }
    sleep 5; t=$((t + 5))
  done
  if [ "$launched" -eq 1 ]; then
    sleep 6  # let Flutter paint its first frame (past the native splash) before capturing evidence
    xcrun simctl io "$udid" screenshot "$EVIDENCE_DIR/ios-nx-run.png" 2>/dev/null
    pass "ios: \`nx run mobile:run\` launched app (Dart VM Service up after terminate negative control; screenshot ios-nx-run.png)"
  else
    fail "ios: app never reached launch (no Dart VM Service) [silence=fail] (see $log)"
  fi
  _kill_run "$pid"
}

# ---- On-device integration tests: the AUTHORITATIVE programmatic UI check ----
# `flutter test integration_test/...` builds, installs and launches the REAL app
# on the device, then asserts the rendered widget tree — a wrong/blank/splash UI
# FAILS. It runs to completion (not resident), so "All tests passed!" is a clean
# pass/fail signal (no DDS/launchctl gymnastics). This supersedes the screenshot
# as UI evidence for feature steps.

_ensure_android() {
  local dev; dev="$("$ADB" devices | awk '/emulator-.*device$/{print $1; exit}')"
  if [ -z "$dev" ]; then
    flutter emulators --launch Medium_Phone_API_35 >/dev/null 2>&1
    "$ADB" wait-for-device
    local b=0; until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; b=$((b+3)); [ "$b" -gt 180 ] && break; done
    dev="$("$ADB" devices | awk '/emulator-.*device$/{print $1; exit}')"
  fi
  printf '%s' "$dev"
}

_ensure_ios() {
  local udid; udid="$(xcrun simctl list devices booted | grep -oE '[0-9A-Fa-f-]{36}' | head -1)"
  if [ -z "$udid" ]; then
    udid="$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -oE '[0-9A-Fa-f-]{36}')"
    [ -n "$udid" ] && { xcrun simctl boot "$udid" 2>/dev/null; open -a Simulator; }
    local b=0; while [ -n "$udid" ] && ! xcrun simctl list devices | grep "$udid" | grep -q Booted; do sleep 2; b=$((b+2)); [ "$b" -gt 120 ] && break; done
  fi
  printf '%s' "$udid"
}

# A failure is "infra-only" (the test never actually ran its assertions) when the
# log shows a build/load/connection problem but NO real test-assertion failure.
# Real assertion failures throw a `TestFailure` / framework exception; infra
# failures do not — so this is the reliable discriminator, NOT the `[E]` marker
# (transient infra errors like "device offline" ALSO print `[E]`; see
# VERIFICATION.md known-limitation 4). We retry infra-only failures, never real
# assertion failures.
_is_infra_only_failure() {
  local log="$1"
  grep -qE "Failed to start Dart Development Service|device offline|Lost connection to device|Failed to load|Gradle task .* failed|registerService: Service connection disposed|Connection refused" "$log" \
    && ! grep -qE "TestFailure|EXCEPTION CAUGHT BY FLUTTER TEST" "$log"
}

# Force a clean emulator reboot and wait until fully booted + settled, so the
# camera HAL is fresh. Used before the real-camera test (the most load-sensitive
# check) and as the fallback when an emulator is wedged offline.
_android_cold_boot() {
  local dev="${1:-emulator-5554}"
  "$ADB" -s "$dev" emu kill >/dev/null 2>&1; sleep 3
  pkill -f qemu-system >/dev/null 2>&1; sleep 2
  "$ADB" kill-server >/dev/null 2>&1; "$ADB" start-server >/dev/null 2>&1
  flutter emulators --launch Medium_Phone_API_35 >/dev/null 2>&1
  "$ADB" wait-for-device >/dev/null 2>&1
  local b=0; until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; b=$((b + 3)); [ "$b" -gt 240 ] && break; done
  sleep 8  # let camera/HAL + system services come up before first use
}

# Best-effort recovery of an offline Android emulator: reconnect, else cold-boot.
_android_recover() {
  local dev="$1" w=0
  "$ADB" reconnect offline >/dev/null 2>&1; sleep 3
  while [ "$w" -lt 30 ] && ! "$ADB" devices | grep -qE "^${dev}[[:space:]]+device$"; do sleep 3; w=$((w + 3)); done
  "$ADB" devices | grep -qE "^${dev}[[:space:]]+device$" || _android_cold_boot "$dev"
}

# verify_integration <label> <device-id> <test-file-under-integration_test/>
verify_integration() {
  local label="$1" dev="$2" tf="$3"
  # Per-(platform,test) log so multiple integration tests on the same platform
  # don't overwrite each other's evidence (rule 8: store evidence).
  local log="$EVIDENCE_DIR/integration-$label-$(_slug "$tf").log"
  local attempt=0 max=3
  while [ "$attempt" -lt "$max" ]; do
    attempt=$((attempt + 1))
    ( cd "$ROOT/apps/mobile" && flutter test "integration_test/$tf" -d "$dev" >"$log" 2>&1 )
    if grep -qF "All tests passed!" "$log"; then
      pass "$label: on-device integration test asserts UI ($tf)"
      return 0
    fi
    # Retry transient infra failures (test never ran) — recovering an offline
    # Android emulator first. NEVER retry a real assertion failure.
    if [ "$attempt" -lt "$max" ] && _is_infra_only_failure "$log"; then
      case "$label" in
        android*) grep -q "device offline" "$log" && _android_recover "$dev" ;;
      esac
      sleep 8; continue
    fi
    break
  done
  fail "$label: on-device integration test FAILED ($tf) [silence=fail] (see $log)"
}

verify_integration_android() {
  local tf="$1" dev; dev="$(_ensure_android)"
  [ -z "$dev" ] && { fail "android: no emulator for integration test"; return 1; }
  verify_integration android "$dev" "$tf"
}

# Exercises the REAL camera/permission path. Cold-boots a FRESH emulator first
# (option 1) so cumulative gate load can't starve the camera HAL, then installs
# the app and grants CAMERA. NOTE on the grant: `flutter test` does an *update*
# install of the same-signed APK, which PRESERVES already-granted runtime
# permissions — so granting after `flutter install` (before the test) survives
# into the test run.
verify_integration_android_real() {
  local tf="$1" dev
  dev="$(_ensure_android)"; [ -z "$dev" ] && { fail "android(real): no emulator"; return 1; }
  _android_cold_boot "$dev"
  dev="$(_ensure_android)"; [ -z "$dev" ] && { fail "android(real): no emulator after cold boot"; return 1; }
  ( cd "$ROOT/apps/mobile" && flutter install -d "$dev" >/dev/null 2>&1 )
  "$ADB" -s "$dev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null
  verify_integration "android-real" "$dev" "$tf"
}

verify_integration_ios() {
  local tf="$1" udid; udid="$(_ensure_ios)"
  [ -z "$udid" ] && { fail "ios: no simulator for integration test"; return 1; }
  verify_integration ios "$udid" "$tf"
}
