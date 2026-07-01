#!/usr/bin/env bash
# Verify N1 (print a document) acceptance criteria.
# Run from repository root: bash scripts/verify/n1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== N1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "DocumentPrinter seam exists" \
  "apps/mobile/lib/features/library/document_printer.dart" \
  "abstract interface class DocumentPrinter"

assert_file_has "printing dependency added" \
  "apps/mobile/pubspec.yaml" \
  "printing:"

assert_file_has "page viewer wires Print" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-print"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/n1_print_document.feature" \
  "Print a document"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/n1_print_document_test.dart" \
  "print"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device N1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device print PDF test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/n1_print_document_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/n1_print_document_test.dart"
fi

echo "== N1 verification complete =="
