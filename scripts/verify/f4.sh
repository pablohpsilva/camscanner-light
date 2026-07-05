#!/usr/bin/env bash
# Verify F4 (segmentation dot detection) — detector present + host probe green,
# including the box-tightness gate. Run: bash scripts/verify/f4.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== F4 verification =="

require_tool python3
require_tool flutter
require_tool git

# ---- Source presence (static asserts) ----
assert_file_has "detector uses convexHull quad fit" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" "cv.convexHull(contour)"
assert_file_has "detector uses epsilon sweep constant" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" "_kSegEpsFracs"
assert_file_has "detector no longer calls cv.isContourConvex" \
  "apps/mobile/lib/features/scan/opencv_edge_detector.dart" "isConvexQuad"
assert_file_has "pure isConvexQuad helper exists" \
  "apps/mobile/lib/features/scan/detector_geometry.dart" "bool isConvexQuad("
assert_file_has "probe computes tightness IoU" \
  "apps/mobile/tool/detect_probe.py" "tightness IoU="

# ---- Pure geometry unit tests ----
assert_cmd "isConvexQuad unit tests pass" "All tests passed" \
  bash -c "cd apps/mobile && flutter test test/features/scan/detector_geometry_test.dart 2>&1"

# ---- Host probe: algorithm + tightness gate (authoritative host check) ----
assert_cmd "detector host probe (incl. tightness) passes" "ALL PROBE CHECKS PASS" \
  python3 apps/mobile/tool/detect_probe.py

verify_summary
