#!/usr/bin/env bash
# Verify F3 (live camera edge overlay) acceptance criteria.
# Run: bash scripts/verify/f3.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== F3 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git

# ---- Source presence (static asserts) ----
assert_file_has "LiveQuadOverlay widget exists" \
  "apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart" "class LiveQuadOverlay"
assert_file_has "LiveQuadOverlay has test key" \
  "apps/mobile/lib/features/scan/widgets/live_quad_overlay.dart" "live-quad-overlay"
assert_file_has "CameraPreviewController declares sampleFrame" \
  "apps/mobile/lib/features/scan/camera_preview_controller.dart" "sampleFrame"
assert_file_has "CameraPreviewController declares previewSize" \
  "apps/mobile/lib/features/scan/camera_preview_controller.dart" "previewSize"
assert_file_has "PluginCameraPreviewController implements sampleFrame" \
  "apps/mobile/lib/features/scan/camera_preview_controller_impl.dart" "sampleFrame"
assert_file_has "previewSize swaps for sensor orientation" \
  "apps/mobile/lib/features/scan/camera_preview_controller_impl.dart" "sensorOrientation"
assert_file_has "CameraPreviewView has liveCorners param" \
  "apps/mobile/lib/features/scan/widgets/camera_preview_view.dart" "liveCorners"
assert_file_has "CameraPreviewView uses IgnorePointer" \
  "apps/mobile/lib/features/scan/widgets/camera_preview_view.dart" "IgnorePointer"
assert_file_has "CameraScreen has _sampleTimer" \
  "apps/mobile/lib/features/scan/camera_screen.dart" "_sampleTimer"
assert_file_has "CameraScreen has _doSample" \
  "apps/mobile/lib/features/scan/camera_screen.dart" "_doSample"
assert_file_has "CameraScreen guards _isSampling" \
  "apps/mobile/lib/features/scan/camera_screen.dart" "_isSampling"
assert_file_has "EdgeDetector interface is unchanged" \
  "apps/mobile/lib/features/scan/edge_detector.dart" "Future<DetectionResult?> detect"
assert_file_has "liveDetectionScanDependencies factory exists" \
  "apps/mobile/test/support/fake_scan.dart" "liveDetectionScanDependencies"
assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/f3_live_overlay.feature" "live edge overlay"
assert_file_has "generated test calls confident-corners step" \
  "apps/mobile/integration_test/f3_live_overlay_test.dart" "theCameraIsReadyWithADetectorReturningConfidentCorners"
assert_file_has "generated test calls timer step" \
  "apps/mobile/integration_test/f3_live_overlay_test.dart" "theLiveOverlaySampleTimerFires"
assert_file_has "generated test calls overlay-visible step" \
  "apps/mobile/integration_test/f3_live_overlay_test.dart" "theLiveQuadOverlayIsVisibleOnTheCameraPreview"

# ---- Generated code is current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (f3 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/f3_live_overlay_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- OpenCV host library (required by scan tests in the shared suite) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "f3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: BDD integration test ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android f3_live_overlay_test.dart
verify_integration_ios f3_live_overlay_test.dart

verify_summary
