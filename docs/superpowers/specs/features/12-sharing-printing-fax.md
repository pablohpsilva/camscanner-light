# Feature 12 — Sharing, Printing & Fax

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 6 — Sharing, printing & fax
**Depends on:** Feature 07 (scrubbed PDF/exports)

## Purpose

Get documents out of the app: share, print, and (later) fax — consistent with the
on-device privacy posture.

## Scope

**In now (on-device, private, no backend)**
- **System share sheet:** share a PDF/JPG to any installed app (Mail, Messages,
  WhatsApp, Slack, social apps, etc.). Covers email + social sharing for free.
- **Wireless printing:** AirPrint (iOS) / Android print framework.

**Deferred (documented, behind interfaces)**
- **Share by link:** requires uploading to a server to mint a URL (off-device) —
  depends on the backend deferred in Feature 11.
- **Fax to 30+ countries:** requires a paid third-party fax provider (off-device,
  cost).

## Privacy & DRY

- Shared/printed files are the already metadata-scrubbed exports from Feature 07;
  sharing adds no metadata leak.

## Architecture (SOLID/KISS/DRY)

- Each outbound channel implements a small `ShareChannel` interface (OCP); a
  future `FaxProvider` / link-share channel slots in without modifying existing
  channels.

## Testing strategy (TDD/BDD first)

- **Unit/widget:** share invokes the OS share sheet with the correct file; print
  invokes the OS print dialog; shared files carry no personal metadata.
- **BDD scenarios:**
  - *Given a PDF, when I tap Share, then the system share sheet opens with that
    file.*
  - *Given a PDF, when I tap Print, then the OS print dialog opens for a wireless
    printer.*
  - *Given any shared file, then it carries no personal metadata.*

## Deliverable (user-testable)

**Share and Print actions**: share a PDF/JPG via the system share sheet, and
print via AirPrint / the Android print framework. **You can test it by** tapping
Share (the system share sheet opens with the file) and Print (the OS print dialog
opens for a wireless printer), and confirming the shared file carries no personal
metadata.

## Acceptance criteria (each closed only by a passing test)

- [ ] Share a PDF/JPG via the system share sheet (email/social/messaging) — *widget/BDD: share sheet opens with the file*
- [ ] Wirelessly print a PDF — *widget/BDD: print dialog opens*
- [ ] Shared/printed files are metadata-scrubbed — *unit*
- [ ] Link-share and fax sit behind a `ShareChannel`/`FaxProvider` interface, on-device channels undisturbed — *unit: interface*

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
