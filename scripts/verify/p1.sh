#!/usr/bin/env bash
# Verify P1 (PDF password protection) acceptance criteria.
# Run from repository root: bash scripts/verify/p1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== P1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "PdfEncryptor seam exists" \
  "apps/mobile/lib/features/library/pdf/pdf_encryptor.dart" \
  "abstract interface class PdfEncryptor"

assert_file_has "syncfusion dependency added" \
  "apps/mobile/pubspec.yaml" \
  "syncfusion_flutter_pdf:"

assert_file_has "exportProtectedPdf in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "exportProtectedPdf"

assert_file_has "page viewer wires Protect" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-protect"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/p1_pdf_password.feature" \
  "Password-protect a PDF"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/p1_pdf_password_test.dart" \
  "protect"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device P1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device protected-PDF test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/p1_pdf_password_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/p1_pdf_password_test.dart"
fi

echo "== P1 verification complete =="
