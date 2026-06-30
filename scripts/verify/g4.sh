#!/usr/bin/env bash
# Verify G4 (Filter picker UI) acceptance criteria.
# Run from repository root: bash scripts/verify/g4.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G4 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "EnhancerMode public enum exists" \
  "apps/mobile/lib/features/library/enhancer_mode.dart" \
  "enum EnhancerMode"

assert_file_has "FilterPickerStrip class exists" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "class FilterPickerStrip"

assert_file_has "_thumbFn top-level function present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "_thumbFn"

assert_file_has "bakeOrientation called in _thumbFn" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "bakeOrientation"

assert_file_has "compute() used in FilterPickerStrip" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "compute"

assert_file_has "filter-tile-auto key present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "filter-tile-auto"

assert_file_has "filter-tile-original key present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "filter-tile-original"

assert_file_has "filter-tile-bw key present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "filter-tile-bw"

assert_file_has "filter-picker-strip key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "filter-picker-strip"

assert_file_has "EnhancerMode.auto is default in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "EnhancerMode.auto"

# Negative: old toggle keys must be gone
if grep -qF "grayscale-toggle" "apps/mobile/lib/features/scan/capture_review_screen.dart"; then
  fail "old grayscale-toggle key found in review screen — must be removed"
else
  pass "old AppBar toggle keys absent from review screen"
fi

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g4_filter_picker.feature" \
  "Filter picker strip"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g4_filter_picker_test.dart" \
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

verify_integration_android g4_filter_picker_test.dart
verify_integration_ios g4_filter_picker_test.dart

verify_summary
