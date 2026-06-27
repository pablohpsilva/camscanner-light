#!/usr/bin/env bash
# Verify A2 (camera preview + permission) acceptance criteria.
# Run from anywhere: bash scripts/verify/a2.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip device launches — skipping is reported as
# a FAIL, never silent. Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== A2 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Native + dependency config (static asserts) ----
assert_file_has "android manifest declares CAMERA permission" \
  "apps/mobile/android/app/src/main/AndroidManifest.xml" "android.permission.CAMERA"
assert_file_has "ios Info.plist declares NSCameraUsageDescription" \
  "apps/mobile/ios/Runner/Info.plist" "NSCameraUsageDescription"
assert_file_has "pubspec depends on camera plugin" \
  "apps/mobile/pubspec.yaml" "camera:"
assert_file_has "pubspec depends on permission_handler" \
  "apps/mobile/pubspec.yaml" "permission_handler:"

# ---- Static criteria: unit + widget tests, analyze ----
# Covers ScanController state machine, ScanDependencies wiring, CameraScreen
# states, and Scan→camera navigation.
assert_cmd "a2 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (integration tests) ----
# Authoritative: pump the REAL app on each device and assert the camera screen's
# widget tree for the denied and granted/preview states. The real camera +
# permission_handler native code is compiled/linked into these device builds.
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

# BDD-generated integration tests (from integration_test/a2_scan_permission.feature
# via bdd_widget_test + build_runner). The .feature file is the authored BDD
# source; a2_scan_permission_test.dart is committed (generated files are
# idempotent — regenerate with
# `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`).
# Covers the three scenarios (denied / granted / unavailable) on BOTH platforms.
#
# NOTE on real-plugin RUNTIME coverage: the BDD scenarios inject fakes so they
# assert the widget tree deterministically; the REAL camera/permission_handler
# native code is still compiled + linked into these device builds. A real
# *runtime* camera test cannot be gated here — the real permission request raises
# the OS permission dialog (GrantPermissionsActivity), which the integration_test
# driver cannot tap, so a real preview never renders under `flutter test`. That
# path is verified manually via apps/mobile/tool/manual_real_camera_check.sh
# (which installs with `-g` to bypass the dialog). See VERIFICATION.md.
verify_integration_android a2_scan_permission_test.dart
verify_integration_ios a2_scan_permission_test.dart

verify_summary
