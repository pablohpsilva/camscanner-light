#!/usr/bin/env bash
# Verify G1 (grayscale filter) acceptance criteria.
# Run: bash scripts/verify/g1.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G1 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "ImageEnhancer interface exists" \
  "apps/mobile/lib/features/library/image_enhancer.dart" \
  "abstract interface class ImageEnhancer"

assert_file_has "NoneEnhancer exists" \
  "apps/mobile/lib/features/library/image_enhancer.dart" \
  "class NoneEnhancer"

assert_file_has "GrayscaleEnhancer exists" \
  "apps/mobile/lib/features/library/grayscale_enhancer.dart" \
  "class GrayscaleEnhancer"

assert_file_has "grayscale-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "grayscale-toggle"

assert_file_has "bakeOrientation called in GrayscaleEnhancer (orientation safety)" \
  "apps/mobile/lib/features/library/grayscale_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in GrayscaleEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/grayscale_enhancer.dart" \
  "compute"

assert_file_has "ImageEnhancer in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "ImageEnhancer"

assert_file_has "enhancer applied in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "enhancer.enhance"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g1_grayscale.feature" \
  "Grayscale"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g1_grayscale_test.dart" \
  "theReviewScreenIsOpenWithACapturedImage"

assert_file_has "CameraScreen G1 test exists" \
  "apps/mobile/test/features/scan/camera_screen_g1_test.dart" \
  "GrayscaleEnhancer"

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

verify_integration_android g1_grayscale_test.dart
verify_integration_ios g1_grayscale_test.dart

verify_summary
