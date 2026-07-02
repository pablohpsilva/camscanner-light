#!/usr/bin/env bash
# Verify R2 (share images + close Feature 12) acceptance criteria.
# Run from repository root: bash scripts/verify/r2.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== R2 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "page viewer shares a single image via the channel" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "Couldn't share image"

assert_file_has "page viewer shares all images via the channel" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "Couldn't share images"

assert_file_has "library share has a re-entrancy guard" \
  "apps/mobile/lib/features/library/home_screen.dart" \
  "_sharing"

assert_file_has "image-export BDD step asserts the share channel" \
  "apps/mobile/test/step/i_see_the_image_export_confirmation.dart" \
  "lastBddShareChannel"

# share_plus stays isolated to the seam (exactly one importer).
COUNT="$(grep -rl "package:share_plus" apps/mobile/lib/ | wc -l | tr -d ' ')"
if [[ "$COUNT" == "1" ]]; then
  pass "share_plus imported only by the seam"
else
  fail "share_plus imported by $COUNT files (want 1 — the seam)"
fi

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device R2 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device image-share deterministic test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/r2_share_image_device_test.dart"
  assert_cmd "on-device single-image share BDD passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/i1_export_image_test.dart"
  assert_cmd "on-device all-images share BDD passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/j1_export_all_images_test.dart"
fi

echo "== R2 verification complete =="
