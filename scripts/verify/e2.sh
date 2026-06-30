#!/usr/bin/env bash
# Verify E2 (perspective flatten) acceptance criteria.
# VERIFY_SKIP_DEVICE=1  — skips device launches (reported FAIL, never silent).
# REAL_DEVICE=1         — Tier-3 manual lane (capture angled doc, confirm flat).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== E2 verification =="

require_tool flutter
require_tool pnpm
require_tool git

# ── Interface + implementation ────────────────────────────────────────────
assert_file_has "ImageWarper interface" \
  "apps/mobile/lib/features/library/image_warper.dart" "abstract interface class ImageWarper"
assert_file_has "WarpException" \
  "apps/mobile/lib/features/library/image_warper.dart" "class WarpException"
assert_file_has "PerspectiveWarper class" \
  "apps/mobile/lib/features/library/perspective_warper.dart" "class PerspectiveWarper"
assert_file_has "bakeOrientation called (EXIF-frame contract)" \
  "apps/mobile/lib/features/library/perspective_warper.dart" "bakeOrientation"
assert_file_has "compute() isolate" \
  "apps/mobile/lib/features/library/perspective_warper.dart" "compute("

# ── DIP: PerspectiveWarper not imported by widget layer ───────────────────
if grep -r "perspective_warper" apps/mobile/lib/features/library/page_viewer_screen.dart \
    apps/mobile/lib/features/library/pdf/ 2>/dev/null | grep -q .; then
  fail "PerspectiveWarper imported by widget/pdf layer — DIP violation"
else
  pass "PerspectiveWarper not imported by widget layer"
fi

# ── Schema v3 ─────────────────────────────────────────────────────────────
assert_file_has "schemaVersion => 3" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 3;"
assert_file_has "Pages.flatRelativePath column" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "get flatRelativePath =>"
assert_file_has "onUpgrade addColumn flatRelativePath" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "pages.flatRelativePath"

# ── File store ────────────────────────────────────────────────────────────
assert_file_has "flatRelativeFor method" \
  "apps/mobile/lib/features/library/document_file_store.dart" "flatRelativeFor"

# ── PageImage.displayPath ─────────────────────────────────────────────────
assert_file_has "flatImagePath field" \
  "apps/mobile/lib/features/library/page_image.dart" "flatImagePath"
assert_file_has "displayPath getter" \
  "apps/mobile/lib/features/library/page_image.dart" "String get displayPath"

# ── Consumers use displayPath ─────────────────────────────────────────────
assert_file_has "viewer uses displayPath" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "displayPath"
assert_file_has "PdfBuilder uses displayPath" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "displayPath"

# ── Repo wiring ───────────────────────────────────────────────────────────
assert_file_has "repo warper field" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "_warper"
assert_file_has "repo warp call" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "_warper.warp("

# ── Test helpers ──────────────────────────────────────────────────────────
assert_file_has "FakeImageWarper in fake_library" \
  "apps/mobile/test/support/fake_library.dart" "class FakeImageWarper"
assert_file_has "tempLibraryDependencies wires warper" \
  "apps/mobile/test/support/fake_library.dart" "warper: const PerspectiveWarper()"

# ── image package ─────────────────────────────────────────────────────────
assert_file_has "image package in pubspec" \
  "apps/mobile/pubspec.yaml" "image:"

# ── Generated code current ────────────────────────────────────────────────
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/e2_flatten_test.dart \
    apps/mobile/lib/features/library/drift/app_database.g.dart >/dev/null 2>&1 && echo OK \
    || (echo 'GENERATED FILES STALE'; exit 1)"

# ── BDD step ─────────────────────────────────────────────────────────────
assert_file_has "i_see_the_page_viewer step is real (not a stub)" \
  "apps/mobile/test/step/i_see_the_page_viewer.dart" "page-viewer-page-1"

# ── Suite ─────────────────────────────────────────────────────────────────
assert_cmd "unit + widget + migration + warper tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ── Device ────────────────────────────────────────────────────────────────
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android e2_flatten_test.dart
verify_integration_ios e2_flatten_test.dart

# ── Opt-in REAL_DEVICE Tier-3 ─────────────────────────────────────────────
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "MANUAL: capture an angled document, adjust one corner, Accept."
  echo "Open the document. Verify the page viewer shows a flat, head-on image"
  echo "(not the original angled capture). Export to PDF; confirm PDF page is flat."
fi

verify_summary
