#!/usr/bin/env bash
# Verify C2 (in-app PDF preview) acceptance criteria.
# Run: bash scripts/verify/c2.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (open the preview, confirm visually + zoom — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== C2 verification =="

require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence ----
assert_file_has "pdfx dependency present" \
  "apps/mobile/pubspec.yaml" "pdfx: ^2.9.0"
assert_file_has "PdfPreviewScreen exists" \
  "apps/mobile/lib/features/library/pdf_preview_screen.dart" "class PdfPreviewScreen"
assert_file_has "preview renders via PdfViewPinch" \
  "apps/mobile/lib/features/library/pdf_preview_screen.dart" "PdfViewPinch"
assert_file_has "preview handles open error in-screen (not errorBuilder)" \
  "apps/mobile/lib/features/library/pdf_preview_screen.dart" "pdf-preview-error"
assert_file_has "viewer navigates to the preview" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "PdfPreviewScreen("
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard ----
assert_file_has "step: preview-opens is real (not a stub)" \
  "apps/mobile/test/step/the_pdf_preview_opens.dart" "pdf-preview-view"
assert_file_has "generated c2 test calls the preview-opens step" \
  "apps/mobile/integration_test/c2_pdf_preview_test.dart" "thePdfPreviewOpens(tester)"
assert_file_has "generated c2 test calls the export step" \
  "apps/mobile/integration_test/c2_pdf_preview_test.dart" "iExportTheOpenDocumentToPdf(tester)"

# ---- Generated code current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + c2 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/c2_pdf_preview_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria ----
assert_cmd "c2 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android c2_pdf_preview_test.dart
verify_integration_ios c2_pdf_preview_test.dart

# ---- Opt-in REAL_DEVICE Tier-3 ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): export a document, confirm the PDF preview renders the page VISUALLY correct (upright, legible) and pinch-zoom magnifies."
fi

verify_summary
