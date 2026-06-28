#!/usr/bin/env bash
# Verify C1 (single-page PDF) acceptance criteria.
# Run: bash scripts/verify/c1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (open the PDF, confirm visually upright — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== C1 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "PdfBuilder exists" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "class PdfBuilder"
assert_file_has "PdfBuilder embeds via MemoryImage (lossless + auto-orient)" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "pw.MemoryImage"
assert_file_has "metadata-clean by construction (no info fields set)" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "pw.Document(compress:"
assert_file_has "PdfTextLayer seam exists" \
  "apps/mobile/lib/features/library/pdf/pdf_text_layer.dart" "abstract interface class PdfTextLayer"
assert_file_has "ImageOnlyTextLayer default exists" \
  "apps/mobile/lib/features/library/pdf/pdf_text_layer.dart" "class ImageOnlyTextLayer"
assert_file_has "repository exposes exportPdf" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<File> exportPdf(int documentId)"
assert_file_has "file store has pdfRelativeFor" \
  "apps/mobile/lib/features/library/document_file_store.dart" "pdfRelativeFor"
assert_file_has "viewer wires the export action" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "page-viewer-export"
assert_file_has "pdf dependency pinned" \
  "apps/mobile/pubspec.yaml" "pdf: ^3.11.1"
assert_file_has "EXIF-6 orientation fixture is committed" \
  "apps/mobile/test/fixtures/landscape_exif6.jpg" ""
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard: the new C1 steps are real + wired ----
assert_file_has "step: export is real (not a stub)" \
  "apps/mobile/test/step/i_export_the_open_document_to_pdf.dart" "page-viewer-export"
assert_file_has "step: pdf-is-saved is real (not a stub)" \
  "apps/mobile/test/step/the_pdf_is_saved.dart" "PDF saved"
assert_file_has "generated c1 test calls the export step" \
  "apps/mobile/integration_test/c1_export_pdf_test.dart" "iExportTheOpenDocumentToPdf(tester)"
assert_file_has "generated c1 test calls the pdf-is-saved step" \
  "apps/mobile/integration_test/c1_export_pdf_test.dart" "thePdfIsSaved(tester)"

# ---- Generated code is current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + c1 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/c1_export_pdf_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "c1 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android c1_export_pdf_test.dart
verify_integration_ios c1_export_pdf_test.dart

# ---- Opt-in REAL_DEVICE Tier-3: open the PDF, confirm upright ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): export a document, then open documents/<id>/export.pdf in a PDF viewer — confirm the page renders UPRIGHT and legible, and that the file metadata has no author/producer/creator."
fi

verify_summary
