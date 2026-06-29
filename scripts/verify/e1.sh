#!/usr/bin/env bash
# Verify E1 (corner overlay) acceptance criteria.
# Run: bash scripts/verify/e1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (drag corners on a physical device — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== E1 verification =="

require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence: CropCorners model ----
assert_file_has "CropCorners class" \
  "apps/mobile/lib/features/library/crop_corners.dart" "class CropCorners"
assert_file_has "CropCorners.fullFrame" \
  "apps/mobile/lib/features/library/crop_corners.dart" "fullFrame"
assert_file_has "CropCorners.toStorage" \
  "apps/mobile/lib/features/library/crop_corners.dart" "toStorage"
assert_file_has "CropCorners.tryParse" \
  "apps/mobile/lib/features/library/crop_corners.dart" "tryParse"

# ---- Schema migration ----
assert_file_has "schemaVersion bumped to 2" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 2;"
assert_file_has "Pages.corners column" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "get corners =>"
assert_file_has "onUpgrade addColumn" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "addColumn"

# ---- Overlay + keys + a11y ----
assert_file_has "CropOverlay class" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "class CropOverlay"
assert_file_has "overlay key" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "crop-overlay"
assert_file_has "handle tl key" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "crop-handle-"
assert_file_has "overlay handles are a11y-labeled" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "Semantics"

# ---- Review wiring ----
assert_file_has "review hosts the overlay" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" "CropOverlay("
assert_file_has "review reset control" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" "crop-reset"

# ---- Persistence wiring ----
assert_file_has "createFromCapture takes corners" \
  "apps/mobile/lib/features/library/document_repository.dart" "createFromCapture(CapturedImage capture, {CropCorners? corners})"
assert_file_has "PageImage carries corners" \
  "apps/mobile/lib/features/library/page_image.dart" "corners"

# ---- Privacy + E2 orientation contract ----
assert_file_has "scrubber re-emits Orientation (E2 frame contract)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "Orientation"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard ----
assert_file_has "step: see-overlay is real (not a stub)" \
  "apps/mobile/test/step/i_see_the_crop_overlay.dart" "crop-overlay"
assert_file_has "step: drag-corner is real (not a stub)" \
  "apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart" "crop-handle-tl"
assert_file_has "step: drag-corner actually drags" \
  "apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart" "drag"
assert_file_has "generated e1 test calls the see-overlay step" \
  "apps/mobile/integration_test/e1_crop_test.dart" "iSeeTheCropOverlay(tester"
assert_file_has "generated e1 test calls the drag step" \
  "apps/mobile/integration_test/e1_crop_test.dart" "iDragTheTopLeftCropCorner(tester"

# ---- Generated code current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (e1 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/e1_crop_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria ----
assert_cmd "e1 unit + widget + migration tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android e1_crop_test.dart
verify_integration_ios e1_crop_test.dart

# ---- Opt-in REAL_DEVICE Tier-3 ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): capture a document; confirm 4 corner handles appear, each drags and tracks the finger, the quad/scrim update, Reset restores full frame, and Accept saves the document."
fi

verify_summary
