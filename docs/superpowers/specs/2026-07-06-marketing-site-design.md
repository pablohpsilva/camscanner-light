# ScannerCam Light — Marketing / Support / Privacy Site

**Date:** 2026-07-06
**Status:** Approved (design)

## Goal

A static GitHub Pages website to serve as the **marketing landing page** and the
**mandatory App Store / Play Store support & privacy URLs** for ScannerCam Light.
It must look premium and privacy-first, and it must use **real screenshots**
captured from the running app.

## Constraints & Decisions

- **Location:** new folder `apps/web/`, isolated from the Flutter app in
  `apps/mobile/`. Does not touch the mobile app or its build.
- **Tech:** plain static **HTML + CSS + minimal vanilla JS**. No framework, no
  Node build step, no dependencies. GitHub Pages serves the folder directly.
  Rationale: it's a 3-page brochure site — a build pipeline adds fragility for
  no benefit (KISS).
- **Visual direction:** "Clean & trustworthy" — light/white, spacious,
  Apple-store-like, device-framed screenshots, soft shadows, single accent color.
- **Screenshots:** captured from the physical Android device `RZCY51D0T1K`
  (SM A166B). The iOS simulator cannot run this app on Apple Silicon
  (pdfx/MLKit/opencv arm64-sim gaps), so Android is the capture source. Screens
  are visually equivalent for marketing. User curates the captured batch.
- **Store links:** "Coming soon" buttons (no live store URLs yet).
- **Support email:** `scannercamlight.line149@passmail.net`.

## Verified Facts (basis for privacy claims)

Confirmed by inspecting `apps/mobile`:

- **No `INTERNET` permission** in `android/app/src/main/AndroidManifest.xml`.
- No analytics / Firebase / Sentry / HTTP client dependencies in `pubspec.yaml`.
- Only outbound-capable packages: `url_launcher` (opens an external Ko-fi
  donation link only when the user taps it) and `share_plus` (system share
  sheet, user-initiated).
- Image bytes stored on-device on disk (`DocumentFileStore`); metadata in local
  Drift/SQLite DB. OCR is Google ML Kit (on-device). OpenCV via FFI (local).

→ Marketing/privacy spine: **100% on-device, no account, no cloud, works
offline, no data collection.** This is literally true and verifiable.

## Design System

- **Colors** (from app icon): `--accent:#2E7DFF` (brand blue),
  `--ink:#1A2238` (navy), `--bg:#FFFFFF`, `--surface:#F5F8FC`,
  `--muted:#5B6478`.
- **Type:** system font stack (`-apple-system, "Segoe UI", Roboto, sans-serif`).
  No web-font downloads.
- **Components:** rounded device-frame mockups (CSS) around real screenshots,
  soft shadows, generous whitespace, single accent, mobile-first responsive.

## File Structure

```
apps/web/
  index.html          landing (marketing)
  support.html        support / FAQ / contact
  privacy.html        privacy policy
  styles.css          shared design system
  main.js             nav toggle, screenshot lightbox, smooth scroll
  assets/
    icon.png          app icon (copied from apps/mobile branding)
    screenshots/      real device captures (raw + chosen)
  README.md           run locally + publish on GitHub Pages
```

`.nojekyll` file included so GitHub Pages serves assets without Jekyll
processing.

## Pages

### index.html (landing)
1. **Sticky nav** — icon + "ScannerCam Light"; links Features / Privacy /
   Support; "Get the app" button.
2. **Hero** — headline ("Scan. Clean. Done."), subhead (on-device, free), two
   store badges (App Store / Google Play) rendered as "Coming soon" buttons, a
   framed hero screenshot.
3. **Feature grid** — 6 cards from real capabilities:
   - Automatic edge detection & crop
   - Perspective correction & auto enhance
   - Multi-page documents
   - Full-text OCR search (FTS5)
   - PDF export & share
   - Reorder, rotate, re-crop pages
4. **Screenshot gallery** — 4–6 framed real screenshots, click-to-enlarge
   lightbox.
5. **Privacy band** — the verified story + 4 checkmarks (On-device / No account
   / Offline / Free).
6. **Support/donate CTA + footer** — links to privacy & support, Ko-fi mention,
   copyright.

### support.html
Short intro + FAQ (offline? where are files stored? how to export a PDF? is it
free? how to free up space?) + contact:
`scannercamlight.line149@passmail.net`.

### privacy.html
Honest, specific policy from the verified facts: no data collected, no network
access, images stored locally, OCR on-device, donation opens an external link,
sharing is user-initiated. Plain English + effective date (2026-07-06).

## Screenshot Capture Plan

Drive `RZCY51D0T1K`:
1. Seed 1–2 presentable sample documents in the app.
2. Capture ~6 screens via `adb exec-out screencap -p`:
   camera + edge overlay, capture review, library grid, page viewer, OCR/search,
   PDF export/share.
3. Present the batch; user curates.
4. Frame chosen shots in CSS device mockups; keep raw PNGs in
   `assets/screenshots/`.

## Testing / Verification

This is a static brochure site outside the Flutter app, so the mobile app's
TDD/BDD gate does not apply. Verification instead:
- All three pages render correctly (open via Playwright; screenshot desktop +
  mobile widths and show the user).
- All internal links resolve.
- No external network requests (works fully offline).
- Basic HTML sanity (well-formed, no broken asset paths).

## Out of Scope

- No custom domain / CNAME now (can add later).
- No live store URLs (buttons say "Coming soon").
- No blog, changelog, or i18n.
- No changes to the Flutter app.
