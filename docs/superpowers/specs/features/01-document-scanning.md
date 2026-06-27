# Feature 01 — Document Scanning (Capture)

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Step 0 (monorepo + app scaffold)
**Feeds:** Feature 03 (manual crop & perspective), Feature 04 (auto edge detection)

## Purpose

Turn the phone camera into the front door of the app: the act of capturing
paper materials as raw, OCR-quality source image(s) that are handed to the
crop/flatten pipeline. This feature answers exactly one question well: *"How
does a user point their phone at something and capture a clean source image?"*

## Scope

**In scope**
- Camera screen: live preview, shutter, capture controls.
- Capture modes (below).
- Auto-capture and manual capture.
- Permission and error handling.
- Producing raw captured image(s) + capture metadata for the next step.

**Out of scope (own features)**
- Corner detection (04), manual crop + perspective flatten (03), enhancement
  filters (05), multi-page document management (06), PDF export (07), gallery
  import (07 / I2).

## Capture modes

| Mode | Capture behavior | Output |
|---|---|---|
| **Single** | One shot, one page | 1 page |
| **Batch** | Rapid repeated shots, minimal taps between pages | N pages |
| **ID card** | Guided front capture, then back capture | Both stacked onto **1 page** |
| **Whiteboard** | Preset of Single; tuned detection + glare/color handling | 1 page |
| **Receipt** | Preset of Single; tuned for long/narrow thermal paper | 1 page |

- Whiteboard and Receipt are **presets over Single**, not distinct flows.
- Book mode is intentionally excluded; facing pages are handled via Batch.
- Build order: implement **Single** first, then the others.

## Capture behavior

- **Auto-capture:** default ON once available; fires when the document is
  framed, in focus, and steady (stability check / brief countdown). Built
  **manual-first** because real auto-capture depends on live edge detection
  (Feature 04).
- **Manual override:** tap-to-capture always available; user can disable
  auto-capture in settings.
- **Focus/exposure:** tap-to-focus and exposure lock.

## Capture controls & quality

| Control | Decision |
|---|---|
| Torch / flash | On / Off / Auto toggle |
| Alignment grid | Optional rule-of-thirds grid, off by default |
| Resolution | Highest available still, capped (~12 MP) — **fixed/automatic, not a user setting** (KISS) |
| Output format | JPEG, q≈90 (lossy-but-sharp, tuned for OCR) |
| Quality guard | Auto-capture only fires in focus & steady; warn on low light / blur |

Capture quality is deliberately tuned high because downstream **OCR accuracy
depends on sharpness** (see cross-cutting OCR requirement in
`00-overview-roadmap.md`).

## Output (interface to next step)

- One or more raw captured images (file paths in temp storage).
- Capture metadata: mode, timestamp, page count, ID-card front/back grouping.
- For ID card: front + back combined onto a single logical page.

## Permissions & error handling

- Request camera permission with a clear rationale before first use.
- Graceful states (no crash) for: permission denied (path to Settings),
  no camera available, low storage.

## SOLID / KISS / DRY notes

- Separate concerns: a `CameraController` abstraction (device I/O), a
  `CaptureMode` strategy per mode (open for extension, closed for modification),
  a `CaptureSession` that produces the output model. The camera screen widget
  depends on interfaces, not the concrete camera plugin (DIP).
- Mode presets (Whiteboard/Receipt) reuse the Single flow — no duplication.

## Testing strategy (TDD/BDD first)

- **Unit:** mode selection + ID-card front/back grouping; capture-settings and
  quality rules; auto-capture stability/guard logic (with a faked detector).
- **Widget:** camera screen states — permission granted/denied, torch toggle,
  mode switch, manual shutter.
- **BDD acceptance scenarios:**
  - *Given camera permission is granted, when I open Scan in Single mode and tap
    the shutter, then a sharp captured image is produced and passed to the crop
    step.*
  - *Given permission is denied, when I open Scan, then I see a rationale and a
    button to open Settings, and the app does not crash.*
  - *Given ID card mode, when I capture front then back, then both images are
    combined onto a single page in the output.*
  - *Given Batch mode, when I capture three pages in succession, then three pages
    are produced in order with minimal taps between captures.*
  - *Given auto-capture is enabled and the document is framed and steady, when it
    passes the stability check, then a capture fires automatically.*

## Acceptance criteria

1. User can open the Scan screen and capture an image in **Single** mode
   (manual shutter), producing an OCR-quality JPEG handed to the next step.
2. Mode selector exposes Single, Batch, ID card, Whiteboard, Receipt.
3. ID card mode combines front + back onto one page.
4. Torch, grid, tap-to-focus, and exposure lock work.
5. Permission-denied / no-camera states are handled gracefully.
6. All logic covered by tests written test-first; BDD scenarios pass.

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
