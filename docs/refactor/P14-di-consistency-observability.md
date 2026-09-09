# P14 — DI consistency, observability & secondary-feature cleanups

**Tier 3 (Consistency) · Effort S–M · Risk Low · Depends on: P00 (`AppLogger`) · Device verification: Android + iOS (both available)**

Companion to `00-overview-and-comparison.md` and `01-roadmap.md`. This plan unifies the three
divergent dependency-injection styles onto the project's factory-typedef convention, moves a
misplaced (not dead) collaborator to its real consumer, adds observability at the silent native
catches, and cleans up a cluster of small duplication / separation-of-concerns / hardening issues
in the secondary features (feedback, donation, settings).

---

## Summary

The composition roots have drifted into **three** DI styles: `scan_dependencies.dart` uses pure
factory typedefs (the intended convention); `library_dependencies.dart` mixes a `createRepository`
factory with six inline `const` collaborators; `feedback_dependencies.dart` uses lazy
`service()`/`availability()` methods that inline-construct `http.Client()` + collectors + providers;
and `main.dart`'s `runCamScannerApp` inline-creates the `ThemeController`/`LocaleController` (with a
`..load()`) instead of taking them from the composition root. This plan converges everything on the
factory-typedef convention and pulls controller creation into the composition root.

Alongside DI, this plan closes a batch of small, independent issues in the secondary features:
`GalleryPicker` is **misplaced** in scan though its only consumer is the library; the silent native
catches swallow corrupt-input vs native-crash vs timeout; and feedback/donation/settings carry
duplicated nav, a duplicated env read, an in-screen l10n mapping, a per-rebuild origin derivation,
a bare JSON cast, and a raw sitekey interpolation.

This plan is **behaviour-preserving**. `ScanDependencies`, `LibraryDependencies`,
`FeedbackDependencies`, and all public widget constructors keep their **shapes** so the
feedback/donation/settings tests and `test/bdd/*.feature` stay GREEN. Depends on **P00** for
`AppLogger`. Repository-side silent catches are handled by **P10 SAFE-03** — cross-referenced here,
not duplicated.

---

## Verified findings

| ID | Current location | What's wrong | Impact | Live/latent |
|---|---|---|---|---|
| **dependencies-inconsistency** | `scan_dependencies.dart` (typedefs); `library_dependencies.dart:37-45`; `feedback_dependencies.dart:36-47`; `main.dart:48-55` | 3 DI styles: pure factory typedefs vs `createRepository` + 6 inline `const` collaborators (printer/share/archiver/linkShare/fax/features) vs lazy `service()`/`availability()` inline-constructing `http.Client()`+`PlatformDiagnosticsCollector()`+`PlatformAttestationProvider()`; `runCamScannerApp` inline-creates `ThemeController(SharedPrefsThemeModeStore)`/`LocaleController(SharedPrefsLocaleStore)..load()` | No single convention; new collaborators wired ad hoc; controllers created outside the composition root | **live** |
| **DEAD-1** (misplacement, not dead) | `GalleryPicker` iface + `ImagePickerGalleryPicker` + `createGalleryPicker` in `gallery_picker.dart`, wired in `scan_dependencies.dart:4,9,16,23,28`; sole consumer `library/home_screen.dart:195` (via `ScanDependencies`) | Collaborator lives in the SCAN feature but nothing in `lib/features/scan/` uses it | Cross-feature coupling; library reaches through `ScanDependencies` for a picker | **live** |
| **error-swallowing observability** | `native_page_processor.dart:48,95`; enhancer/warper `catch{return bytes}` blocks | Silent catches can't distinguish corrupt-input vs native-crash vs timeout | Native failures are invisible in the field; no signal to diagnose | **live** |
| **DUP-4** | `feedback_config.dart` `FeedbackConfig.fromEnvironment:12-15` **and** `feedback_dependencies.dart:23-26` re-inline the same two `String.fromEnvironment` reads | Env read in two places because `fromEnvironment` is a `factory` (not const-usable as a default param) | Env config can drift; two edit sites for one truth | **live** |
| **DUP-3** | `donation_banner.dart:26-28` & `settings_screen.dart:100-102` hand-roll `Navigator.push(MaterialPageRoute(builder:(_)=>const DonationScreen()))`; feedback push inlined `settings_screen.dart:88-93` | Navigation route duplicated | Route/transition changes must be made in multiple places | **live** |
| **SOC-3** | `feedback_screen.dart` `_messageFor:17-24` | A free `FeedbackResult`→l10n mapping function lives in the screen file | Mapping not reusable/testable next to the model | **live** |
| **SOC-4** | `feedback_screen.dart` `build()` IIFE `${scheme}://${host}` from `workerUrl` at :246-251 | Origin derived on every rebuild inside `build` | Redundant work per rebuild; logic buried in `build` | **live** |
| **SF-2** (hardening) | `feedback_service.dart:46-48` `jsonDecode(...)['challenge'] as String` | Bare cast while later parsing (:102-110) is defensive | A malformed/absent `challenge` throws instead of a handled error | **live** |
| **SF-3** (hardening, low real risk) | `turnstile_widget.dart:71` interpolates `data-sitekey="$siteKey"` raw into WebView HTML (`JavaScriptMode.unrestricted:40`) | Raw interpolation into unrestricted-JS WebView HTML | siteKey is a build-time env constant, so real risk is low; still an unvalidated injection point | **live** |

