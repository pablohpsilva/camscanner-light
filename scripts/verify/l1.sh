#!/usr/bin/env bash
# Verify L1 (merge documents) acceptance criteria.
# Run from repository root: bash scripts/verify/l1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== L1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "mergeInto on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "mergeInto"

assert_file_has "mergeInto in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "mergeInto"

assert_file_has "merge picker dialog exists" \
  "apps/mobile/lib/features/library/merge_picker_dialog.dart" \
  "MergePickerDialog"

assert_file_has "page viewer wires Merge" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-merge"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/l1_merge_documents.feature" \
  "Merge documents"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/l1_merge_documents_test.dart" \
  "merge"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device L1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device merge test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/l1_merge_documents_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/l1_merge_documents_test.dart"
fi

echo "== L1 verification complete =="

verify_summary
