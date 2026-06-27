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

## Acceptance criteria

1. User can share a PDF/JPG via the system share sheet (email/social/messaging).
2. User can wirelessly print a PDF.
3. Shared/printed files are metadata-scrubbed.
4. Link-share and fax sit behind a `ShareChannel`/`FaxProvider` interface for
   later, without disturbing on-device channels.
5. All logic test-first; BDD scenarios pass.
