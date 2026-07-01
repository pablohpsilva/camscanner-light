#!/usr/bin/env bash
# Verify H2 (Page thumbnail strip) acceptance criteria.
# Run from repository root: bash scripts/verify/h2.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== H2 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "PageThumbnailStrip class exists" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "class PageThumbnailStrip"

assert_file_has "Key(page-thumbnail-strip) in page_thumbnail_strip.dart" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "page-thumbnail-strip"

assert_file_has "Key(page-thumb- prefix) in page_thumbnail_strip.dart" \
  "apps/mobile/lib/features/library/widgets/page_thumbnail_strip.dart" \
  "page-thumb-"

assert_file_has "PageThumbnailStrip used in page_viewer_screen.dart" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "PageThumbnailStrip"

assert_file_has "page_thumbnail_strip.dart imported in page_viewer_screen.dart" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page_thumbnail_strip.dart"

# Negative: old indicator must be gone from the viewer screen
if grep -qF "page-viewer-indicator" "apps/mobile/lib/features/library/page_viewer_screen.dart"; then
  fail "old page-viewer-indicator key still present in page_viewer_screen.dart — must be removed"
else
  pass "old page-viewer-indicator absent from page_viewer_screen.dart"
fi

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/h2_page_thumbnail_strip.feature" \
  "Page thumbnail strip"

assert_file_has "BDD generated test exists" \
  "apps/mobile/integration_test/h2_page_thumbnail_strip_test.dart" \
  "thePageViewerIsOpenWith2Pages"

# ---- OpenCV host library (scan tests in shared suite need it) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Host tests + analyze + coverage ----
assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device gate (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android h2_page_thumbnail_strip_test.dart
verify_integration_ios h2_page_thumbnail_strip_test.dart

verify_summary
