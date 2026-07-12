# Ream Phase 2 — remaining screen re-skins (04, 07, 08, 09, 10)

**Date:** 2026-07-12
**Status:** design, pending user review
**Depends on:** Ream design system + Library (Phase 1, shipped), Ream document editor
(Phase 2a, shipped `5781c3e`).

## Goal

Apply the **Ream** visual language to the five app screens that Phase 1/2a did not
touch, so the whole app reads as one designed product. This is a **pure re-skin**:
no behavior, logic, wiring, or callback changes. Every existing test keeps passing;
each screen's controls, actions, and semantics are unchanged — only the visual
structure (colors, type, spacing, chrome) moves to Ream.

Reference (single source of truth): `docs/design/ream/README.md` and the screen
anchors in `docs/design/ream/Ream Scanner.dc.html`. Do **not** re-fetch from the
network.

## Scope

In scope — five screens:

| # | Screen | File(s) | Theme |
|---|--------|---------|-------|
| 07 | Recognized text (OCR) | `lib/features/library/recognized_text_screen.dart` | Light |
| 08 | Export PDF | `lib/features/library/pdf_preview_screen.dart` | Light |
| 09 | Send feedback | `lib/features/feedback/feedback_screen.dart` | Light |
| 10 | Support / donation | `lib/features/donation/donation_screen.dart` | Light |
| 04 | Review & clean | `lib/features/library/edit_crop_screen.dart` | Dark, **chrome-only** |

Out of scope:
- `donation_banner.dart` — **already** on Ream (`context.ream`, `amberSoft/amber/ink2`). Leave it.
- Capture / ID-card screens (03, 05) — OS scanner owns them.
- Screen 04 **crop-canvas interaction** (`CropOverlay` gesture/corner-drag logic) —
  chrome-only means we restyle background, header bar, confidence chip, filter strip,
  and footer buttons, but do **not** touch the interactive canvas's gesture code.
  Restyling the handle *colors* is allowed only if it is a trivial constant swap that
  does not alter hit-testing; otherwise leave the canvas as-is and note it.
- Any change to `DonationConfig`, `FeedbackService`, OCR, PDF generation, share/print
  plumbing, or the `*Dependencies` DI classes.

## Design language (recap — authoritative values in `docs/design/ream/README.md`)

- **Access idiom:** `final r = context.ream;` at build scope, then `r.paper`, `r.ink`,
  etc. No `ReamColors` import needed in screen files (the extension self-provides and
  falls back to `ReamColors.light` under bare widget tests).
- **Type:** Figtree for UI (titles 800, tracking -0.02em); IBM Plex Mono for technical
  readouts and the caps section-labels (`QUALITY`, `TYPE`, `MESSAGE`, `EMAIL`, page
  counts, IDs).
- **18 color tokens** available on `ReamColors` (see README table): `paper, surface,
  surface2, ink, ink2, muted, line, line2, appBg, green, greenDeep, greenSoft, amber,
  amberSoft, blue, blueSoft, kofiRed, deleteRed`.
- Confidence semantics: green = success/ready, amber = verify/optional, blue = info.

## Reuse — build on existing widgets, do not re-create

Confirmed present:
- `lib/theme/widgets/confidence_chip.dart` — the green "ready" pill (07, 04).
- `lib/theme/widgets/ream_action_button.dart` — footer buttons (verify it exposes the
  fill variants each screen needs: surface/outline, ink, green-deep; if a variant is
  missing, extend this widget rather than inlining a new button).
- `lib/theme/widgets/ream_segmented.dart` — the segmented control (09 TYPE toggle).
- `lib/features/library/widgets/editor_top_bar.dart` and the editor's dark idiom —
  reference for screen 04's dark header.

New **shared** widgets (create once in `lib/theme/widgets/`, reuse across screens) —
these exist specifically so parallel subagents don't each invent a divergent version:
- **`ream_back_header.dart`** — the light back-header (leading chevron, centered Figtree
  700 title, trailing spacer for symmetry). Used by **all four light screens (07, 08, 09,
  10)**. Without this shared widget, four subagents produce four subtly different headers.
  Takes a title `String` and an `onBack` callback (default `Navigator.maybePop`).
- **`ream_section_label.dart`** — a mono, muted, letter-spaced caps label (`QUALITY`,
  `TYPE`, `MESSAGE`, `EMAIL — optional…`). Used by 08 + 09.

A new button fill (green-deep primary for 08, ink primary for 09) should be a **variant
of `ream_action_button`**, not a bespoke inline container, unless the widget's API makes
that materially harder — in which case note it in the task's review.

## Per-screen design

### 07 — Recognized text (OCR) · light
- `Scaffold` bg `r.paper`; Ream back-header (chevron + centered "Recognized text",
  Figtree 700). Replace the Material `AppBar` with the Ream header treatment used by the
  other light screens (match Library/editor header spacing).
- Below header: green **confidence_chip** "Text layer ready · powers search" (mono
  micro-label inside), shown when a text layer exists (reuse existing "has OCR" state —
  do not add new state).
- Body: existing `SelectableText`, restyled — Figtree 400/13, `r.ink2`, line-height 1.7;
  keep selectability and the existing recognize/copy actions intact.
- Footer: two `ream_action_button`s — **Copy text** (surface + `r.line` border, `r.ink`)
  and **Share .txt** (ink fill, surface text). Wire to the *existing* copy/share
  callbacks; do not change what they do.

### 08 — Export PDF · light
- `Scaffold` bg `r.paper`; Ream back-header "Export as PDF".
- Keep the `PdfViewPinch` preview OR the design's static preview card — **preserve the
  current preview behavior**; only restyle its frame/badge (mono "N pp" badge, `r.ink`
  chip). Do not swap the pdfx viewer for a fake.
