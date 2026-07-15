# P15 — Hygiene: theme tokens, i18n date, lints, pins

**Tier 5 (Hygiene) · Effort S–M · Risk Low · Depends on: none · Device verification: host + Android + iOS (both available)**

Companion to `00-overview-and-comparison.md` and `01-roadmap.md`. This plan cleans up four
independent hygiene fronts: hardcoded colors/typography that bypass the Ream theme tokens; a visible
i18n date regression (grid card shows hardcoded English months); a bare-minimum lint config; and
loose dependency pins. No behaviour change beyond fixing the grid-date localization.

> **Scope note:** the `kSlot` magic-number cleanup is owned by **P13 (layout)** — this plan does
> **not** touch it. P15 covers colors/typography, date localization, lints, and pins only.

---

## Summary

The Ream design system (`ReamColors`, `ReamTypography`, `context.ream`) is defined but bypassed in a
handful of spots. There are only **4** non-theme `Color(0x…)` sites and **33** `Colors.*` usages and
**36** `TextStyle(` constructions that don't route through the tokens. The other 36 `Color(0x…)`
matches are the legitimate token definitions in `lib/theme/ream_colors.dart` — those stay.

Separately, the same document renders **different dates** in the list vs the grid: the list uses an
ISO numeric `DateFormat` while the grid card uses a **hardcoded English `months[]` array**, so the
grid date is unlocalized despite the app's 11-language i18n — a visible regression.

The lint config is `flutter_lints` only (rules block commented out), so intent like the 12
`unawaited(` call sites isn't enforced. And `intl: any` is fully unpinned while `opencv_dart` is
correctly pinned exactly to `2.1.0` (must be preserved — `2.2.x` builds from source, 5–8× slower).

Everything here is **behaviour-preserving** except the deliberate grid-date localization fix. Token
swaps must be pixel-equivalent (map each hardcoded value to the token that already equals it). Lint
tightening will surface **existing** warnings that must be fixed to keep the zero-warning bar.

---

## Verified findings

| ID | Current location | What's wrong | Impact | Live/latent |
|---|---|---|---|---|
| **theme-token-bypass** | Non-theme `Color(0x…)`: `page_viewer_screen.dart:739` `Color(0x99000000)`, `document_grid_card.dart:55` `Color(0x14000000)`, `feedback_screen.dart:274` `Color(0xFF201C16)`, `ream_action_button.dart:31`. `Colors.*` = **33** (worst: `capture_review_screen` 6, `crop_overlay` 4, `filter_picker_strip` 3). `TextStyle(` = **36** across 18 files (worst tie: `sort_pill` 5, `feedback_screen` 5; `donation` 4). The other 36 `Color(0x` are legit defs in `lib/theme/ream_colors.dart`. | Hardcoded colors/typography bypass `ReamColors`/`ReamTypography`/`context.ream` | Theme (esp. dark/warm-paper) doesn't apply uniformly; drift from tokens | **live** |
| **dup-date-format** | `documents_list_view.dart` `_formatLocal:166-170` (createdAt, ISO numeric Y-M-D HH:MM) vs `document_grid_card.dart` `_formatDate:127-143` (modifiedAt, **hardcoded English `months[]`**) | Two date formatters; grid isn't localized despite 11-lang i18n; also list shows createdAt, grid shows modifiedAt | Same doc shows different dates list vs grid; grid is a visible **i18n regression** | **live** |
| **analysis-options-minimal** | `analysis_options.yaml` — only `include: package:flutter_lints/flutter.yaml`, rules block commented out | No `unawaited_futures` etc.; the 12 `unawaited(` usages in `lib/` show intent that's unenforced | Async-safety/style conventions not enforced by the linter | **latent** |
| **pubspec-loose-pins** | `pubspec.yaml`: `intl: any` (:35) fully unpinned. `opencv_dart` exactly `2.1.0` (:43, correct). PDF stacks: `pdf ^3.11.1` (:48), `printing ^5.13.0` (:49), `pdfx ^2.9.0` (:50), `syncfusion_flutter_pdf ^33.2.15` (:55, only for AES-encrypted export) | `intl: any` can float to a breaking version; syncfusion is a heavy dep for one feature (trade-off to document) | A silent `intl` bump could break date/number formatting; no unused deps found | **latent** |

---

## Definition of done

- The **4** non-theme `Color(0x…)` sites, the **33** `Colors.*` usages, and the **36** `TextStyle(`
  constructions in `lib/features` are mapped to `ReamColors`/`ReamTypography`/`context.ream` (or a new
  `ReamTypography` size helper) with **pixel-equivalent** output. The 36 legit `Color(0x…)`
  definitions in `lib/theme/ream_colors.dart` are untouched.
- A grep/lint guard exists (or is documented) against new `Colors.` / raw `TextStyle(` in
  `lib/features`.
