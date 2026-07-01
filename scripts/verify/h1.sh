#!/usr/bin/env bash
# Verify H1 (Add multiple pages) acceptance criteria.
# Run from repository root: bash scripts/verify/h1.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== H1 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "addPageToDocument in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "addPageToDocument"

assert_file_has "addPageToDocument implemented in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "addPageToDocument"

assert_file_has "addPage method in SaveController" \
  "apps/mobile/lib/features/library/save_controller.dart" \
  "addPage"

assert_file_has "camera-done key in CameraScreen" \
  "apps/mobile/lib/features/scan/camera_screen.dart" \
  "camera-done"

assert_file_has "_activeDocId state variable in CameraScreen" \
  "apps/mobile/lib/features/scan/camera_screen.dart" \
  "_activeDocId"

assert_file_has "_pageCount state variable in CameraScreen" \
  "apps/mobile/lib/features/scan/camera_screen.dart" \
  "_pageCount"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/h1_add_pages.feature" \
  "Add multiple pages"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/h1_add_pages_test.dart" \
  "theCameraScreenIsOpen"

# ---- OpenCV host library ----
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

verify_integration_android h1_add_pages_test.dart
verify_integration_ios h1_add_pages_test.dart

verify_summary