---

## Definition of done

- All four composition roots use the **factory-typedef** convention: `library_dependencies.dart`'s
  six inline `const` collaborators and `feedback_dependencies.dart`'s inline-constructing methods
  become typedef fields with production defaults; `runCamScannerApp` receives the
  `ThemeController`/`LocaleController` from the composition root instead of `new`-ing them inline.
- `GalleryPicker` (+ `ImagePickerGalleryPicker` + `createGalleryPicker`) lives in the library feature
  and is a `LibraryDependencies` field; `scan_dependencies.dart` no longer references it; `home_screen`
  gets the picker from `LibraryDependencies`.
- `AppLogger` (P00) sinks are wired at `native_page_processor.dart:48,95` and the enhancer/warper
  `catch{return bytes}` blocks, tagging corrupt-input vs native-crash vs timeout. (Repo catches:
  see P10 SAFE-03 — not touched here.)
- Env is read in **one** place: a const-friendly `FeedbackConfig` path so
  `feedback_dependencies.dart` no longer re-inlines the two `String.fromEnvironment` reads.
- `DonationScreen.route()` / `openDonation(context)` (and a feedback equivalent) helpers exist;
  `donation_banner.dart`, `settings_screen.dart` use them instead of hand-rolled `MaterialPageRoute`.
- `_messageFor` becomes a `FeedbackResultL10n` extension beside `feedback_result.dart`.
- `FeedbackConfig.turnstileOrigin` getter replaces the per-rebuild `${scheme}://${host}` IIFE.
- `feedback_service.dart` parses `challenge` defensively (consistent with :102-110).
- `turnstile_widget.dart` validates `siteKey` against `^[A-Za-z0-9_-]+$` (or passes it via a JS
  channel/variable).
- **TDD** failing-first for each change; **BDD** feedback/donation/settings + `test/bdd/*.feature`
  stay green; `flutter analyze` clean. **Device**: feedback + donation flows verified on real Android
  **and** iOS.

---

## Before → After

| Concern | Before | After |
|---|---|---|
| DI convention | 3 styles (typedefs / mixed const / lazy methods) + inline controllers in `main.dart` | One factory-typedef convention; controllers from the composition root |
| `GalleryPicker` | Defined & wired in scan; used only by library | Owned by library; a `LibraryDependencies` field |
| Native catches | Silent `catch{return bytes}` | `AppLogger` sink distinguishing corrupt/crash/timeout |
| Env read | Duplicated in config + deps | Single const-friendly `FeedbackConfig` path |
| Donation/feedback nav | Hand-rolled `MaterialPageRoute` in 3 spots | `DonationScreen.route()`/`openDonation` + feedback helper |
| Feedback result → l10n | Free fn in the screen file | `FeedbackResultL10n` extension beside the model |
| Turnstile origin | `${scheme}://${host}` IIFE per rebuild | `FeedbackConfig.turnstileOrigin` getter |
| `challenge` parse | Bare `as String` cast | Defensive parse like :102-110 |
| Turnstile sitekey | Raw interpolation into unrestricted WebView | Validated `^[A-Za-z0-9_-]+$` / JS channel |

---

## Tasks

Independent, subagent-ready. Write the failing test first, then the minimum implementation. All
tasks touch different files and are parallel-safe unless noted.

### Task 1 — Converge `library_dependencies.dart` on factory typedefs (dependencies-inconsistency)
- **Scope**: Turn the 6 inline `const` collaborators (printer/share/archiver/linkShare/fax/features
  at :37-45) into typedef fields with production defaults, matching `scan_dependencies.dart`. Keep the
  `LibraryDependencies` class **shape** so tests still inject fakes the same way.
