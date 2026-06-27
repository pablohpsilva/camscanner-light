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

## Plan files (ordered)

Status: ✅ written & ready · ⏳ pending (written when its predecessor passes the gate)

| Order | Step | Spec | Plan file | Status |
|------|------|------|-----------|--------|
| 0 | Monorepo foundation | `step-0` design | `2026-06-27-step-0-monorepo-foundation.md` | ✅ **built & gated** |
| A1 | App shell: home (empty Documents list) + Scan button | 02, 01 | `2026-06-27-a1-app-shell.md` | ✅ written |
| A2 | Camera preview + permission | 01 | `…-a2-camera-preview.md` | ⏳ |
| A3 | Capture photo → review screen | 01 | `…-a3-capture-review.md` | ⏳ |
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
| G1 | Grayscale filter | 05 | `…-g1-grayscale.md` | ⏳ |
| G2 | Black & White filter | 05 | `…-g2-bw.md` | ⏳ |
| G3 | Color / Auto-Magic filter | 05 | `…-g3-color-auto.md` | ⏳ |
| G4 | Filter picker UI | 05 | `…-g4-picker.md` | ⏳ |
| H1 | Add multiple pages | 06 | `…-h1-add-pages.md` | ⏳ |
| H2 | Page thumbnail strip | 06 | `…-h2-thumbnails.md` | ⏳ |
| H3 | Reorder pages | 06 | `…-h3-reorder.md` | ⏳ |
| H4 | Delete / retake page | 06 | `…-h4-delete-retake.md` | ⏳ |
| H5 | Multi-page PDF export | 07 | `…-h5-multipage-pdf.md` | ⏳ |
| I1 | Export page as image | 10 | `…-i1-export-image.md` | ⏳ |
| I2 | Gallery import | 01 | `…-i2-gallery-import.md` | ⏳ |

Later sub-projects (08 OCR, 09 PDF editing, 10 conversion, 12 sharing) get their
own ordered plan files once Sub-project 1 is complete and gated.

Cross-cutting concerns (metadata scrubber, searchable-PDF text-layer interface,
password) are introduced as shared, single-responsibility files in the first
plan that needs them and reused thereafter (DRY).
