#!/usr/bin/env bash
# Verify O5 (library search by name + OCR content) acceptance criteria.
# Run from repository root: bash scripts/verify/o5.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== O5 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "searchDocuments on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "searchDocuments"

assert_file_has "searchDocuments in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "searchDocuments"

assert_file_has "home wires the search field" \
  "apps/mobile/lib/features/library/home_screen.dart" \
  "documents-search-field"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/o5_content_search.feature" \
  "Search the library by content"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/o5_content_search_test.dart" \
  "content"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device O5 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device search test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o5_content_search_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o5_content_search_test.dart"
fi

echo "== O5 verification complete =="