- List and grid render the **same** date for a given document via one locale-aware `intl`
  `DateFormat`; the timestamp shown (createdAt vs modifiedAt) is agreed and consistent; the grid date
  is localized (regression fixed) and verified across at least two locales.
- `analysis_options.yaml` enables `unawaited_futures` + a few strictness rules; all newly-surfaced
  warnings are fixed to keep the **zero-warning** bar; `custom_lint` for timeout/token conventions is
  evaluated (adopt or explicitly defer).
- `pubspec.yaml`: `intl` pinned to a caret range; `opencv_dart` **preserved at exactly `2.1.0`**; the
  syncfusion single-feature trade-off is documented (no action required); PDF stack pins reviewed.
- **TDD** failing-first where testable (date formatter, lint-guard). **BDD** + all host tests stay
  green. **Device**: theme + localized-date render verified on real Android **and** iOS.

---

## Before → After

| Concern | Before | After |
|---|---|---|
| Hardcoded colors | 4 non-theme `Color(0x…)` + 33 `Colors.*` | Mapped to `ReamColors`/`context.ream`, pixel-equivalent |
| Typography | 36 raw `TextStyle(` across 18 files | `ReamTypography` (+ size helpers) |
| Token guard | None | grep/lint guard against `Colors.` / `TextStyle(` in `lib/features` |
| Date in list vs grid | ISO numeric (list, createdAt) vs hardcoded English months (grid, modifiedAt) | One locale-aware `intl` `DateFormat`, same timestamp, both localized |
| Lint config | `flutter_lints` only, rules commented out | `unawaited_futures` + strictness rules; zero-warning bar held |
| `intl` pin | `intl: any` | Pinned caret range |
| `opencv_dart` | exactly `2.1.0` | Preserved exactly `2.1.0` |
| syncfusion | Heavy, one feature, undocumented | Trade-off documented (kept) |

---

## Tasks

Independent, subagent-ready. Write the failing test/guard first where applicable, then the change.
Token-swap tasks are partitioned by file so they run in parallel without collisions.

