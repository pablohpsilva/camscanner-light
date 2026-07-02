#!/usr/bin/env bash
# Verify Q1 (compress / export quality) acceptance criteria.
# Run from repository root: bash scripts/verify/q1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== Q1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "ExportQuality enum exists" \
  "apps/mobile/lib/features/library/export/export_quality.dart" \
  "enum ExportQuality"

assert_file_has "ImageCompressor seam exists" \
  "apps/mobile/lib/features/library/export/image_compressor.dart" \
  "abstract interface class ImageCompressor"

assert_file_has "compressor bakes orientation" \
  "apps/mobile/lib/features/library/export/image_compressor.dart" \
  "bakeOrientation"

assert_file_has "ExportQualityDialog exists" \
  "apps/mobile/lib/features/library/export/export_quality_dialog.dart" \
  "export-quality-dialog"

assert_file_has "PdfBuilder accepts quality" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" \
  "ExportQuality quality"

assert_file_has "repository exportPdf accepts quality" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportPdf(int documentId,"

assert_file_has "page viewer shows quality dialog" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "showExportQualityDialog"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/q1_compress_export.feature" \
  "Compress / export quality"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/q1_compress_export_test.dart" \
  "Medium"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device Q1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device compression test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/q1_compress_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/q1_compress_export_test.dart"
fi

echo "== Q1 verification complete =="

verify_summary
