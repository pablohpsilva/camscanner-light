# Feature 10 — PDF Conversion

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 4 — PDF conversion
**Depends on:** Feature 07 (PDF), shared metadata scrubber
**Related:** Feature 12 (sharing the results)

## Purpose

Convert between PDF and image formats — **on-device only**, preserving the
privacy guarantee that documents never leave the phone.

## Scope

**Supported now (on-device, private)**
- `image → PDF`
- `PDF → JPG` (export each page, or all pages, as images)

**Deferred (dropped for now)**
- `PDF ↔ Word / Excel / PPT` (Office formats, both directions). High-fidelity
  Office conversion realistically needs a server (off-device) and conflicts with
  the privacy posture. Revisitable later as an **opt-in hybrid** behind the same
  `Converter` interface, with no rework to on-device conversions.

## Privacy & DRY

- Nothing leaves the device.
- Every converted file passes through the shared **metadata scrubber**.

## Architecture (SOLID/KISS/DRY)

- Conversions sit behind a `Converter` interface (DIP); a future opt-in backend
  converter could plug in without touching on-device paths.
- Runs off the UI thread.

## Boundary

- **Producing** a PDF → Feature 07. **Converting** PDF<->image → Feature 10.
- **Sharing/printing** the result → Feature 12.

## Testing strategy (TDD/BDD first)

- **Unit:** image→PDF produces a valid one-page PDF; PDF→JPG yields one image per
  page; outputs are metadata-scrubbed.
- **BDD scenarios:**
  - *Given an image, when I convert to PDF, then a one-page PDF is produced and
    metadata-scrubbed.*
  - *Given a multi-page PDF, when I convert to JPG, then I get one image per
    page.*
  - *Given any conversion, then no data leaves the device.*

## Acceptance criteria

1. User can convert an image to a PDF on-device.
2. User can convert a PDF to per-page JPGs on-device.
3. All converted files are metadata-scrubbed; nothing leaves the device.
4. Conversions sit behind a `Converter` interface for future extension.
5. All logic test-first; BDD scenarios pass.
