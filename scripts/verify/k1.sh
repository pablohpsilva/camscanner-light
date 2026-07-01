#!/usr/bin/env bash
# Verify K1 (rotate a page 90°) acceptance criteria.
# Run from repository root: bash scripts/verify/k1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== K1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "rotate90Cw on OcrWordBox" \
  "apps/mobile/lib/features/library/ocr/ocr_result.dart" \
  "rotate90Cw"

assert_file_has "rotatePage on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "rotatePage"

assert_file_has "rotatePage in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "copyRotate"

assert_file_has "page viewer wires Rotate" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-rotate"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/k1_rotate_page.feature" \
  "Rotate a page"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/k1_rotate_page_test.dart" \
  "rotate"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device K1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device rotate test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/k1_rotate_page_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/k1_rotate_page_test.dart"
fi

echo "== K1 verification complete =="
