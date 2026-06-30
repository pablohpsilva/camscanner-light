#!/usr/bin/env bash
# Verify G3 (Color & Auto-Magic filters) acceptance criteria.
# Run from repository root: bash scripts/verify/g3.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G3 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "AutoEnhancer class exists" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "class AutoEnhancer"

assert_file_has "ColorEnhancer class exists" \
  "apps/mobile/lib/features/library/color_enhancer.dart" \
  "class ColorEnhancer"

assert_file_has "_autoLevels function present in AutoEnhancer" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "_autoLevels"

assert_file_has "bakeOrientation called in AutoEnhancer" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in AutoEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "compute"

assert_file_has "bakeOrientation called in ColorEnhancer" \
  "apps/mobile/lib/features/library/color_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in ColorEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/color_enhancer.dart" \
  "compute"

assert_file_has "auto-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "auto-toggle"

assert_file_has "color-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "color-toggle"

assert_file_has "_EnhancerMode.auto present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "_EnhancerMode.auto"

assert_file_has "_EnhancerMode.color present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "_EnhancerMode.color"

assert_file_has "AutoEnhancer wired in review screen accept" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "AutoEnhancer"

assert_file_has "ColorEnhancer wired in review screen accept" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "ColorEnhancer"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g3_auto_color.feature" \
  "Auto scan enhancement"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g3_auto_color_test.dart" \
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

verify_integration_android g3_auto_color_test.dart
verify_integration_ios g3_auto_color_test.dart

verify_summary
