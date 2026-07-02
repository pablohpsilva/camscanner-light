#!/usr/bin/env bash
# Verify H4 (Delete / retake page) acceptance criteria.
# Run from repository root: bash scripts/verify/h4.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== H4 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "deletePage in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "deletePage"

assert_file_has "replacePage in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "replacePage"

assert_file_has "deletePage in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "deletePage"

assert_file_has "replacePage in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "replacePage"

assert_file_has "onCapture single-capture mode in CameraScreen" \
  "apps/mobile/lib/features/scan/camera_screen.dart" \
  "onCapture"

assert_file_has "page menu in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-page-menu"

assert_file_has "retake handler in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "_retakePage"

assert_file_has "delete-page handler in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "_confirmAndDeletePage"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/h4_delete_retake.feature" \
  "Delete page"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/h4_delete_retake_test.dart" \
  "iDeleteTheCurrentPage"

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
    pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=h4
fi

echo "== H4 verification complete =="

verify_summary
