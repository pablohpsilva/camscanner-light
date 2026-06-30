#!/usr/bin/env bash
# Verify E3 (re-edit crop corners) acceptance criteria.
# VERIFY_SKIP_DEVICE=1  — skips device launches (reported FAIL, never silent).
# REAL_DEVICE=1         — Tier-3 manual lane (open saved doc, re-edit corners, confirm new flat).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== E3 verification =="

require_tool flutter
require_tool pnpm
require_tool git

# ── Interface ──────────────────────────────────────────────────────────────
assert_file_has "updatePageCorners on DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "updatePageCorners"

# ── DriftDocumentRepository implementation ────────────────────────────────
assert_file_has "updatePageCorners implemented in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "updatePageCorners"

assert_file_has "fullFrame branch: flat file delete in impl" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "CropCorners.fullFrame"

# ── EditCropScreen ─────────────────────────────────────────────────────────
assert_file_has "EditCropScreen class exists" \
  "apps/mobile/lib/features/library/edit_crop_screen.dart" \
  "class EditCropScreen"

assert_file_has "edit-crop-accept key in EditCropScreen" \
  "apps/mobile/lib/features/library/edit_crop_screen.dart" \
  "edit-crop-accept"

assert_file_has "CropOverlay used in EditCropScreen" \
  "apps/mobile/lib/features/library/edit_crop_screen.dart" \
  "CropOverlay("

# ── PageViewerScreen wiring ────────────────────────────────────────────────
assert_file_has "edit_crop_screen imported in viewer" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "edit_crop_screen"

assert_file_has "page-viewer-edit key in viewer" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-edit"

assert_file_has "_editCrop method in viewer" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "_editCrop"

# ── DIP check: viewer does not import PerspectiveWarper ───────────────────
if grep -q "perspective_warper" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" 2>/dev/null; then
  fail "PerspectiveWarper imported by viewer — DIP violation"
else
  pass "DIP: PerspectiveWarper not imported by viewer"
fi

# ── Test helpers ───────────────────────────────────────────────────────────
assert_file_has "FakeDocumentRepository.updatePageCorners stub" \
  "apps/mobile/test/support/fake_library.dart" \
  "updatePageCorners"

assert_file_has "lastUpdatedCorners tracking field in fake" \
  "apps/mobile/test/support/fake_library.dart" \
  "lastUpdatedCorners"

assert_file_has "throwOnUpdate flag in fake" \
  "apps/mobile/test/support/fake_library.dart" \
  "throwOnUpdate"

# ── BDD steps ──────────────────────────────────────────────────────────────
assert_file_has "i_tap_the_edit_crop_button taps page-viewer-edit" \
  "apps/mobile/test/step/i_tap_the_edit_crop_button.dart" \
  "page-viewer-edit"

assert_file_has "i_tap_accept_on_the_viewer taps edit-crop-accept" \
  "apps/mobile/test/step/i_tap_accept_on_the_viewer.dart" \
  "edit-crop-accept"

# ── Feature + generated test ───────────────────────────────────────────────
assert_file_has "e3 feature file exists" \
  "apps/mobile/integration_test/e3_reedit.feature" \
  "Re-edit crop"

assert_file_has "e3 generated test file exists" \
  "apps/mobile/integration_test/e3_reedit_test.dart" \
  "Re-edit crop"

# ── Generated code current ─────────────────────────────────────────────────
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"

assert_cmd "no uncommitted generated diff" "" \
  bash -c "git diff --exit-code -- \
    apps/mobile/integration_test/e3_reedit_test.dart \
    >/dev/null 2>&1 && echo OK \
    || (echo 'GENERATED FILES STALE'; exit 1)"

# ── Suite ──────────────────────────────────────────────────────────────────
assert_cmd "unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ── Device ─────────────────────────────────────────────────────────────────
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android e3_reedit_test.dart
verify_integration_ios e3_reedit_test.dart

# ── Opt-in REAL_DEVICE Tier-3 ─────────────────────────────────────────────
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "MANUAL: Capture an angled document, accept with adjusted corners."
  echo "Open the document; confirm flat image is shown."
  echo "Tap Edit crop. Adjust at least one corner. Accept."
  echo "Verify the page viewer now shows the newly re-warped flat image."
  echo "Tap Edit crop again; drag all corners to fullFrame positions. Accept."
  echo "Verify the original (un-warped) image is shown."
fi

verify_summary
