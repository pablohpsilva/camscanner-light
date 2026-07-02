#!/usr/bin/env bash
# Verify J1 (export all pages as images) acceptance criteria.
# Run from repository root: bash scripts/verify/j1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== J1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "exportAllPagesAsImages on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportAllPagesAsImages"

assert_file_has "exportAllPagesAsImages in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "exportAllPagesAsImages"

assert_file_has "page viewer wires Export all as images" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-export-all-images"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/j1_export_all_images.feature" \
  "Export all pages as images"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/j1_export_all_images_test.dart" \
  "images"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device J1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device export-all test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/j1_export_all_images_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/j1_export_all_images_test.dart"
fi

echo "== J1 verification complete =="

verify_summary