- `QUALITY` mono section-label; the existing quality options rendered as Ream radio rows
  (selected = `greenSoft` bg + `green` border + check; unselected = `surface` + `line`).
  Bind to the **existing** quality state/enum — no new options.
- Password-protect toggle restyled (keep the existing toggle wiring).
- Primary **Preview & share PDF** = green-deep `ream_action_button`; wire to existing
  `ShareMenuButton`/share action.

### 09 — Send feedback · light
- `Scaffold` bg `r.paper`; Ream back-header "Send feedback".
- `TYPE` section-label + **ream_segmented** (Bug / Idea / Question) bound to the existing
  category value (currently a `DropdownButtonFormField` — replace the *control* with the
  segmented widget but keep the same underlying form field / value + validation).
- `MESSAGE` label + restyled multiline `TextFormField` (surface, `r.line`, Figtree).
- `EMAIL — optional` label + restyled `TextFormField`; drop the `Colors.grey` helper for
  `r.muted`.
- Blue "What we include" disclosure card (`blueSoft` bg, blue dot, existing diagnostics
  copy). `TurnstileWidget` stays exactly as wired (device-only).
- Primary **Send report** = ink `ream_action_button`; wire to existing submit.

### 10 — Support / donation · light
- `Scaffold` bg `r.paper`; Ream back-header "Support Ream".
- Centered ♥ + headline "No accounts. No cloud. No subscription." (Figtree 800) +
  body (`r.ink2`). Replace `Colors.amber.shade700` heart with `r.amber`/`r.kofiRed` per
  design.
- Amber honest-disclaimer card (`amberSoft`, existing "unlocks nothing" copy).
- **Ko-fi** button = `kofiRed` fill (keep existing launch wiring / `DonationConfig`).
- Bitcoin card (`surface`, `line`): QR (`Colors.white` → keep white *only inside the QR
  quiet-zone*, which QR needs; frame it in Ream), mono truncated address + green-deep
  "copy" (keep existing copy-to-clipboard action).

### 04 — Review & clean · dark, **chrome-only**
- `Scaffold`/body bg → dark editor tone (`#201c16`-family; reuse the editor's dark
  constant, do not invent a new one). Replace `Colors.black`/`Colors.white54`.
- Dark header bar (Retake / Review / Save) — match editor idiom; keep existing button
  callbacks.
- Green **confidence_chip** (dark variant) "High confidence — corners look right", driven
  by existing detector confidence state if present; if the screen has no such state,
  render the static "Review" affordance and note the gap — **do not** add detection logic.
- Filter strip + footer (Add page / Save document) restyled to dark; keep wiring.
- **Do not touch** `CropOverlay` gesture/hit-testing. Handle-color constant swap only if
  trivial and non-behavioral.

## Testing (per CLAUDE.md — TDD, verify-then-claim)

Per screen:
1. **TDD (host, required):** write/adjust a failing widget test first that asserts the
   Ream structure — e.g. background resolves to `context.ream.paper` (light) or the dark
   tone (04), the Ream header/title is present, the confidence chip / segmented / section
   labels render, and the footer buttons carry their existing keys/labels. Then implement
   to green.
2. **Preserve existing tests:** every current unit/feature/step test for the screen must
   stay green with **no semantic change** to its expectations. If a re-skin forces a
   finder change (e.g. a Material `AppBar` title finder → the Ream header), update the
   finder minimally and note it; never weaken an assertion.
3. **BDD:** these are pure re-skins of already-shipped behavior. Existing `.feature`
   files (04 `e1_crop`, 07 `o4_recognized_text`, 08 `c2_pdf_preview`, 10 via
   `s1_donation_banner`) continue to cover behavior — **no new `.feature` required** for
   the visual change. `feedback_screen` and `donation_screen` have no feature file today;
   we do **not** add one for a re-skin (no new behavior). If any behavior *did* change,
   that would be out of scope — stop and flag it.
4. **Both platforms:** the re-skins are pure Flutter widget code (no new native calls),
   so host widget tests + `flutter analyze` (zero warnings) + `dart format` are the gate.
   On-device is a **named, accepted gap** for pure-visual changes: we will do one
   combined install + eyeball pass on the real Android device at the end of the batch
   (iOS remains sim-only per project constraints). No screen introduces native-dependent
   behavior, so this gap is explicit and bounded.

## Execution structure

- **One spec (this file) → one plan → parallel subagents**, one subagent per screen.
  The five screen files are independent; the only shared surface is the optional
  `ream_section_label` widget.
- **Sequencing:** the shared widgets (`ream_back_header`, `ream_section_label`, any
  `ream_action_button` variant) are **task 0** — created + tested + merged *before* the
  parallel screen tasks start, so all screens build on stable shared code. Since
  `ream_back_header` is used by all four light screens, this task-0 barrier is required,
  not optional. Only screen 04 (dark, its own header idiom) is independent of it.
- Each subagent: TDD order, scoped `git add` (named paths only, never `-A` — the repo
  carries a long-lived WIP pile), `flutter analyze` clean, `dart format`, paste the
  FAIL→PASS evidence, then task review before the next.
- Final whole-branch review + one combined Android install/eyeball pass.

## Definition of done (whole batch)

1. All five screens visually match their `.dc.html` anchors (warm-paper light; dark for 04).
2. `flutter test` green except the 2 known opencv-env failures; `flutter analyze` zero
   warnings; `dart format lib test` clean.
3. No behavior/logic/wiring/DI change; all pre-existing tests green with only minimal,
   noted finder updates.
4. Combined Android install eyeball pass done; iOS = named sim/gap.
5. Branch reviewed and merged to master.
