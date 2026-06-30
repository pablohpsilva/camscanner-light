#!/usr/bin/env bash
# scripts/verify/f2.sh — F2 pre-fill crop corners gate
set -euo pipefail
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
MOBILE="$REPO_ROOT/apps/mobile"

_pass() { echo "PASS: $1"; }
_fail() { echo "FAIL: $1" >&2; exit 1; }

echo "=== F2 static asserts ==="

grep -q "EdgeDetectorFactory" \
  "$MOBILE/lib/features/scan/scan_dependencies.dart" \
  && _pass "ScanDependencies declares EdgeDetectorFactory" \
  || _fail "ScanDependencies must declare EdgeDetectorFactory"

grep -q "createEdgeDetector" \
  "$MOBILE/lib/features/scan/scan_dependencies.dart" \
  && _pass "ScanDependencies has createEdgeDetector" \
  || _fail "ScanDependencies missing createEdgeDetector"

grep -q "EdgeDetector? edgeDetector" \
  "$MOBILE/lib/features/scan/capture_review_screen.dart" \
  && _pass "CaptureReviewScreen has edgeDetector param" \
  || _fail "CaptureReviewScreen missing edgeDetector param"

grep -q "_userInteracted" \
  "$MOBILE/lib/features/scan/capture_review_screen.dart" \
  && _pass "_userInteracted guard present" \
  || _fail "_userInteracted guard missing in capture_review_screen.dart"

grep -q "Colors.green" \
  "$MOBILE/lib/features/scan/capture_review_screen.dart" \
  && _pass "Green cue referenced in CaptureReviewScreen" \
  || _fail "Colors.green missing in capture_review_screen.dart"

grep -q "Color highlightColor" \
  "$MOBILE/lib/features/scan/widgets/crop_overlay.dart" \
  && _pass "CropOverlay has highlightColor param" \
  || _fail "CropOverlay missing highlightColor param"

# DIP: capture_review_screen must NOT import opencv_dart
if grep -q "opencv_dart" \
    "$MOBILE/lib/features/scan/capture_review_screen.dart"; then
  _fail "DIP violation: opencv_dart imported in capture_review_screen.dart"
else
  _pass "DIP: opencv_dart not in capture_review_screen.dart"
fi

test -f "$MOBILE/integration_test/f2_auto_corners.feature" \
  && _pass "BDD feature file exists" \
  || _fail "F2 BDD feature file missing"

test -f "$MOBILE/integration_test/f2_auto_corners_test.dart" \
  && _pass "BDD test file exists" \
  || _fail "F2 BDD test file missing"

echo "=== OpenCV host library ==="
bash "$REPO_ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

echo "=== flutter analyze ==="
(cd "$MOBILE" && flutter analyze) \
  && _pass "flutter analyze clean" \
  || _fail "flutter analyze reported issues"

echo "=== host test suite ==="
(cd "$MOBILE" && flutter test) \
  && _pass "host suite green" \
  || _fail "flutter test failed"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  echo "SKIP: VERIFY_SKIP_DEVICE=1 — skipping on-device BDD"
else
  echo "=== on-device BDD ==="
  (cd "$MOBILE" && flutter test integration_test/f2_auto_corners_test.dart) \
    && _pass "BDD integration tests green" \
    || _fail "F2 BDD integration tests failed"
fi

echo "=== F2 VERIFY COMPLETE ==="
