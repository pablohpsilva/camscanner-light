# App Store rejection fixes — Guidelines 3.1.1 (donations) and 2.3.10 (screenshots)

**Date:** 2026-07-14
**Context:** Apple rejected v1.0.1 (build 9), submission `6b06a25c-a3b5-4a54-b3bf-533785331c71`,
reviewed on iPad Air 11-inch (M3). Two issues:

1. **Guideline 3.1.1 — Payments.** The app offers donations (Ko-fi link, Bitcoin
   address) through a mechanism other than In-App Purchase. Apple requires IAP
   for donations to the developer, or their removal from the iOS app.
2. **Guideline 2.3.10 — Accurate Metadata.** Uploaded App Store screenshots show
   a non-iOS status bar. Root cause: the ASC-sized sets in
   `apps/web/assets/screenshots/appstore/` (1284×2778) and `appstore-ipad/`
   (2048×2732, commit `a5d4d88`) were resized from **Android** captures —
   Android status bar, Material widgets, Android nav bar.

**Decisions (user-approved):** hide donations on iOS (keep them on Android);
recapture the iOS screenshots from iOS simulators with donations hidden.

## 1. Donation gate (3.1.1)

**Approach: runtime platform gate.** A small helper in
`lib/features/donation/` (e.g. `donation_availability.dart`):

```dart
/// App Store guideline 3.1.1: donations to the developer must use In-App
/// Purchase on iOS, so all donation entry points are hidden there.
bool get donationsAvailable => defaultTargetPlatform != TargetPlatform.iOS;
```

Chosen over a build-time `FEATURE_DONATION` flag because the constraint is a
property of the platform, not of a build configuration — no future iOS build
can forget a `--dart-define` and regress into rejection. Tests override with
`debugDefaultTargetPlatformOverride`.

**Call sites (the only two donation entry points):**

- `lib/features/library/home_screen.dart:582` —
  `bottomNavigationBar: donationsAvailable ? const DonationBanner() : null`
- `lib/features/settings/settings_screen.dart:69-76` — include the
  "Support the app" `_NavRow` only when `donationsAvailable`.

`DonationScreen`, `DonationBanner`, and `DonationConfig` are untouched:
unreachable on iOS, unchanged on Android.

**Tests (TDD + BDD, both platforms):**

- Widget tests (failing first): home-screen banner and settings row hidden
  when `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`, visible for
  `TargetPlatform.android`.
- BDD: a `.feature` file covering both behaviors ("donation entry points are
  hidden on iPhone/iPad", "donation entry points are shown on Android"),
  generated test via `build_runner`, steps in `test/step/`.
- Device proof: `integration_test/*_device_test.dart` run on a real/simulated
  iOS device asserting no donation banner and no settings row, and on a real
  Android device asserting both are present.

## 2. Screenshots (2.3.10)

The replacement pipeline already exists in `store/` (capture harness +
headless-Chrome framer). After the donation gate lands:

1. Boot the iOS 18.3 **iPhone 16 Plus** and **iPad Pro 13-inch (M4)**
   simulators; run `store/capture.sh <udid> ios-iphone ios` and
   `store/capture.sh <udid> ios-ipad ios`.
2. `node store/template/build.mjs` to regenerate the framed finals.
3. Verify each of the six `store/final/ios-iphone/` (1320×2868) and
   `store/final/ios-ipad/` (2048×2732) images: iOS status bar, no donation
   banner, correct captions.

Android classes (`android-phone`, `android-tablet`) are not recaptured — the
banner is legitimate on Play Store shots. The misleading
`apps/web/assets/screenshots/appstore*/` sets live on another branch and are
not part of this fix.

## 3. Release + resubmission

- Bump `apps/mobile/pubspec.yaml` to `1.0.1+10` (TestFlight has seen build 9).
- Build the Release IPA: `bash scripts/build-ios-release.sh`.
- **User-side checklist (Claude cannot do these):**
  1. Upload `apps/mobile/build/ios/ipa/mobile.ipa` via `xcrun altool`.
  2. In App Store Connect → Previews and Screenshots → **View All Sizes in
     Media Manager**, replace every size slot containing an Android-derived
     image with the new `store/final/ios-*` sets.
  3. Select the new build 10 for the version and resubmit.
  4. Optionally reply in the Resolution Center noting donations were removed
     from the iOS app and screenshots were replaced with iOS captures.

## Error handling / edge cases

- iPadOS reports `TargetPlatform.iOS` — covered by the same gate (the review
  device was an iPad).
- macOS/desktop are not shipped targets; the gate only special-cases iOS.
- An unconfigured donation build (empty `KOFI_URL`/`BITCOIN_ADDRESS`) already
  hides the donation screen's sections; that behavior is unchanged.

## Definition of done

- All host tests green (`flutter test` from `apps/mobile/`).
- Device integration tests green on a real Android device AND an iOS
  device/simulator, named explicitly in the verification report.
- Six new iOS iPhone + six iPad finals regenerated and visually verified.
- `flutter analyze` clean; build 10 IPA produced.
