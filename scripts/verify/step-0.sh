#!/usr/bin/env bash
# Verify Step 0 (monorepo foundation) acceptance criteria.
# Run from anywhere: bash scripts/verify/step-0.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip the (slow) device launches — but skipping
# is itself reported, never silent. Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

APP_ID="com.camscannerlight.mobile"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"

echo "== Step 0 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Static criteria ----
# Clean tree (check before anything that could dirty tracked files)
if [ -z "$(git status --porcelain)" ]; then
  pass "git working tree clean"
else
  fail "git working tree NOT clean"
fi

# analyze + test, cache disabled so a cached result can't mask a real run (rule 6)
assert_cmd "nx analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache
assert_cmd "nx test passes" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

# nx-flutter patch applied (proves the Node 24 fix survives install)
if grep -rqlF "existsSync" node_modules/@nxrocks/nx-flutter/src 2>/dev/null; then
  pass "nx-flutter patch applied (shim present in installed plugin)"
else
  fail "nx-flutter patch NOT applied (shim missing) [silence=fail]"
fi
# nx loads the patched plugin (would throw ERR_PACKAGE_PATH_NOT_EXPORTED otherwise)
assert_cmd "nx loads project (plugin OK)" '"name":"mobile"' \
  pnpm nx show project mobile

# ---- Device criteria: literal `nx run mobile:run` on each platform ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

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

verify_android_run
verify_ios_run

verify_summary