- **Files**: `lib/features/library/library_dependencies.dart`.
- **Test-first**: assert existing library tests still construct `LibraryDependencies` with overrides
  and pass; add a test that each collaborator has a production default.
- **Done**: library tests + `test/bdd/*` green; `flutter analyze` clean.
- **Parallel-safe**: yes.

### Task 2 — Converge `feedback_dependencies.dart` on factory typedefs (dependencies-inconsistency)
- **Scope**: Replace lazy `service()`/`availability()` inline-constructing `http.Client()` +
  `PlatformDiagnosticsCollector()` + `PlatformAttestationProvider()` (:36-47) with typedef fields +
  production defaults.
- **Files**: `lib/features/feedback/feedback_dependencies.dart`.
- **Test-first**: feedback tests inject a fake client/collector via the new fields; watch red then
  green.
- **Done**: feedback tests green; shape preserved.
- **Parallel-safe**: yes.

### Task 3 — Move controller creation into the composition root (dependencies-inconsistency)
- **Scope**: `runCamScannerApp` (`main.dart:48-55`) should receive `ThemeController`/`LocaleController`
  (with `..load()`) as parameters/overrides from the composition root rather than `new`-ing
  `ThemeController(SharedPrefsThemeModeStore)` / `LocaleController(SharedPrefsLocaleStore)` inline.
- **Files**: `lib/main.dart` (+ composition root wiring).
- **Test-first**: a test constructs `runCamScannerApp` with injected controllers (deterministic
  locale/theme) and asserts no inline store is created.
- **Done**: startup behaviour unchanged; i18n/theme tests green.
- **Parallel-safe**: yes (main.dart-scoped).

### Task 4 — Relocate `GalleryPicker` to the library feature (DEAD-1)
- **Scope**: Move `gallery_picker.dart` (`GalleryPicker`, `ImagePickerGalleryPicker`,
  `createGalleryPicker`) into `lib/features/library/`; make it a `LibraryDependencies` field; remove
  its references from `scan_dependencies.dart:4,9,16,23,28`; `home_screen.dart:195` reads it from
  `LibraryDependencies`.
- **Files**: `gallery_picker.dart` (moved), `scan_dependencies.dart`, `library_dependencies.dart`,
  `home_screen.dart`.
- **Test-first**: a test asserts `home_screen` imports the picker from library DI and `scan` no
  longer exposes it; watch red then green.
- **Done**: scan feature no longer references the picker; import BDD green.
- **Parallel-safe**: coordinate with Task 1 (both edit `library_dependencies.dart`) — do Task 1 first
  or merge carefully.

### Task 5 — `AppLogger` sinks at silent native catches (error-swallowing observability)
- **Scope**: At `native_page_processor.dart:48,95` and the enhancer/warper `catch{return bytes}`
  blocks, log via `AppLogger` (P00) distinguishing corrupt-input vs native-crash vs timeout. Keep the
  fallback return semantics identical (still return `bytes`/`null`).
- **Files**: `lib/features/library/native_page_processor.dart` (+ enhancer/warper files).
- **Test-first**: unit test asserting a thrown native error is logged with the right tag while the
  fallback still returns the input bytes.
- **Done**: no behaviour change to the fallback path; logs present. Cross-reference **P10 SAFE-03**
  for repo catches (do not duplicate here).
- **Parallel-safe**: yes. **Depends on P00.**

### Task 6 — Single const-friendly env read (DUP-4)
- **Scope**: Provide a const-friendly `FeedbackConfig` path so the two `String.fromEnvironment` reads
  live only in `feedback_config.dart`; `feedback_dependencies.dart:23-26` no longer re-inlines them
  (the `factory fromEnvironment:12-15` isn't const-usable as a default param — hence a `const`
  constructor / static const path).
- **Files**: `lib/features/feedback/feedback_config.dart`, `feedback_dependencies.dart`.
- **Test-first**: test asserting the deps default derives config from the single `FeedbackConfig`
  source.
- **Done**: env read once; feedback tests green.
- **Parallel-safe**: yes (coordinate with Task 2 on `feedback_dependencies.dart`).

### Task 7 — Nav route helpers (DUP-3)
- **Scope**: Add `DonationScreen.route()` / `openDonation(context)` and a feedback push helper;
  replace hand-rolled `MaterialPageRoute` in `donation_banner.dart:26-28`, `settings_screen.dart:100-102`,
  and the inlined feedback push `settings_screen.dart:88-93`.
- **Files**: `donation_screen.dart`, `feedback_screen.dart` (helper), `donation_banner.dart`,
  `settings_screen.dart`.
