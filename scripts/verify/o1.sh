#!/usr/bin/env bash
# Verify O1 (OCR page-text foundation) acceptance criteria.
# Run from repository root: bash scripts/verify/o1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration test.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== O1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "OcrEngine interface exists" \
  "apps/mobile/lib/features/library/ocr/ocr_engine.dart" \
  "abstract interface class OcrEngine"

assert_file_has "NoOpOcrEngine exists" \
  "apps/mobile/lib/features/library/ocr/ocr_engine.dart" \
  "NoOpOcrEngine"

assert_file_has "OcrResult model exists" \
  "apps/mobile/lib/features/library/ocr/ocr_result.dart" \
  "class OcrResult"

assert_file_has "ocrText column in Pages" \
  "apps/mobile/lib/features/library/drift/app_database.dart" \
  "ocrText"

assert_file_has "runOcr in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "runOcr"

assert_file_has "on-device OCR integration test exists" \
  "apps/mobile/integration_test/o1_ocr_test.dart" \
  "runOcr caches recognized text"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device OCR integration test skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device OCR integration test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o1_ocr_test.dart"
fi

echo "== O1 verification complete =="

verify_summary
