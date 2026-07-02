# Implementation Plans — Index

One plan file **per step**. Each plan produces working, tested software on its
own and decomposes code into **multiple focused, single-responsibility files**
(SOLID) — never one large file.

## Progression Gate (binding)

**We only move to the next step when the previous step is fully done** — every
acceptance criterion in its spec is developed, tested, fulfilled, and **working**
(observed green, quality gates clean, reviewed and double-checked, per the
Definition of Done in `../specs/00-overview-roadmap.md`).

A step's plan file is **written only after** its predecessor passes the gate — we
plan and build progressively, not speculatively.

**Verification harness (binding) — see `../VERIFICATION.md`.** Every step ships
`scripts/verify/<step>.sh` (built on `scripts/verify/lib.sh`) that encodes its
acceptance criteria as asserts — exact command + success marker, exit-code check,
caches disabled, negative controls, **silence = FAIL**. The gate is that script
exiting 0, and an **independent adversarial verifier subagent** must run it from
a clean state and agree before the step is marked done. The final task of every
plan is "author `scripts/verify/<step>.sh` and pass it under the independent
verifier."

Any step that adds/changes UI also ships an
`apps/mobile/integration_test/<step>_*.dart` test asserting the rendered widget
tree on each device (run via `verify_integration_{android,ios}`) — the
**authoritative on-device UI check**, mutation-verified once; screenshots are
corroborating only.

**BDD-from-.feature standard (from A3 onwards):** BDD scenarios are authored
as `.feature` files (Gherkin) under `apps/mobile/integration_test/` and
generated into on-device integration tests via `bdd_widget_test` + `build_runner`.
Step definitions live in `apps/mobile/test/step/` (shared, reusable).
Generated `*_test.dart` files are committed (idempotent). The A2 scenarios are
the reference example (`a2_scan_permission.feature` → `a2_scan_permission_test.dart`).

## Plan files (ordered)

Status: ✅ written & ready · ⏳ pending (written when its predecessor passes the gate)

| Order | Step | Spec | Plan file | Status |
|------|------|------|-----------|--------|
| 0 | Monorepo foundation | `step-0` design | `2026-06-27-step-0-monorepo-foundation.md` | ✅ **built & gated** |
| A1 | App shell: home (empty Documents list) + Scan button | 02, 01 | `2026-06-27-a1-app-shell.md` | ✅ **built & gated** |
| A2 | Camera preview + permission | 01 | `2026-06-27-a2-camera-preview.md` | ✅ **built & gated** |
| A3 | Capture photo → review screen | 01 | `2026-06-27-a3-capture-review.md` | ✅ **built & gated** |
| B1 | Save photo + document record (storage) | 02, 06 | `…-b1-persist-page.md` | ⏳ |
| B2 | Documents list reads storage | 02 | `…-b2-list-from-storage.md` | ⏳ |
| B3 | Page viewer | 02 | `…-b3-page-viewer.md` | ⏳ |
| C1 | Single-page PDF generation | 07 | `…-c1-pdf-generate.md` | ⏳ |
| C2 | In-app PDF preview *(walking skeleton)* | 07 | `…-c2-pdf-preview.md` | ⏳ |
| D1 | Rename document | 02 | `…-d1-rename.md` | ⏳ |
| D2 | Delete document | 02 | `…-d2-delete.md` | ⏳ |
| D3 | Sort documents | 02 | `…-d3-sort.md` | ⏳ |
| E1 | Manual crop corner overlay | 03 | `…-e1-crop-overlay.md` | ⏳ |
| E2 | Perspective flatten | 03 | `…-e2-flatten.md` | ⏳ |
| E3 | Re-edit crop | 03 | `…-e3-recrop.md` | ⏳ |
| F1 | Auto contour detection | 04 | `…-f1-detect.md` | ⏳ |
| F2 | Pre-fill crop corners | 04 | `…-f2-prefill.md` | ⏳ |
| F3 | Live edge overlay (stretch) | 04 | `…-f3-live-overlay.md` | ⏳ |
| G1 | Grayscale filter | 05 | `2026-06-30-g1-grayscale.md` | ✅ **built & gated** |
| G2 | Black & White filter | 05 | `2026-06-30-g2-bw.md` | ✅ **built & gated** |
| G3 | Color / Auto-Magic filter | 05 | `2026-07-01-g3-color-auto.md` | ✅ **built & gated** |
| G4 | Filter picker UI | 05 | `2026-07-01-g4-filter-picker.md` | ✅ **built & gated** |
| H1 | Add multiple pages | 06 | `2026-07-01-h1-add-pages.md` | ✅ **built & gated** |
| H2 | Page thumbnail strip | 06 | `2026-07-01-h2-thumbnails.md` | ✅ **built & gated** |
| H3 | Reorder pages | 06 | `2026-07-01-h3-reorder-pages.md` | ✅ **built & gated** |
| E4 | Curved warp (Coons patch) | 03 | `2026-07-01-curved-crop-coons-warp.md` | ✅ **built & gated** |
| H4 | Delete / retake page | 06 | `2026-07-01-h4-delete-retake-pages.md` | ✅ **built & gated** |
| H5 | Multi-page PDF export | 07 | `2026-07-01-h5-multipage-pdf.md` | ✅ **built & gated** |
| I1 | Export page as image | 10 | `2026-07-01-i1-export-image.md` | ✅ **built & gated** |
| I2 | Gallery import | 01 | `2026-07-01-i2-gallery-import.md` | ✅ **built & gated** |
| O1 | OCR page-text foundation | 08 | `2026-07-01-o1-ocr-foundation.md` | ✅ **built & gated** |
| O2 | OCR engine (ML Kit) + auto-run after save | 08 | `2026-07-01-o2-mlkit-engine.md`¹ | ✅ **built & merged** |
| O3 | Searchable PDF text layer | 08 | `2026-07-01-o3-searchable-pdf.md`¹ | ✅ **built & merged** |
| O4 | Recognized text: view / copy / export .txt | 08 | `2026-07-01-o4-recognized-text.md` | ✅ **built & gated** |
| O5 | Library search by name + OCR content | 08, 02 | `2026-07-01-o5-content-search.md` | ✅ **built & gated** |
| J1 | Export all pages as images | 10 | `2026-07-01-j1-export-all-images.md` | ✅ **built & gated** |
| K1 | Rotate a page 90° | 09 | `2026-07-01-k1-rotate-page.md` | ✅ **built & gated** |
| L1 | Merge documents | 09 | `2026-07-01-l1-merge-documents.md` | ✅ **built & gated** |
| M1 | Split a document | 09 | `2026-07-01-m1-split-document.md` | ✅ **built & gated** |
| N1 | Print a document | 12 | `2026-07-01-n1-print-document.md` | ✅ **built & gated** |
| P1 | PDF password protection (AES-256) | 07/09 | `2026-07-02-p1-pdf-password.md` | ✅ **built & gated** |

¹ O2/O3 were built and merged directly (commits `d896f1d`, `2657c31`) ahead of a formal plan file; rows added here for an accurate index.

Later sub-projects (08 OCR, 09 PDF editing, 10 conversion, 12 sharing) get their
own ordered plan files once Sub-project 1 is complete and gated.

Cross-cutting concerns (metadata scrubber, searchable-PDF text-layer interface,
password) are introduced as shared, single-responsibility files in the first
plan that needs them and reused thereafter (DRY).
