#!/usr/bin/env bash
# Verify A3 (capture photo → review screen) acceptance criteria.
# Run from anywhere: bash scripts/verify/a3.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip device launches — skipping is reported as
# a FAIL, never silent. Opt-in REAL_DEVICE=1 adds a real-camera smoke lane.
# Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== A3 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "CapturedImage value type exists" \
  "apps/mobile/lib/features/scan/captured_image.dart" "class CapturedImage"
assert_file_has "preview seam exposes capture()" \
  "apps/mobile/lib/features/scan/camera_preview_controller.dart" "Future<CapturedImage> capture()"
assert_file_has "ScanController exposes capture()" \
  "apps/mobile/lib/features/scan/scan_controller.dart" "Future<CapturedImage?> capture()"
assert_file_has "review screen exists" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" "class CaptureReviewScreen"
assert_file_has "shutter button key present" \
  "apps/mobile/lib/features/scan/widgets/camera_preview_view.dart" "scan-shutter"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "a3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration tests) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

# BDD-generated integration test (from integration_test/a3_capture_review.feature
# via bdd_widget_test + build_runner; the generated *_test.dart is committed).
# Injects fakes → deterministic; the real camera native code is compiled+linked
# into the device build. Real *runtime* capture is the opt-in REAL_DEVICE lane
# below + manual on iOS (see VERIFICATION.md #5).
verify_integration_android a3_capture_review_test.dart
verify_integration_ios a3_capture_review_test.dart

# ---- Opt-in real-device smoke lane (REAL_DEVICE=1) ----
# Proves the REAL camera plugin produces a REAL non-empty JPEG on hardware.
# Android: install debuggable + pre-grant CAMERA (bypasses the dialog), tap the
# shutter, then read the app's private storage via run-as and assert a non-empty
# JPEG was written. iOS real camera = MANUAL "Allow once" (no simulator camera).
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device/emulator connected"
  else
    # NOTE: all waits are DEVICE-SIDE (`adb shell sleep`) — host `sleep` is
    # blocked in some sandboxed CI/agent environments and would stall the lane.
    # Verified by hand on a physical SM-A166B: this exact sequence opens the real
    # camera (logcat "First frame ... 1280x720"), captures a real ~175 KB JPEG to
    # the app's private cache, and renders the review screen.
    apk="apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    if ! ( cd apps/mobile && flutter build apk --debug ) >/dev/null 2>&1; then
      fail "REAL_DEVICE: debug APK build failed — skipping the rest of the lane"
    elif ! "$ADB" -s "$rdev" install -r -g "$apk" >/dev/null 2>&1; then
      fail "REAL_DEVICE: adb install -g failed — skipping the rest of the lane"
    else
      pass "REAL_DEVICE: installed with CAMERA pre-granted"
      "$ADB" -s "$rdev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null
      # Ensure the screen is awake, unlocked, and stays on (a dozing/locked
      # device silently swallows the taps below and the lane false-FAILs).
      "$ADB" -s "$rdev" shell svc power stayon true 2>/dev/null
      "$ADB" -s "$rdev" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
      "$ADB" -s "$rdev" shell wm dismiss-keyguard 2>/dev/null
      # Clear any stale captures so the assertion proves THIS run (negative control).
      "$ADB" -s "$rdev" shell "run-as $APP_ID find . -iname '*.jpg' -delete" 2>/dev/null
      "$ADB" -s "$rdev" shell am force-stop "$APP_ID" 2>/dev/null
      "$ADB" -s "$rdev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 7
      size="$("$ADB" -s "$rdev" shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
      w="${size%x*}"; h="${size#*x}"
      # Open Scan (extended FAB ~83% width, ~88.8% height — measured on SM-A166B,
      # 1080x2340; the old ~93.5% height tapped below the FAB and missed), then
      # the shutter (bottom-center ~50% width, ~86% height — see CameraPreviewView).
      "$ADB" -s "$rdev" shell input tap "$(( w * 83 / 100 ))" "$(( h * 888 / 1000 ))" >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 6   # camera init + warm-up
      "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/real-device-camera.png" 2>/dev/null
      "$ADB" -s "$rdev" shell input tap "$(( w * 50 / 100 ))" "$(( h * 86 / 100 ))" >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 4   # takePicture + write + nav to review
      found="$("$ADB" -s "$rdev" shell "run-as $APP_ID find . -iname '*.jpg' -size +0c" 2>/dev/null | tr -d '\r')"
      if [ -n "$found" ]; then
        pass "REAL_DEVICE: real camera produced a non-empty JPEG ($found)"
      else
        fail "REAL_DEVICE: no non-empty JPEG produced by the real camera [silence=fail]"
      fi
      shot="$EVIDENCE_DIR/real-device-review.png"
      "$ADB" -s "$rdev" exec-out screencap -p > "$shot" 2>/dev/null
      echo "REAL_DEVICE: screenshots → $EVIDENCE_DIR/real-device-camera.png , $shot"
      "$ADB" -s "$rdev" shell svc power stayon false 2>/dev/null
    fi
  fi
  echo "REAL_DEVICE (iOS): MANUAL — run the app on a physical iPhone, tap Scan →"
  echo "  Allow → shutter, and confirm the review screen shows the captured photo."
fi

verify_summary
