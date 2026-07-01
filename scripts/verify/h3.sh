#!/usr/bin/env bash
# Verify H3 (Reorder pages) acceptance criteria.
# Run from repository root: bash scripts/verify/h3.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== H3 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "reorderPages in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "reorderPages"

assert_file_has "reorderPages in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "reorderPages"

assert_file_has "onReorder parameter in PageThumbnailStrip" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "onReorder"

assert_file_has "ReorderableListView in PageThumbnailStrip" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "ReorderableListView"

assert_file_has "ReorderableDragStartListener in PageThumbnailStrip" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "ReorderableDragStartListener"

assert_file_has "_reorderPages in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "_reorderPages"

assert_file_has "onReorder wired in PageViewerScreen" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "onReorder"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/h3_page_reorder.feature" \
  "Page reorder"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/h3_page_reorder_test.dart" \
  "thePageViewerIsOpenWith2Pages"

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
    pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=h3
fi

echo "== H3 verification complete =="
