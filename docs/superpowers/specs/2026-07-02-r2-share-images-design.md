# R2 — Share images + close Feature 12 (design)

**Date:** 2026-07-02
**Status:** Approved (design)
**Sub-project:** 6 — Sharing, printing & fax (Feature 12, "sharing" — JPG)
**Depends on:** R1 (`ShareChannel` seam), I1/J1 (image export), Q1 (export-quality + compress/scrub pipeline).
**Reuses:** R1's `ShareChannel` / `SystemShareChannel` / `FakeShareChannel` (DRY — no seam change).

## Purpose

Complete Feature 12's "Share a PDF/**JPG** via the system share sheet" criterion.
R1 delivered PDF sharing behind a `ShareChannel` seam. R2 routes the two
image-export flows through that same seam so a page (or all pages) can be shared
as JPG, and closes a re-entrancy gap on the library-list Share that R1's review
flagged.

## Problem being fixed

The image-export actions write scrubbed JPGs to **app-private storage**
(`documents/$docId/page_${position}_export.jpg`, inside the app documents dir)
and show a "Page saved as image" / "Exported N images" snackbar. That location
is not reachable via the system Files app or Photos — so today the "export" is a
dead end: the user cannot actually get the JPG off the device. The share sheet is
the delivery mechanism. R2 changes both actions from *save-to-nowhere* to
*export → share*.

Separately, R1's `HomeScreen._shareDocument` has no re-entrancy guard, so
double-tapping Share on a large document can launch overlapping `exportPdf` runs.

## Scope

- **In:** route `_exportPageAsImage` and `_exportAllImages` through `ShareChannel`;
  add a re-entrancy guard to `_shareDocument`; update the affected tests + the
  shared image-export BDD step; close Feature 12.
- **Out:** save-to-Photos/gallery (different mechanism + permissions, not what
  Feature 12 specifies); link-share and fax (remain deferred behind the
  interface); any `ShareChannel` signature change.

## Changes

### 1. Image-export actions → share (`page_viewer_screen.dart`)

- `_exportPageAsImage`: after `exportPageAsImage(documentId, position, quality:)`
  returns the scrubbed `File`, call
  `widget.share.share([file.path], subject: _name)`.
- `_exportAllImages`: after `exportAllPagesAsImages(documentId, quality:)` returns
  `List<File>`, call `widget.share.share(files.map((f) => f.path).toList(),
  subject: _name)` — **one** share sheet with all N JPGs (no zip).
- Both keep the existing `showExportQualityDialog` first (Q1) and the existing
  `_exporting` flag (which already guards re-entry) with a `finally` reset.
- **Menu keys/values unchanged** (`page-viewer-export-image` / `export-image`,
  `page-viewer-export-all-images` / `export-all-images`) to avoid needless test
  churn; only the visible **labels** change to "Share page as image" / "Share all
  as images".
- **Feedback:** consistent with R1 — the OS share sheet is the success feedback,
  so **no success snackbar**. On failure: "Couldn't share image" (single) /
  "Couldn't share images" (all). The scrub already happened in the export
  pipeline (Q1); the channel does not re-scrub (DRY, trust-upstream).

### 2. Library-list Share re-entrancy guard (`home_screen.dart`)

- Add `bool _sharing = false` to `_HomeScreenState`. `_shareDocument` returns
  early if `_sharing` is already true; otherwise sets it, and resets it in a
  `finally`. No snackbar (chosen: minimal re-entrancy protection, not a progress
  indicator).

### 3. `ShareChannel` — unchanged

Already `share(List<String> filePaths, {String? subject})`; multi-file share is a
plain call. No seam change.

## Cross-cutting impact (must update)

Changing the export snackbars affects tests that assert the old "saved" strings:

- **Host widget tests:** `page_viewer_i1_test.dart`, `page_viewer_export_all_test.dart`,
  and `page_viewer_q1_test.dart` currently assert "Page saved as image" /
  "Exported N images". These are rewritten to inject a `FakeShareChannel` and
  assert the channel received the exported `.jpg` path(s) (and, on failure, the
  new "Couldn't share image(s)" snackbar).
- **Shared BDD step:** `test/step/i_see_the_image_export_confirmation.dart` asserts
  the old snackbar and is reused by the I1/J1/Q1 on-device scenarios. Since
  `tempLibraryDependencies()` already injects+records a `FakeShareChannel`
  (`lastBddShareChannel`, added in R1), this step is rewritten to assert the
  channel recorded a `.jpg` — mirroring R1's
  `the_document_is_handed_to_the_share_sheet`. All reusing scenarios then verify
  the new share behavior. (The generated `*_test.dart` for those features is
  regenerated if the step signature changes; keep the commit scoped.)

## Metadata scrub

Unchanged posture: `exportPageAsImage`/`exportAllPagesAsImages` already scrub EXIF
(I1/J1 + Q1). R2 shares that already-scrubbed output; no re-scrub. A test asserts
the shared file is the export-pipeline output.

## Testing strategy (TDD/BDD first)

- **Unit/widget:**
  - `_exportPageAsImage` → `FakeShareChannel` receives `[<.jpg path>]`,
    subject=name; `throwOnExportImage` → "Couldn't share image", channel not
    called, `_exporting` reset.
  - `_exportAllImages` → `FakeShareChannel` receives N `.jpg` paths; failure →
    "Couldn't share images".
  - Rewrite the three affected I1/J1/Q1 host tests to the share behavior.
  - `_shareDocument` re-entrancy: using `FakeDocumentRepository`'s existing
    `exportGate`, hold the first export in-flight, tap Share again, release the
    gate, assert exactly one export (`exportedIds.length == 1`) / `share.calls == 1`.
- **BDD (on-device Samsung `RZCY51D0T1K`):** scan → accept → Done → open the
  document → share the page as image → the channel received a `.jpg`.
- **On-device deterministic:** `exportPageAsImage` on device yields a valid JPEG
  (first bytes `0xFF 0xD8`), routed through a recording channel.
- **Verify script** `scripts/verify/r2.sh` (repo root), gated by the independent
  verifier; plans index R2 row; roadmap Feature 12 marked done.

## Deliverable (user-testable)

From the page viewer, "Share page as image" and "Share all as images" open the
system share sheet with the scrubbed JPG(s). **Test by** tapping each and
confirming the share sheet appears with the image(s); double-tapping library
Share does not launch two exports.

## Definition of Done

- Both image-export actions route through `ShareChannel`; labels updated; failure
  snackbars correct; `_exporting` guard retained.
- `_shareDocument` re-entrancy guard added.
- Affected host tests + the shared BDD step rewritten to the share behavior; full
  host suite green; `flutter analyze` clean.
- `.feature` BDD + on-device deterministic test green on `RZCY51D0T1K`.
- `scripts/verify/r2.sh` passes under the independent verifier; plans index R2 row
  added; **Feature 12 roadmap row marked done** (PDF via R1 + JPG via R2;
  link-share/fax remain deferred behind the interface).
