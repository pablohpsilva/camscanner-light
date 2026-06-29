#!/usr/bin/env bash
# Verify D1 (rename document) acceptance criteria.
# Run: bash scripts/verify/d1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (rename on a physical device — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== D1 verification =="

require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence ----
assert_file_has "repository declares rename" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<Document> rename("
assert_file_has "DocumentRenameException exists" \
  "apps/mobile/lib/features/library/document_repository.dart" "class DocumentRenameException"
assert_file_has "Drift implements rename" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "Future<Document> rename("
assert_file_has "shared rename dialog exists" \
  "apps/mobile/lib/features/library/widgets/rename_dialog.dart" "Future<String?> showRenameDialog"
assert_file_has "rename dialog field key" \
  "apps/mobile/lib/features/library/widgets/rename_dialog.dart" "rename-field"
assert_file_has "rename dialog save key" \
  "apps/mobile/lib/features/library/widgets/rename_dialog.dart" "rename-save"
assert_file_has "viewer has the rename action" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "page-viewer-rename"
assert_file_has "list view has the per-row menu" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "document-menu-"
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- (A) _name guard invariant: a renamed-then-exported PDF shows the NEW name ----
assert_file_has "viewer title is local _name state" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "_name = widget.name"
WIDGET_NAME_COUNT="$(grep -c "widget.name" apps/mobile/lib/features/library/page_viewer_screen.dart)"
if [ "$WIDGET_NAME_COUNT" = "1" ]; then
  pass "widget.name used exactly once (only the _name initializer; title + export read _name)"
else
  fail "widget.name appears $WIDGET_NAME_COUNT times (expected 1: the _name initializer) — title or export PDF may show a stale name after rename"
fi

# ---- No-empty-stub guard ----
assert_file_has "step: open-rename-menu is real (not a stub)" \
  "apps/mobile/test/step/i_open_the_rename_menu_for_the_first_document.dart" "document-rename-"
assert_file_has "step: rename-to enters text (not a stub)" \
  "apps/mobile/test/step/i_rename_the_document_to.dart" "enterText"
assert_file_has "step: rename-to taps Save (not a stub)" \
  "apps/mobile/test/step/i_rename_the_document_to.dart" "rename-save"
assert_file_has "generated d1 test calls the open-menu step" \
  "apps/mobile/integration_test/d1_rename_test.dart" "iOpenTheRenameMenuForTheFirstDocument(tester)"
assert_file_has "generated d1 test calls the rename step" \
  "apps/mobile/integration_test/d1_rename_test.dart" "iRenameTheDocumentTo(tester"
assert_file_has "generated d1 test calls the assertion step" \
  "apps/mobile/integration_test/d1_rename_test.dart" "iSeeText(tester"

# ---- Generated code current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (d1 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/d1_rename_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria ----
assert_cmd "d1 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android d1_rename_test.dart
verify_integration_ios d1_rename_test.dart

# ---- Opt-in REAL_DEVICE Tier-3 ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): rename a document from the list menu AND from the viewer; confirm the new name shows in the list and on the viewer AppBar."
fi

verify_summary
