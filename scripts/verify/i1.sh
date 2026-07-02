#!/usr/bin/env bash
# Verify I1 (Export page as image) acceptance criteria.
# Run from repository root: bash scripts/verify/i1.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== I1 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "exportPageAsImage in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportPageAsImage"

assert_file_has "exportPageAsImage in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "exportPageAsImage"

assert_file_has "imageExportRelativeFor in DocumentFileStore" \
  "apps/mobile/lib/features/library/document_file_store.dart" \
  "imageExportRelativeFor"

assert_file_has "export-image menu item in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-export-image"

assert_file_has "export handler in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "_exportPageAsImage"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/i1_export_image.feature" \
  "Export page as image"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/i1_export_image_test.dart" \
  "iSeeTheImageExportConfirmation"

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
    pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=i1
fi

echo "== I1 verification complete =="

verify_summary
