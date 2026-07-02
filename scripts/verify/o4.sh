#!/usr/bin/env bash
# Verify O4 (recognized text: view / copy / export .txt) acceptance criteria.
# Run from repository root: bash scripts/verify/o4.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== O4 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "exportRecognizedText on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportRecognizedText"

assert_file_has "exportRecognizedText in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "exportRecognizedText"

assert_file_has "RecognizedTextScreen exists" \
  "apps/mobile/lib/features/library/recognized_text_screen.dart" \
  "class RecognizedTextScreen"

assert_file_has "page viewer wires View text" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-view-text"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/o4_recognized_text.feature" \
  "View and copy recognized text"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/o4_recognized_text_test.dart" \
  "recognized text"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device O4 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device recognized-text test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o4_recognized_text_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o4_recognized_text_test.dart"
fi

echo "== O4 verification complete =="

verify_summary
