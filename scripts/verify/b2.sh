#!/usr/bin/env bash
# Verify B2 (documents list reads from storage) acceptance criteria.
# Run: bash scripts/verify/b2.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 OS-kill (force-stop + relaunch) lane (manual upright check).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== B2 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "DocumentSummary read model exists" \
  "apps/mobile/lib/features/library/document_summary.dart" "class DocumentSummary"
assert_file_has "repository exposes listDocumentSummaries" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<List<DocumentSummary>> listDocumentSummaries()"
assert_file_has "list read is no-N+1 (grouped aggregate)" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "groupBy("
assert_file_has "DocumentThumbnail uses Image.file + cacheWidth" \
  "apps/mobile/lib/features/library/widgets/document_thumbnail.dart" "cacheWidth:"
assert_file_has "list view renders thumbnails" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "DocumentThumbnail("
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"
assert_file_has "Tier-2 persistent deps helper exists" \
  "apps/mobile/test/support/fake_library.dart" "persistentLibraryDependencies"
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"

# ---- Generated code is current (Drift unchanged + new BDD test) ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + b2 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/b2_restart_persistence_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria: unit + widget tests (incl. Tier-1 persistence + EXIF regression), analyze, coverage ----
assert_cmd "b2 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration tests) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android b2_restart_persistence_test.dart
verify_integration_ios b2_restart_persistence_test.dart

# ---- Opt-in REAL_DEVICE Tier-3: true OS kill (force-stop) + relaunch shows the doc ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 (OS-kill) lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device connected"
  else
    "$ADB" -s "$rdev" shell am force-stop "$APP_ID" 2>/dev/null
    "$ADB" -s "$rdev" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
    "$ADB" -s "$rdev" shell wm dismiss-keyguard 2>/dev/null
    "$ADB" -s "$rdev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    "$ADB" -s "$rdev" shell sleep 7
    "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/b2-real-restart-home.png" 2>/dev/null
    pass "REAL_DEVICE: force-stopped + relaunched (evidence: b2-real-restart-home.png)"
    echo "REAL_DEVICE Tier-3: MANUAL — confirm the home list shows the previously-saved document with an UPRIGHT thumbnail (see b2-real-restart-home.png)."
  fi
  echo "REAL_DEVICE (iOS): MANUAL — confirm a saved document survives an OS kill and renders upright on a physical iPhone."
fi

verify_summary
