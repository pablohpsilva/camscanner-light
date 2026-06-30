#!/usr/bin/env bash
# Verify F1 (contour detection) acceptance criteria.
# VERIFY_SKIP_DEVICE=1  — skips device launches (reported FAIL, never silent).
# REAL_DEVICE=1         — Tier-3 manual lane (capture, verify auto corner detection).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== F1 verification =="

require_tool flutter
require_tool pnpm
require_tool git

# ── Setup OpenCV library for host tests ────────────────────────────────────
# The test suite requires DARTCV_LIB_PATH and DYLD_LIBRARY_PATH for
# opencv_dart to run on the macOS host. Source setup script to download if needed.
bash scripts/setup-cv-host-test.sh
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ── EdgeDetector interface ─────────────────────────────────────────────────
assert_file_has "EdgeDetector interface exists" \
  "apps/mobile/lib/features/scan/edge_detector.dart" \
  "interface class EdgeDetector"

assert_file_has "DetectionResult class exists" \
  "apps/mobile/lib/features/scan/edge_detector.dart" \
  "class DetectionResult"

assert_file_has "DetectionResult has operator ==" \
  "apps/mobile/lib/features/scan/edge_detector.dart" \
  "operator =="

# ── OpenCvEdgeDetector implementation ─────────────────────────────────────
assert_file_has "OpenCvEdgeDetector exists" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "class OpenCvEdgeDetector"

assert_file_has "_runPipeline top-level function exists" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "_runPipeline"

assert_file_has "List<double> return type in _runPipeline (isolate-safe primitives)" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "List<double>?"

assert_file_has "isContourConvex convexity filter present" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "isContourConvex"

assert_file_has "compute() used (off-thread assertion)" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" \
  "compute("

# ── opencv_dart dependency ─────────────────────────────────────────────────
assert_file_has "opencv_dart in pubspec.yaml" \
  "apps/mobile/pubspec.yaml" \
  "opencv_dart"

# ── DIP check: edge_detector.dart must NOT import opencv_dart ─────────────
if grep -q "^import.*opencv_dart" \
    "apps/mobile/lib/features/scan/edge_detector.dart" 2>/dev/null; then
  fail "DIP violation: edge_detector.dart imports opencv_dart — callers must not see it"
else
  pass "DIP: edge_detector.dart does not import opencv_dart"
fi

# ── FakeEdgeDetector ──────────────────────────────────────────────────────
assert_file_has "FakeEdgeDetector in fake_scan.dart" \
  "apps/mobile/test/support/fake_scan.dart" \
  "FakeEdgeDetector"

assert_file_has "FakeEdgeDetector.calls counter" \
  "apps/mobile/test/support/fake_scan.dart" \
  "int calls"

# ── Integration test file ─────────────────────────────────────────────────
assert_file_has "f1_edge_detection_test.dart present" \
  "apps/mobile/integration_test/f1_edge_detection_test.dart" \
  "F1 edge detection"

# ── Suite ──────────────────────────────────────────────────────────────────
assert_cmd "unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ── Device ─────────────────────────────────────────────────────────────────
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android f1_edge_detection_test.dart
verify_integration_ios f1_edge_detection_test.dart

# ── Opt-in REAL_DEVICE Tier-3 ─────────────────────────────────────────────
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "MANUAL: Open the app and capture a document."
  echo "Verify: detect() returns a non-null DetectionResult for a live JPEG."
  echo "(F2 will display the result in the crop overlay — not part of F1.)"
fi

verify_summary
