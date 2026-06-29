#!/usr/bin/env bash
# Verify D3 (sort the library) acceptance criteria.
# Run: bash scripts/verify/d3.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (sort on a physical device — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== D3 verification =="

require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence: pure sort model ----
assert_file_has "sort model defines sortDocuments" \
  "apps/mobile/lib/features/library/document_sort.dart" "List<DocumentSummary> sortDocuments("
assert_file_has "sort model defines nextSort" \
  "apps/mobile/lib/features/library/document_sort.dart" "DocumentSort nextSort("
assert_file_has "sort model defines the DocumentSort class" \
  "apps/mobile/lib/features/library/document_sort.dart" "class DocumentSort"
assert_file_has "name sort is case-insensitive" \
  "apps/mobile/lib/features/library/document_sort.dart" "toLowerCase()"

# ---- Source presence: control + keys ----
assert_file_has "sort control bar exists" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "class SortControlBar"
assert_file_has "sort control bar key" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "sort-control-bar"
assert_file_has "name chip key" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "sort-chip-name"
assert_file_has "created chip key" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "sort-chip-created"
assert_file_has "modified chip key" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "sort-chip-modified"
assert_file_has "asc direction key" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "sort-direction-asc"
assert_file_has "desc direction key" \
  "apps/mobile/lib/features/library/widgets/sort_control_bar.dart" "sort-direction-desc"
assert_file_has "home screen renders the sort control" \
  "apps/mobile/lib/features/library/home_screen.dart" "SortControlBar("
assert_file_has "home screen sorts the summaries" \
  "apps/mobile/lib/features/library/home_screen.dart" "sortDocuments(_summaries"

# ---- Constraints: no schema change, no repo signature change, privacy ----
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "repo list signature unchanged (no sort arg)" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<List<DocumentSummary>> listDocumentSummaries();"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard ----
assert_file_has "step: tap-sort-chip is real (not a stub)" \
  "apps/mobile/test/step/i_tap_the_sort_chip.dart" "sort-chip-"
assert_file_has "step: chip-active asserts selected (not a stub)" \
  "apps/mobile/test/step/i_see_the_sort_chip_is_active.dart" "selected"
assert_file_has "generated d3 test calls the tap-chip step" \
  "apps/mobile/integration_test/d3_sort_test.dart" "iTapTheSortChip(tester"
assert_file_has "generated d3 test calls the assertion step" \
  "apps/mobile/integration_test/d3_sort_test.dart" "iSeeTheSortChipIsActive(tester"

# ---- Generated code current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (d3 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/d3_sort_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria ----
assert_cmd "d3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android d3_sort_test.dart
verify_integration_ios d3_sort_test.dart

# ---- Opt-in REAL_DEVICE Tier-3 ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): with >=2 scanned documents, tap each sort chip (Name/Created/Modified) and re-tap to flip direction; confirm the list visibly reorders and the active chip shows the matching arrow."
fi

verify_summary