### Task 1 — Map the 4 non-theme `Color(0x…)` sites to tokens (theme-token-bypass)
- **Scope**: `page_viewer_screen.dart:739` (`Color(0x99000000)`), `document_grid_card.dart:55`
  (`Color(0x14000000)`), `feedback_screen.dart:274` (`Color(0xFF201C16)`), `ream_action_button.dart:31`
  → the equivalent `ReamColors`/`context.ream` token (add a token if one doesn't already equal it).
- **Files**: those 4 files (+ maybe `ream_colors.dart` for a new named token).
- **Test-first**: golden/widget assertion that the rendered color is unchanged (pixel-equivalent).
- **Done**: no non-theme `Color(0x…)` outside `lib/theme/`; visual parity.
- **Parallel-safe**: yes.

### Task 2 — Replace `Colors.*` usages (33) with tokens (theme-token-bypass)
- **Scope**: Replace the 33 `Colors.*` usages, worst offenders `capture_review_screen` (6),
  `crop_overlay` (4), `filter_picker_strip` (3), with `ReamColors`/`context.ream` equivalents.
- **Files**: the ~files containing `Colors.*` in `lib/features`.
- **Test-first**: `capture_review_screen_test.dart` (510 LOC) stays green; add a color-parity check
  where a golden exists.
- **Done**: no `Colors.*` in `lib/features` (or documented exceptions); visual parity.
- **Parallel-safe**: yes — can split per-file across subagents.

### Task 3 — Route `TextStyle(` (36 across 18 files) through `ReamTypography` (theme-token-bypass)
- **Scope**: Replace raw `TextStyle(` constructions (worst: `sort_pill` 5, `feedback_screen` 5,
  `donation` 4) with `ReamTypography`; add `ReamTypography` size helpers where a one-off size is
  needed.
- **Files**: the 18 files; `ream_typography.dart` for new helpers.
- **Test-first**: widget test that text style (size/weight) is unchanged for a sampled widget.
- **Done**: raw `TextStyle(` removed from `lib/features` (or documented); parity held.
- **Parallel-safe**: yes — split per-file.

### Task 4 — Add a token-bypass guard (theme-token-bypass)
- **Scope**: A grep/lint guard (CI script or `custom_lint` rule) failing on new `Colors.` or raw
  `TextStyle(` in `lib/features`.
- **Files**: `scripts/` (grep guard) and/or lint config.
- **Test-first**: the guard flags a deliberately-added `Colors.red`, then passes once removed.
- **Done**: guard runs in the test/lint pipeline; documented.
- **Parallel-safe**: yes (depends on Tasks 1–3 having cleaned existing hits, or ships allow-listed).

### Task 5 — Unify localized date formatting (dup-date-format)
- **Scope**: Replace `documents_list_view._formatLocal:166-170` and
  `document_grid_card._formatDate:127-143` (hardcoded English `months[]`) with **one** locale-aware
  `intl` `DateFormat`. Agree which timestamp to show (createdAt vs modifiedAt) and use it consistently
  in both views.
- **Files**: new/shared date-format helper; `documents_list_view.dart`, `document_grid_card.dart`.
- **Test-first**: unit test asserting the same document yields the same, localized string in both
  views across ≥2 locales (e.g. `en`, `de`); the grid no longer emits hardcoded English months.
- **Done**: list and grid dates match and are localized; i18n regression closed.
- **Parallel-safe**: yes (self-contained).

### Task 6 — Tighten lints (analysis-options-minimal)
- **Scope**: Enable `unawaited_futures` + a few strictness rules in `analysis_options.yaml`; fix every
  newly-surfaced warning (12 `unawaited(` sites already show intent) to hold the zero-warning bar;
  evaluate `custom_lint` for timeout/token conventions (adopt or explicitly defer with a note).
- **Files**: `analysis_options.yaml` (+ whatever files the new rules flag).
- **Test-first**: run `flutter analyze`, capture the new warnings as the failing baseline, fix to
  zero.
- **Done**: `flutter analyze` clean under the tightened rules.
- **Parallel-safe**: partial — the fix set touches many files; do the rule enable + fixes as one
  coordinated task, or split the fixes per-file after the rules land.

### Task 7 — Pin `intl`, preserve `opencv_dart`, document PDF trade-off (pubspec-loose-pins)
- **Scope**: `pubspec.yaml:35` `intl: any` → a caret range matching the resolved version. Leave
  `opencv_dart` exactly `2.1.0` (:43) — add a comment noting `2.2.x` builds from source (5–8× slower).
  Review `pdf`/`printing`/`pdfx`/`syncfusion_flutter_pdf` pins; document that syncfusion is heavy for
  its single AES-encrypted-export use (no removal). No unused deps found.
- **Files**: `pubspec.yaml`, `pubspec.lock`.
- **Test-first**: `flutter pub get` resolves; the full host suite stays green under the pinned `intl`
  (date/number formatting unchanged).
- **Done**: `intl` pinned; `opencv_dart` unchanged; trade-off documented; suite green.
- **Parallel-safe**: yes (isolated; but re-run after Task 5 if it changes `intl` usage).

---

## Risks & mitigations

- **Color/typography swap changes pixels** — a mismatched token silently restyles UI. *Mitigation*:
  map each hardcoded value to the token that **already equals it**; assert pixel-equivalence via
  golden/widget tests; verify theme on device (both platforms), including dark/warm-paper.
- **Date-format change shifts the displayed timestamp** — switching createdAt↔modifiedAt or format is
  user-visible. *Mitigation*: agree the timestamp explicitly, cover with a cross-locale unit test, and
  eyeball on device.
- **Lint tightening floods warnings** — `unawaited_futures` may flag many `Future`s. *Mitigation*:
  scope the rule set narrowly first; fix all surfaced warnings before merging so the zero-warning bar
  holds; defer `custom_lint` if it balloons.
- **`intl` pin breaks a transitive constraint** — pinning could conflict with `flutter_localizations`.
  *Mitigation*: pin to the already-resolved version's caret range; re-run `flutter pub get` and the
  full suite.
- **`opencv_dart` accidental bump** — a careless `pub upgrade` could move off `2.1.0`. *Mitigation*:
  keep the exact pin + explanatory comment; note it in the PR description.

---

## Verification commands

Run from `apps/mobile/`.

```bash
# Token-bypass audit (should trend to zero in lib/features)
rg -n 'Colors\.' lib/features | wc -l
rg -n 'TextStyle\(' lib/features | wc -l
rg -n 'Color\(0x' lib/features            # non-theme sites only; theme defs live in lib/theme/

# TDD — date formatter + guards (host)
flutter test test/features/library/       # list/grid date parity across locales
flutter test test/features/scan/capture_review_screen_test.dart   # 510 LOC, stays green
flutter test test/                        # full host suite incl test/bdd

# Lint / format (tightened rules; zero-warning bar)
flutter analyze
dart format --output=none --set-exit-if-changed lib test

# Pins
flutter pub get                           # resolves under pinned intl; opencv_dart stays 2.1.0

# Device — theme + localized date render (BOTH platforms)
flutter test integration_test/theme_and_date_device_test.dart -d <android-device-id>
flutter test integration_test/theme_and_date_device_test.dart -d <ios-device-id>
```

Verify theme tokens and the localized grid/list date on a real Android device **and** a real iOS
device before claiming done; record the green run per the verify-then-claim rule.
