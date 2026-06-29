#!/usr/bin/env bash
# Verify B3 (page viewer / tap-to-open + delete) acceptance criteria.
# Run: bash scripts/verify/b3.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (pinch-zoom + post-delete OS-kill, manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== B3 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "PageImage read model exists" \
  "apps/mobile/lib/features/library/page_image.dart" "class PageImage"
assert_file_has "repository exposes getDocumentPages" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<List<PageImage>> getDocumentPages(int documentId)"
assert_file_has "repository exposes deleteDocument" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<void> deleteDocument(int documentId)"
assert_file_has "delete is transactional (row-first)" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "deleteDocumentDir(documentId)"
assert_file_has "PageViewerScreen exists" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "class PageViewerScreen"
assert_file_has "viewer uses InteractiveViewer (zoom/pan)" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "InteractiveViewer"
assert_file_has "delete dialog returns a bool (screen owns the sequence)" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "showDialog<bool>"
assert_file_has "list view has the onOpen callback" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "ValueChanged<DocumentSummary>? onOpen"
assert_file_has "home wires tap-to-open" \
  "apps/mobile/lib/features/library/home_screen.dart" "PageViewerScreen("
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard: each new B3 step is a real implementation ----
assert_file_has "step: open document is real (not a stub)" \
  "apps/mobile/test/step/i_open_the_first_document.dart" "tester.tap"
assert_file_has "step: delete document is real (not a stub)" \
  "apps/mobile/test/step/i_delete_the_open_document.dart" "page-viewer-delete-confirm"
assert_file_has "step: gone-from-home is real (not a stub)" \
  "apps/mobile/test/step/the_document_is_gone_from_the_home.dart" "findsNothing"
assert_file_has "generated b3 test calls the open step" \
  "apps/mobile/integration_test/b3_view_and_delete_test.dart" "iOpenTheFirstDocument(tester)"
assert_file_has "generated b3 test calls the delete step" \
  "apps/mobile/integration_test/b3_view_and_delete_test.dart" "iDeleteTheOpenDocument(tester)"
assert_file_has "generated b3 test calls the gone-from-home step" \
  "apps/mobile/integration_test/b3_view_and_delete_test.dart" "theDocumentIsGoneFromTheHome(tester)"

# ---- Generated code is current (Drift unchanged + new BDD test) ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + b3 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/b3_view_and_delete_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "b3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android b3_view_and_delete_test.dart
verify_integration_ios b3_view_and_delete_test.dart

# ---- Opt-in REAL_DEVICE Tier-3: pinch-zoom + post-delete OS-kill ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device connected"
  else
    "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/b3-real-viewer.png" 2>/dev/null
    pass "REAL_DEVICE: captured viewer screen (evidence: b3-real-viewer.png)"
    echo "REAL_DEVICE Tier-3 (MANUAL): (1) open a document, pinch-zoom — the page MAGNIFIES and renders UPRIGHT; (2) delete it, then 'adb shell am force-stop $APP_ID' + relaunch — the document is still GONE."
  fi
  echo "REAL_DEVICE (iOS): MANUAL — confirm pinch-zoom magnifies + upright, and a deleted document stays gone after an OS kill on a physical iPhone."
fi

verify_summary
