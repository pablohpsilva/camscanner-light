#!/usr/bin/env bash
# Verify G2 (B&W filter) acceptance criteria.
# Run from repository root: bash scripts/verify/g2.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G2 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "BwEnhancer exists" \
  "apps/mobile/lib/features/library/bw_enhancer.dart" \
  "class BwEnhancer"

assert_file_has "_otsuThreshold function present" \
  "apps/mobile/lib/features/library/bw_enhancer.dart" \
  "_otsuThreshold"

assert_file_has "bakeOrientation called in BwEnhancer (orientation safety)" \
  "apps/mobile/lib/features/library/bw_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in BwEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/bw_enhancer.dart" \
  "compute"

assert_file_has "bw-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "bw-toggle"

assert_file_has "_EnhancerMode enum present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "_EnhancerMode"

assert_file_has "BwEnhancer wired in review screen accept" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "BwEnhancer"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g2_bw.feature" \
  "B&W"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g2_bw_test.dart" \
  "theReviewScreenIsOpenWithACapturedImage"

# ---- OpenCV host library (scan tests in shared suite need it) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Host tests + analyze + coverage ----
assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device gate (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android g2_bw_test.dart
verify_integration_ios g2_bw_test.dart

verify_summary
