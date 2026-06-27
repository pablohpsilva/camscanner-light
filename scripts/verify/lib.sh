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

# Wait for a launch marker (or a failure marker) in a resident-run log.
# Returns 0 if launched, 1 otherwise. Silence/timeout => 1 (fail).
_wait_launch() {
  local log="$1" pid="$2" t=0
  while [ "$t" -lt 360 ]; do
    grep -qE "Flutter run key commands|Dart VM Service is listening|Syncing files to device" "$log" 2>/dev/null && return 0
    grep -qE "FAILURE:|Gradle task .* failed|^Error:|Exception:|No supported devices|command not found|Could not build|Unable to" "$log" 2>/dev/null && return 1
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 5; t=$((t + 5))
  done
  return 1
}

_kill_run() { local pid="$1"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; pkill -f "mobile:run" 2>/dev/null; pkill -f "flutter run" 2>/dev/null; }

verify_android_run() {
  local dev log="$EVIDENCE_DIR/android-nx-run.log"
  dev="$("$ADB" devices | awk '/emulator-.*device$/{print $1; exit}')"
  if [ -z "$dev" ]; then
    flutter emulators --launch Medium_Phone_API_35 >/dev/null 2>&1
    "$ADB" wait-for-device
    local t=0; until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; t=$((t+3)); [ "$t" -gt 180 ] && break; done
    dev="$("$ADB" devices | awk '/emulator-.*device$/{print $1; exit}')"
  fi
  [ -z "$dev" ] && { fail "android: no emulator available"; return 1; }
  # Negative control (rule 5): force-stop, confirm NOT resumed.
  "$ADB" -s "$dev" shell am force-stop "$APP_ID" 2>/dev/null
  if [ "$("$ADB" -s "$dev" shell dumpsys activity activities 2>/dev/null | grep -i ResumedActivity | grep -ci camscannerlight)" != "0" ]; then
    fail "android: negative control failed (app still resumed pre-launch)"; return 1
  fi
  ( pnpm nx run mobile:run -- -d "$dev" >"$log" 2>&1 ) & local pid=$!
  if _wait_launch "$log" "$pid"; then
    sleep 4
    local resumed; resumed="$("$ADB" -s "$dev" shell dumpsys activity activities 2>/dev/null | grep -i ResumedActivity | grep -ci camscannerlight)"
    "$ADB" -s "$dev" exec-out screencap -p >"$EVIDENCE_DIR/android-nx-run.png" 2>/dev/null
    if [ "$resumed" -ge 1 ]; then
      pass "android: \`nx run mobile:run\` launched app (resumed after negative control; screenshot android-nx-run.png)"
    else
      fail "android: launch markers seen but app NOT resumed (see $log)"
    fi
  else
    fail "android: \`nx run mobile:run\` never reached a launch marker [silence=fail] (see $log)"
  fi
  _kill_run "$pid"
}

verify_ios_run() {
  local udid log="$EVIDENCE_DIR/ios-nx-run.log"
  udid="$(xcrun simctl list devices booted | grep -oE '[0-9A-Fa-f-]{36}' | head -1)"
  if [ -z "$udid" ]; then
    udid="$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -oE '[0-9A-Fa-f-]{36}')"
    [ -n "$udid" ] && { xcrun simctl boot "$udid" 2>/dev/null; open -a Simulator; }
    local t=0; while [ -n "$udid" ] && ! xcrun simctl list devices | grep "$udid" | grep -q Booted; do sleep 2; t=$((t+2)); [ "$t" -gt 120 ] && break; done
  fi
  [ -z "$udid" ] && { fail "ios: no simulator available"; return 1; }
  # Negative control (rule 5): terminate, then prove this run starts it.
  xcrun simctl terminate "$udid" "$APP_ID" 2>/dev/null
  ( pnpm nx run mobile:run -- -d "$udid" >"$log" 2>&1 ) & local pid=$!
  if _wait_launch "$log" "$pid"; then
    sleep 4
    if xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -qi camscannerlight; then
      xcrun simctl io "$udid" screenshot "$EVIDENCE_DIR/ios-nx-run.png" 2>/dev/null
      pass "ios: \`nx run mobile:run\` launched app (running after negative control; screenshot ios-nx-run.png)"
    else
      fail "ios: launch markers seen but app NOT in launchctl list (see $log)"
    fi
  else
    fail "ios: \`nx run mobile:run\` never reached a launch marker [silence=fail] (see $log)"
  fi
  _kill_run "$pid"
}
