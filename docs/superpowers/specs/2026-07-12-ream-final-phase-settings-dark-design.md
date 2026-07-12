# Ream Final Phase — Settings screen, dark-by-default, dark verification

**Date:** 2026-07-12
**Status:** design, pending user review
**Depends on:** Ream design system + Library (Phase 1), document editor (Phase 2a),
remaining screens (Phase 2, merged `626ed8d`).

## Goal

Close the Ream redesign's **final phase**: give the app a real, user-selectable
theme (Light / Dark / System) that **persists**, reached from a proper **Settings
screen**; make the app render correctly in **dark** on every in-scope screen (dark
is the **default**); fix the one user-facing "Ream" copy string; and finish the
carried deferred-minors polish — all under the non-negotiable TDD + BDD-on-both-
platforms gate.

"Ream" is the internal **design-system codename**, not the product name. The
product name in user-facing copy is **CamScanner-light**. No new user-facing text
may say "Ream".

## Decisions (locked with the user)

1. **Full Settings screen.** The home gear (`home-settings`) pushes a real
   `SettingsScreen` holding the theme selector + "Send feedback" + "Support the
   app" rows + an About footer. The current gear popup menu is replaced.
2. **Default theme = Dark.** New/unset users get dark. Dark must therefore be
   correct out of the box on every in-scope screen.
3. **Persistence = `shared_preferences`** (new dependency), behind a small store
   interface threaded through DI so host tests inject an in-memory fake.
4. **No `package_info_plus`.** The About footer shows the app name + a one-line
   privacy tagline, no runtime version number (avoids an unneeded dependency).
5. **Display name = "CamScanner-light"**; the donation entry/header reads
   **"Support the app"**.

## Scope

In scope:

| Area | Change |
|------|--------|
| Theme control | `ThemeModeStore` interface + `SharedPrefsThemeModeStore` + in-memory fake; `ThemeController` (ChangeNotifier); reactive `MaterialApp`; async `main()` load |
| Settings | New `lib/features/settings/settings_screen.dart` + `SettingsDependencies`; home gear pushes it |
| Dark verification | Audit + fix every in-scope light screen so it is correct under `ReamColors.dark` |
| Copy | `donation_screen` header `Support Ream` → `Support the app` |
| Polish | Carried deferred-minors (see below) |
| Regression | Full BDD integration suite on iOS sim + Android emulator, in dark **and** light |

Out of scope:
- **Scan feature** (`scan_screen`, `id_scan_screen`, `capture_review_screen`,
  `widgets/crop_overlay.dart`, `widgets/filter_picker_strip.dart`) — the OS
  document scanner owns this path; not re-themed. Its hardcoded `Colors.*` stay.
- PDF-generation colors (`ocr_pdf_text_layer.dart` `PdfColors.black`) — output
  document color, unrelated to app theme.
- The two already-dark screens (editor `page_viewer_screen`, `edit_crop_screen`)
  keep their locally-forced dark theme; they are unaffected by app theme mode.
  Their `Colors.black` scrims (`page_counter_pill`, `page_thumbnail_strip`) are
  intentional overlays on a dark canvas — verified, not changed.
- Any behavior change to OCR, PDF generation, share/print, FeedbackService,
  DonationConfig, or the drift schema.

## Architecture

### Theme control & persistence

```dart
// lib/theme/theme_mode_store.dart
abstract class ThemeModeStore {
  Future<ThemeMode?> load();      // null => never set => caller defaults to dark
  Future<void> save(ThemeMode mode);
}

class SharedPrefsThemeModeStore implements ThemeModeStore { /* key 'theme_mode' => 'light'|'dark'|'system' */ }
class InMemoryThemeModeStore implements ThemeModeStore { InMemoryThemeModeStore([ThemeMode? initial]); }
```

```dart
// lib/theme/theme_controller.dart
class ThemeController extends ChangeNotifier {
  ThemeController({required ThemeModeStore store, ThemeMode initial = ThemeMode.dark});
  ThemeMode get mode;
  Future<void> setMode(ThemeMode mode); // no-op if unchanged; else set + notifyListeners() + store.save(mode)
}
```

