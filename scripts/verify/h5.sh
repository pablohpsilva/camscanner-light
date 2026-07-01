#!/usr/bin/env bash
# Verify H5 (Multi-page PDF export) acceptance criteria.
# Run from repository root: bash scripts/verify/h5.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== H5 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "builder multi-page test exists" \
  "apps/mobile/test/features/library/pdf/pdf_builder_test.dart" \
  "multi-page: one PDF page per input page"

assert_file_has "exportPdf multi-page test exists" \
  "apps/mobile/test/features/library/drift_document_repository_test.dart" \
  "exportPdf writes one PDF page per document page"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/h5_multipage_pdf.feature" \
  "Multi-page PDF export"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/h5_multipage_pdf_test.dart" \
  "theExportedPdfHas3Pages"

# ---- OpenCV host library (scan tests in shared suite need it) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Host tests + analyze ----
assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

# ---- On-device BDD (skippable for CI without a device) ----
if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device BDD skipped (must pass on real device before gate)"
else
  assert_cmd "on-device BDD passes (iOS)" "All tests passed" \
    pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=h5
fi

echo "== H5 verification complete =="
