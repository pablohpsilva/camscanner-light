# Ream design — reference for implementers (humans & subagents)

This is the **single source of truth** for the Ream visual redesign. If you are a
subagent implementing any redesign task, read this file and the local design HTML
before writing code. Do not re-fetch from the network unless told to.

## Source of truth

- **Local design markup:** `docs/design/ream/Ream Scanner.dc.html` (committed copy
  of the Claude Design file — read the inline styles/markup for exact spacing,
  radii, weights). `support.js` is the Claude Design canvas runtime (only needed
  to *render* the `.dc.html` in a browser; not needed to read design intent).
- **Remote (for humans):**
  `https://claude.ai/design/p/b1f98d43-afb3-4442-9c2b-f8d1787c2cbc?file=Ream+Scanner.dc.html`
  Project id `b1f98d43-afb3-4442-9c2b-f8d1787c2cbc`. Re-read via the `DesignSync`
  tool (`get_file`) after `/design-login` — **only if** the local copy is missing.
- **Spec:** `docs/superpowers/specs/2026-07-10-ream-design-system-library-design.md`.
- **Direction:** use **1a "warm & clean" (light)**. 1b (dark HUD) is reference
  only, for the dark theme in the final phase. **Do not** implement capture/ID
  scan screens (03, 05, 1b capture) — the app uses the OS scanner.

## Color tokens (light) — use these exact values

Flutter's `Color` cannot parse `oklch`. The design's `:root` neutrals are hex
already; the confidence-trio oklch values are converted to sRGB below. These are
the **only** approved constants — put them in `ReamColors` and reference by name.

| Token         | Design value                | Flutter `Color` |
|---------------|-----------------------------|-----------------|
| `paper`       | `#f4f1ea`                   | `0xFFF4F1EA` |
| `surface`     | `#fffdf8`                   | `0xFFFFFDF8` |
| `surface2`    | `#faf7f0`                   | `0xFFFAF7F0` |
| `ink`         | `#33302a`                   | `0xFF33302A` |
| `ink2`        | `#5c574d`                   | `0xFF5C574D` |
| `muted`       | `#928c80`                   | `0xFF928C80` |
| `line`        | `#e6e1d6`                   | `0xFFE6E1D6` |
| `line2`       | `#efebe2`                   | `0xFFEFEBE2` |
| `appBg`       | `#e7e3d9` (behind paper)    | `0xFFE7E3D9` |
| `green`       | `oklch(0.66 0.13 150)`      | `0xFF4FA866` |
| `greenDeep`   | `oklch(0.52 0.115 150)`     | `0xFF2D7B44` |
| `greenSoft`   | `oklch(0.94 0.03 150)`      | `0xFFDEF1E1` |
| `amber`       | `oklch(0.70 0.13 78)`       | `0xFFCA932E` |
| `amberSoft`   | `oklch(0.95 0.045 82)`      | `0xFFFEECCD` |
| `blue`        | `oklch(0.66 0.12 245)`      | `0xFF4B99D7` |
| `blueSoft`    | `oklch(0.95 0.03 245)`      | `0xFFDFF1FF` |
| `kofiRed`     | `oklch(0.62 0.16 20)`       | `0xFFD5565D` |
| `deleteRed`   | `oklch(0.72 0.15 25)`       | `0xFFF47B74` |

Conversion is authoritative but ±1 in a channel is acceptable (gamma rounding).
Confidence semantics: **green = high confidence / success**, **amber =
verify / align**, **blue = informational**.

## Type

- **Figtree** — UI. Weights used: 400, 500, 600, 700, 800. Titles: 800, tracking
  `-0.02em`.
- **IBM Plex Mono** — technical readouts only (page counts, dates like
  `6 pages · Jul 8`, IDs, confidence numbers, section labels in caps).
- Bundle both as OFL `.ttf` under `fonts/` and declare in `pubspec.yaml`. Do not
  fetch fonts at runtime (app is offline/private).

## Screen index (anchors in the `.dc.html`)

| # | Screen (caption)            | Current Flutter file(s)                         | Phase |
|---|-----------------------------|-------------------------------------------------|-------|
| 01| Library — list              | `home_screen.dart`, `widgets/documents_list_view.dart` | 1 |
| 02| Library — grid (new)        | `home_screen.dart` (+ new `documents_grid_view.dart`)  | 1 |
| 04| Review & clean              | `edit_crop_screen.dart`                         | later |
| 06| Document editor             | `page_viewer_screen.dart`                       | later |
| 07| Recognized text (OCR)       | `recognized_text_screen.dart`                   | later |
| 08| Export PDF                  | `pdf_preview_screen.dart`                        | later |
| 09| Send feedback               | `feedback/feedback_screen.dart`                 | later |
| 10| Support (donation)          | `donation/donation_screen.dart`, `donation_banner.dart` | later |
| 03/05 | Capture / ID card       | OS scanner — **out of scope**                   | — |

## Definition of done (every redesign task)

Non-negotiable, from `CLAUDE.md`:

1. **TDD** — failing host test first, then implement to green.
2. **BDD** — user-facing behavior has a `.feature` in `integration_test/` with
   shared steps in `test/step/`; regenerate with
   `dart run build_runner build --delete-conflicting-outputs`.
3. **Both platforms** — native-dependent behavior proven on a **real Android AND
   a real iOS device** (`flutter test integration_test/<f>_test.dart -d <id>`),
   or an explicitly named gap.
4. **Verify, then claim** — paste the exact command + green result. No "should
   work". `flutter analyze` must be zero-warning; `dart format lib test`.
