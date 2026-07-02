#!/usr/bin/env bash
# Verify I2 (Gallery import) acceptance criteria.
# Run from repository root: bash scripts/verify/i2.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== I2 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "GalleryPicker interface exists" \
  "apps/mobile/lib/features/scan/gallery_picker.dart" \
  "abstract interface class GalleryPicker"

assert_file_has "ImagePickerGalleryPicker impl exists" \
  "apps/mobile/lib/features/scan/gallery_picker.dart" \
  "ImagePickerGalleryPicker"

assert_file_has "createGalleryPicker in ScanDependencies" \
  "apps/mobile/lib/features/scan/scan_dependencies.dart" \
  "createGalleryPicker"

assert_file_has "image_picker dependency" \
  "apps/mobile/pubspec.yaml" \
  "image_picker"

assert_file_has "camera-import button in CameraScreen" \
  "apps/mobile/lib/features/scan/camera_screen.dart" \
  "camera-import"

assert_file_has "_onImport handler in CameraScreen" \
  "apps/mobile/lib/features/scan/camera_screen.dart" \
  "_onImport"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/i2_gallery_import.feature" \
  "Gallery import"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/i2_gallery_import_test.dart" \
  "iImportAPhotoFromTheGallery"

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
    pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=i2
fi

echo "== I2 verification complete =="

verify_summary