- **`main()` (async):** `WidgetsFlutterBinding.ensureInitialized()` → create
  `SharedPrefsThemeModeStore` → `final stored = await store.load()` → construct
  `ThemeController(store: store, initial: stored ?? ThemeMode.dark)` →
  `runCamScannerApp(themeController: controller)`. Loading before `runApp`
  avoids a first-frame light→dark flash.
- **`runCamScannerApp`** gains an optional `ThemeController? themeController`.
  When null (integration tests that don't inject one), it builds one from a
  `SharedPrefsThemeModeStore` defaulting to Dark. Existing Scan/Library/Feedback
  dependency params are unchanged.
- **`CamScannerApp`** takes the `ThemeController`, wraps `MaterialApp` in
  `AnimatedBuilder(animation: controller, builder: ...)`, sets
  `themeMode: controller.mode`. `theme`/`darkTheme` stay `ReamTheme.light()` /
  `ReamTheme.dark()`.

### DI

New `lib/features/settings/settings_dependencies.dart` — a const class with a
factory typedef `ThemeModeStore Function()` (default `SharedPrefsThemeModeStore.new`)
so tests inject `InMemoryThemeModeStore`. The `ThemeController` is app-level and
passed into `CamScannerApp`; the Settings screen receives the controller +
`FeedbackDependencies` + `Donation* ` wiring it needs to push the sub-screens
(reuse the existing dependency objects already held by `HomeScreen`).

### Settings screen

`lib/features/settings/settings_screen.dart` — renders under the active theme
(`final r = context.ream`), light-and-dark clean:

- `ReamBackHeader(title: 'Settings')`, back key default.
- `ReamSectionLabel('Appearance')` + `ReamSegmented<ThemeMode>` with options
  Light / Dark / System, key `Key('settings-theme-mode')`, value = `controller.mode`,
  onChanged → `controller.setMode(...)`.
- `ReamSectionLabel('Feedback & support')` + two tappable rows:
  - "Send feedback", key `Key('settings-feedback')` → push `FeedbackScreen`
    (only shown when feedback is available, mirroring today's `_feedbackAvailable`).
  - "Support the app", key `Key('settings-support')` → push `DonationScreen`.
- About footer: "CamScanner-light" (Figtree) + one-line tagline
  "Your scans stay on your device — no account, no cloud." (`r.muted`, mono/small),
  key `Key('settings-about')`. No version number.

### Home entry point

`_buildSettingsMenu` (a `PopupMenuButton`) is replaced by a tappable gear
(same visual container, key preserved `Key('home-settings')`) that pushes
`SettingsScreen`. The old `home-menu-feedback` popup item is removed; feedback is
now reached inside Settings. Home tests and `donation_banner_wiring_test` that
tapped the popup feedback item are updated to the new nav path (finder change
only — no weakened assertions).

## Dark verification (per in-scope light screen)

Because in-scope screens read `context.ream`, switching the app to dark flips the
palette automatically. Audit + fix, per screen, only these real risks:

- **Status bar:** under dark, `SystemUiOverlayStyle` must render **light** icons.
  Light screens that don't set it inherit the theme's default — verify on device;
  set `AnnotatedRegion`/`SystemUiOverlayStyle` per brightness where wrong.
- **Fixed whites:** donation QR quiet-zone stays `Colors.white` (QR requires it) —
  correct in dark; frame it so it doesn't float.
- **Thumbnails / images** on a dark `paper`: ensure a `r.line` border keeps light
  scanned pages from bleeding into dark chrome.
- **Contrast:** confidence chips, section labels, muted text remain legible on
  `ReamColors.dark` (tokens already tuned; assert, don't assume).

Screens to verify: **home/library** (`home_screen`), **OCR**
(`recognized_text_screen`), **feedback** (`feedback_screen`), **donation**
(`donation_screen`), **PDF viewer** (`pdf_preview_screen`), and the shared
widgets (`confidence_chip`, `ream_action_button`, `ream_search_field`,
`ream_segmented`, `ream_back_header`, `ream_section_label`).

## Deferred-minors polish (carried from Phases 1–2)

Fold into a single polish task; each is independently trivial:
- Widen `ream_colors_test` to assert all **18** tokens (light + dark).
- Resolve the test-location duplication (`test/theme/widgets/` vs
  `test/features/theme/`) — pick one, move, no orphan.
- Align list-row meta to "N pages · date" order (grid + design parity).
- Grid placeholder color → `r.muted`.
- `feedback` `_fieldDecoration`: differentiate `border` vs `enabledBorder` (or
  document why identical is intended).
- Private ctors on `ReamTypography` / `ReamTheme`.
- Clear the pre-existing 6 `flutter analyze` infos.

## Testing (per CLAUDE.md — TDD first, verify-then-claim, both platforms)

**Unit (host, TDD):**
- `ThemeController`: unset store → mode is Dark; `setMode(light)` updates mode,
  calls `notifyListeners`, persists via store; setting the same mode is a no-op
  (no redundant notify/save).
- `SharedPrefsThemeModeStore`: round-trips each of light/dark/system;
  unknown/missing → null. Uses `SharedPreferences.setMockInitialValues`.
- `CamScannerApp` reacts: pump with an `InMemoryThemeModeStore`-backed controller,
  assert `MaterialApp.themeMode` follows `controller.mode` across `setMode`.

**Widget (host, TDD):**
- `SettingsScreen`: renders the three-way selector at `controller.mode`; tapping
  Light/Dark/System calls `setMode`; `settings-feedback`/`settings-support` push
  the right screens; About row present; no "Ream" text.
- Per-screen dark tests: pump each in-scope screen under `Theme(ReamTheme.dark())`
  and assert its `Scaffold` background resolves to `ReamColors.dark.paper` and key
  elements use dark tokens (mirrors the Phase-2 light assertions).

**BDD:** new `test/features/settings/t1_theme_settings.feature` — behavior is new,
so a feature file is required:
- Scenario: open Settings, select Light → app renders light.
- Scenario: select System → app follows platform brightness.
- Scenario: choice persists across relaunch (seed the store, relaunch, assert
  the selector + theme reflect it).
Generated `*_test.dart` via `build_runner`; steps shared in `test/step/`.

**Both platforms / device:** theme + persistence are `shared_preferences`
(native) — this is device-relevant, not pure-visual, so the BDD integration test
runs on a **real/simulated iOS device AND Android device**. Full regression: run
the existing BDD integration suite in **dark (default) and light** on iOS sim +
Android emulator; the dark run is the acceptance evidence for dark verification.

## Execution structure

One spec → one plan → subagent-driven execution. Suggested task spine (plan
finalizes exact boundaries):
1. `ThemeModeStore` + `SharedPrefsThemeModeStore` + in-memory fake (+ dep add).
2. `ThemeController`.
3. `main.dart` / `runCamScannerApp` / `CamScannerApp` reactive wiring.
4. `SettingsScreen` + `SettingsDependencies` + home gear push (update home tests).
5. Copy fix (`Support the app`).
6. Dark verification pass (per-screen audit/fix + dark tests).
7. BDD `t1_theme_settings` feature + steps.
8. Deferred-minors polish.
9. Whole-branch review + combined device regression (dark + light, both platforms).

Each task: TDD order, scoped `git add` (named paths only, never `-A` — the repo
carries a long-lived WIP pile), `flutter analyze` zero-warnings, `dart format`,
FAIL→PASS evidence, then task review.

## Definition of done

1. Settings screen ships; gear pushes it; theme selector persists across relaunch.
2. App defaults to Dark; every in-scope screen is verified correct in dark on both
   platforms (dark BDD integration run is the evidence).
3. No user-facing "Ream" text remains; display name is CamScanner-light.
4. `flutter test` green except the 2 known opencv-env failures; `flutter analyze`
   zero warnings; `dart format lib test` clean; deferred-minors cleared.
5. No behavior change beyond the theme feature and the settings-nav consolidation;
   all pre-existing tests green with only minimal, noted finder updates.
6. Branch reviewed and merged to master (local + remote).
