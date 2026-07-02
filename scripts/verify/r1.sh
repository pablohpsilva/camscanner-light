#!/usr/bin/env bash
# Verify R1 (share a document) acceptance criteria.
# Run from repository root: bash scripts/verify/r1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== R1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "ShareChannel seam exists" \
  "apps/mobile/lib/features/library/share_channel.dart" \
  "abstract interface class ShareChannel"

assert_file_has "SystemShareChannel implementation exists" \
  "apps/mobile/lib/features/library/share_channel.dart" \
  "class SystemShareChannel implements ShareChannel"

assert_file_has "LibraryDependencies exposes the channel" \
  "apps/mobile/lib/features/library/library_dependencies.dart" \
  "ShareChannel share"

assert_file_has "documents list wires Share" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" \
  "document-share-"

assert_file_has "home screen shares via exportPdf" \
  "apps/mobile/lib/features/library/home_screen.dart" \
  "_shareDocument"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/r1_share_document.feature" \
  "Share a document"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/r1_share_document_test.dart" \
  "iShareTheFirstDocument"

# share_plus must be isolated to the seam (exactly one importer).
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
  warn "VERIFY_SKIP_DEVICE=1 — on-device R1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device share PDF test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/r1_share_document_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/r1_share_document_test.dart"
fi

echo "== R1 verification complete =="

verify_summary