- **Test-first**: widget test that tapping the banner/settings item navigates to the right screen via
  the helper.
- **Done**: nav behaviour identical; settings/donation tests green.
- **Parallel-safe**: yes.

### Task 8 — `FeedbackResultL10n` extension (SOC-3)
- **Scope**: Move `_messageFor` (`feedback_screen.dart:17-24`) to a `FeedbackResultL10n` extension
  beside `feedback_result.dart`.
- **Files**: `feedback_result.dart` (extension), `feedback_screen.dart`.
- **Test-first**: unit test mapping each `FeedbackResult` to its l10n key.
- **Done**: mapping reusable/testable; feedback tests green.
- **Parallel-safe**: yes (coordinate with Task 9 on `feedback_screen.dart`).

### Task 9 — `FeedbackConfig.turnstileOrigin` getter (SOC-4)
- **Scope**: Add a `turnstileOrigin` getter to `FeedbackConfig` computing `${scheme}://${host}` from
  `workerUrl` once; replace the per-rebuild IIFE at `feedback_screen.dart:246-251`.
- **Files**: `feedback_config.dart`, `feedback_screen.dart`.
- **Test-first**: unit test for `turnstileOrigin` from a sample `workerUrl` (with/without port, https).
- **Done**: origin computed once; feedback tests green.
- **Parallel-safe**: yes (coordinate with Task 8 on `feedback_screen.dart`).

### Task 10 — Defensive `challenge` parse + sitekey validation (SF-2, SF-3)
- **Scope**: `feedback_service.dart:46-48` — parse `challenge` defensively like :102-110 (handled
  error instead of a thrown bare cast). `turnstile_widget.dart:71` — validate `siteKey` against
  `^[A-Za-z0-9_-]+$` (or pass via a JS channel/variable) before interpolating into the
  `JavaScriptMode.unrestricted` WebView HTML.
- **Files**: `feedback_service.dart`, `turnstile_widget.dart`.
- **Test-first**: service test for a missing/malformed `challenge` yielding a handled error; widget
  test that an invalid sitekey is rejected (or escaped).
- **Done**: no bare cast; sitekey validated; feedback tests green.
- **Parallel-safe**: yes.

---

## Risks & mitigations

- **DI shape churn breaks fake injection** — tests inject fakes via the current field names.
  *Mitigation*: keep the class **shapes** (field names/positions) stable; only change how defaults are
  produced (behaviour-preserving constraint).
- **Controller-in-composition-root changes startup order** — moving `..load()` could shift when
  theme/locale resolve. *Mitigation*: preserve the `load()` timing; verify i18n follow-device-locale
  and theme on device.
- **`GalleryPicker` move breaks the import path** — `home_screen` reaches through `ScanDependencies`
  today. *Mitigation*: land Task 1 first (or merge carefully); keep the picker's interface identical,
  only its home changes.
- **Over-eager sitekey validation** — a stricter regex could reject a valid Turnstile key.
  *Mitigation*: `^[A-Za-z0-9_-]+$` matches Turnstile's key charset; fail loud in debug, and the key is
  a build-time constant so it's caught at build.
- **Logging noise / PII** — new `AppLogger` sinks must not log image bytes or user content.
  *Mitigation*: log only error class + tag (corrupt/crash/timeout), never payloads.
- **Duplicate edits to `feedback_screen.dart` / `feedback_dependencies.dart`** — Tasks 2/6 and 8/9
  overlap files. *Mitigation*: sequence those pairs or reconcile in one merge; each still tested
  independently.

---

## Verification commands

Run from `apps/mobile/`.

```bash
# TDD — DI, feedback, donation, settings (host)
flutter test test/features/feedback/
flutter test test/features/donation/
flutter test test/features/settings/
flutter test test/features/library/          # library DI + gallery picker relocation + native logger sinks
flutter test test/features/scan/             # scan DI

# BDD stays green (host)
flutter test test/bdd/

# i18n / theme startup (controllers moved to composition root)
flutter test test/                            # supported-locales + theme guardrails

# Lint / format (zero-warning bar)
flutter analyze
dart format --output=none --set-exit-if-changed lib test

# Device — feedback + donation flows (BOTH platforms)
flutter test integration_test/feedback_device_test.dart -d <android-device-id>
flutter test integration_test/feedback_device_test.dart -d <ios-device-id>
```

Depends on **P00** (`AppLogger`) landing first. Do not claim done until feedback + donation flows are
green on a real Android device **and** a real iOS device, with the green run recorded.
