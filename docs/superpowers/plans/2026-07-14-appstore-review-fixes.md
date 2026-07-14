# App Store Rejection Fixes (3.1.1 + 2.3.10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide all donation entry points on iOS (guideline 3.1.1) and regenerate the iOS App Store screenshots from iOS simulators without the donation banner (guideline 2.3.10), then produce build 1.0.1+10 for resubmission.

**Architecture:** A runtime platform gate (`donationsAvailable`, false on iOS/iPadOS) conditionally removes the two donation entry points — the home-screen `DonationBanner` and the Settings "Support the app" row. `DonationScreen`/`DonationBanner`/`DonationConfig` are untouched. Screenshots are regenerated with the existing `store/` capture + framing pipeline.

**Tech Stack:** Flutter (`apps/mobile/`), `bdd_widget_test` + `build_runner` for BDD, `integration_test` for device proof, `store/capture.sh` + headless-Chrome `store/template/build.mjs` for screenshots.

**Spec:** `docs/superpowers/specs/2026-07-14-appstore-review-fixes-design.md`

## Global Constraints

- All Flutter commands run from `apps/mobile/` unless noted otherwise.
- TDD: write the failing test, watch it fail, then implement (red → green).
- Every user-facing behavior needs a Gherkin `.feature` scenario (host BDD lives in `test/bdd/`, steps in `test/step/`, regenerate with `dart run build_runner build --delete-conflicting-outputs`).
- Native/user-visible behavior must be proven on a real Android device AND an iOS device; if no physical iOS device is attached, an iOS simulator run plus an explicitly named gap is the fallback.
- `flutter analyze` must stay at zero warnings; run `dart format lib test integration_test` on touched files.
- Scope every `git add` to named paths — never `git add -A` (long-lived WIP files may sit in the tree).
- Widget tests that set `debugDefaultTargetPlatformOverride` MUST reset it to `null` in a `tearDown`/`addTearDown`, or flutter_test fails the test.

## Parallel execution groups (per CLAUDE.md subagent mandate)

- **Group A:** Task 1 (gate helper) — must land first (defines the interface).
- **Group B (parallel):** Task 2 (home banner gate), Task 3 (settings row gate).
- **Group C (parallel):** Task 4 (host BDD), Task 5 (device test) — depend on Tasks 2+3 being merged.
- **Group D:** Task 6 (screenshot recapture) — depends on Tasks 1–3.
- **Group E:** Task 7 (version bump, full verification, Release IPA).

---

### Task 1: `donationsAvailable` platform gate helper

**Files:**
- Create: `apps/mobile/lib/features/donation/donation_availability.dart`
- Test: `apps/mobile/test/features/donation/donation_availability_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: top-level getter `bool get donationsAvailable` exported from `package:mobile/features/donation/donation_availability.dart`. Tasks 2 and 3 import and read this getter.

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/donation/donation_availability_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_availability.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('donations are unavailable on iOS (App Store guideline 3.1.1)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(donationsAvailable, isFalse);
  });

  test('donations are available on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(donationsAvailable, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `apps/mobile/`): `flutter test test/features/donation/donation_availability_test.dart`
Expected: FAIL — compile error, `donation_availability.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// apps/mobile/lib/features/donation/donation_availability.dart
import 'package:flutter/foundation.dart';

/// Whether donation entry points may be shown on this platform.
///
/// App Store guideline 3.1.1: donations to the developer must go through
/// In-App Purchase on iOS/iPadOS, so every donation entry point (the
/// home-screen banner and the Settings "Support the app" row) is hidden
/// there. Android keeps the Ko-fi / Bitcoin options.
bool get donationsAvailable => defaultTargetPlatform != TargetPlatform.iOS;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/donation/donation_availability_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/donation/donation_availability.dart \
        apps/mobile/test/features/donation/donation_availability_test.dart
git commit -m "feat(donation): platform gate — donations unavailable on iOS (guideline 3.1.1)"
```

---

### Task 2: Hide the home-screen donation banner on iOS

**Files:**
- Modify: `apps/mobile/lib/features/library/home_screen.dart` (build method, `bottomNavigationBar:` at ~line 387; imports at top)
- Test: `apps/mobile/test/features/donation/donation_banner_wiring_test.dart` (replace file contents)

**Interfaces:**
- Consumes: `bool get donationsAvailable` from `package:mobile/features/donation/donation_availability.dart` (Task 1).
- Produces: `HomeScreen` renders `DonationBanner` (key `donation-banner`) only when `donationsAvailable` is true. No API change.

- [ ] **Step 1: Write the failing tests (replace the wiring test file)**

```dart
// apps/mobile/test/features/donation/donation_banner_wiring_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ReamTheme.light(),
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('home screen shows the donation banner on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _pumpHome(tester);
    expect(find.byType(DonationBanner), findsOneWidget);
  });

  testWidgets('home screen hides the donation banner on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _pumpHome(tester);
    expect(find.byType(DonationBanner), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify the iOS one fails**

Run: `flutter test test/features/donation/donation_banner_wiring_test.dart`
Expected: 1 pass ("on Android"), 1 FAIL ("on iOS" — banner still present).

- [ ] **Step 3: Implement the gate in HomeScreen**

In `apps/mobile/lib/features/library/home_screen.dart`, add the import next to the existing donation import (line ~36):

```dart
import '../donation/donation_availability.dart';
```

and change the `build` method's banner line (~387):

```dart
// before
bottomNavigationBar: const DonationBanner(),
// after
bottomNavigationBar: donationsAvailable ? const DonationBanner() : null,
```

- [ ] **Step 4: Run tests to verify both pass**

Run: `flutter test test/features/donation/donation_banner_wiring_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/home_screen.dart \
        apps/mobile/test/features/donation/donation_banner_wiring_test.dart
git commit -m "fix(donation): hide home-screen donation banner on iOS (guideline 3.1.1)"
```

---

### Task 3: Hide the Settings "Support the app" row on iOS

**Files:**
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart` (imports; the `_NavRow` with key `settings-support` at ~lines 69–76)
- Test: `apps/mobile/test/features/settings/settings_screen_test.dart` (add tests)

**Interfaces:**
- Consumes: `bool get donationsAvailable` from `package:mobile/features/donation/donation_availability.dart` (Task 1).
- Produces: `SettingsScreen` renders the row with key `settings-support` only when `donationsAvailable` is true. No API change.

- [ ] **Step 1: Add the failing tests**

In `apps/mobile/test/features/settings/settings_screen_test.dart`, add the import at the top:

```dart
import 'package:flutter/foundation.dart';
```

add inside `main()` before the first test:

```dart
  tearDown(() => debugDefaultTargetPlatformOverride = null);
```

and append these tests at the end of `main()`:

```dart
  testWidgets('support row is hidden on iOS', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-support')), findsNothing);
  });

  testWidgets('support row is shown on Android', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-support')), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify the iOS one fails**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: "support row is hidden on iOS" FAILS (row present); all others pass.

- [ ] **Step 3: Implement the gate in SettingsScreen**

In `apps/mobile/lib/features/settings/settings_screen.dart`, add the import next to the donation import (line ~8):

```dart
import '../donation/donation_availability.dart';
```

and guard the support row (~line 69):

```dart
// before
            _NavRow(
              key: const Key('settings-support'),
              icon: Icons.favorite_outline,
              label: 'Support the app',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DonationScreen())),
            ),
// after
            if (donationsAvailable)
              _NavRow(
                key: const Key('settings-support'),
                icon: Icons.favorite_outline,
                label: 'Support the app',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DonationScreen()),
                ),
              ),
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/settings/settings_screen.dart \
        apps/mobile/test/features/settings/settings_screen_test.dart
git commit -m "fix(donation): hide Settings support row on iOS (guideline 3.1.1)"
```

---

### Task 4: Host BDD feature for the donation platform gate

**Files:**
- Create: `apps/mobile/test/bdd/donation_platform_gate.feature`
- Create: `apps/mobile/test/step/the_platform_is_ios.dart`
- Create: `apps/mobile/test/step/the_platform_is_android.dart`
- Create: `apps/mobile/test/step/the_home_screen_is_shown.dart`
- Create: `apps/mobile/test/step/i_see_the_donation_banner.dart`
- Create: `apps/mobile/test/step/i_do_not_see_the_donation_banner.dart`
- Create: `apps/mobile/test/step/i_see_the_support_row.dart`
- Create: `apps/mobile/test/step/i_do_not_see_the_support_row.dart`
- Generated: `apps/mobile/test/bdd/donation_platform_gate_test.dart` (via build_runner — do not hand-edit)

**Interfaces:**
- Consumes: gated `HomeScreen`/`SettingsScreen` behavior (Tasks 2+3); existing step `test/step/i_open_settings_from_home.dart` (taps key `home-settings`); fakes `grantedScanDependencies()` / `fakeLibraryDependencies(FakeDocumentRepository())` from `test/support/`.
- Produces: host BDD scenarios that run under `flutter test test/bdd/`.

- [ ] **Step 1: Write the feature file**

```gherkin
# apps/mobile/test/bdd/donation_platform_gate.feature
Feature: Donation entry points respect the platform

  App Store guideline 3.1.1: no non-IAP donations on iOS, so every donation
  entry point is hidden there. Android keeps them.

  Scenario: Donation entry points are hidden on iOS
    Given the platform is iOS
    And the home screen is shown
    Then I do not see the donation banner
    When I open settings from home
    Then I do not see the support row

  Scenario: Donation entry points are shown on Android
    Given the platform is Android
    And the home screen is shown
    Then I see the donation banner
    When I open settings from home
    Then I see the support row
```

- [ ] **Step 2: Write the step implementations**

```dart
// apps/mobile/test/step/the_platform_is_ios.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the platform is iOS
Future<void> thePlatformIsIOS(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}
```

```dart
// apps/mobile/test/step/the_platform_is_android.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the platform is Android
Future<void> thePlatformIsAndroid(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}
```

```dart
// apps/mobile/test/step/the_home_screen_is_shown.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the home screen is shown
Future<void> theHomeScreenIsShown(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ReamTheme.light(),
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

```dart
// apps/mobile/test/step/i_see_the_donation_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the donation banner
Future<void> iSeeTheDonationBanner(WidgetTester tester) async {
  expect(find.byKey(const Key('donation-banner')), findsOneWidget);
}
```

```dart
// apps/mobile/test/step/i_do_not_see_the_donation_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the donation banner
Future<void> iDoNotSeeTheDonationBanner(WidgetTester tester) async {
  expect(find.byKey(const Key('donation-banner')), findsNothing);
}
```

```dart
// apps/mobile/test/step/i_see_the_support_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the support row
Future<void> iSeeTheSupportRow(WidgetTester tester) async {
  expect(find.byKey(const Key('settings-support')), findsOneWidget);
}
```

```dart
// apps/mobile/test/step/i_do_not_see_the_support_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the support row
Future<void> iDoNotSeeTheSupportRow(WidgetTester tester) async {
  expect(find.byKey(const Key('settings-support')), findsNothing);
}
```

- [ ] **Step 3: Generate the test and check the generated step names**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `test/bdd/donation_platform_gate_test.dart` generated. Open it and confirm the imports match the step files created above (e.g. `./../step/the_platform_is_ios.dart` and function `thePlatformIsIOS`). If the generator expected different file/function names (its snake/camel conversion is authoritative), rename the step files/functions to match the generated imports and re-run the build.

- [ ] **Step 4: Run the BDD tests**

Run: `flutter test test/bdd/donation_platform_gate_test.dart`
Expected: PASS (2 scenarios).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/test/bdd/donation_platform_gate.feature \
        apps/mobile/test/bdd/donation_platform_gate_test.dart \
        apps/mobile/test/step/the_platform_is_ios.dart \
        apps/mobile/test/step/the_platform_is_android.dart \
        apps/mobile/test/step/the_home_screen_is_shown.dart \
        apps/mobile/test/step/i_see_the_donation_banner.dart \
        apps/mobile/test/step/i_do_not_see_the_donation_banner.dart \
        apps/mobile/test/step/i_see_the_support_row.dart \
        apps/mobile/test/step/i_do_not_see_the_support_row.dart
git commit -m "test(donation): BDD scenarios for platform-gated donation entry points"
```

---

### Task 5: Device integration test on Android AND iOS

**Files:**
- Create: `apps/mobile/integration_test/n1_donation_gate_device_test.dart`

**Interfaces:**
- Consumes: the real app (`package:mobile/main.dart`), gated behavior from Tasks 2+3, widget keys `donation-banner`, `home-settings`, `settings-support`.
- Produces: a single device test that self-adapts per platform (asserts absence on iOS, presence on Android).

- [ ] **Step 1: Write the device test**

```dart
// apps/mobile/integration_test/n1_donation_gate_device_test.dart
// On-device proof for App Store guideline 3.1.1: donation entry points are
// absent on iOS/iPadOS and present on Android.
//
// Run: flutter test integration_test/n1_donation_gate_device_test.dart -d <device-id>
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('donation entry points match the platform rules', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    final matcher = Platform.isIOS ? findsNothing : findsOneWidget;

    expect(find.byKey(const Key('donation-banner')), matcher);

    await tester.tap(find.byKey(const Key('home-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-support')), matcher);
  });
}
```

- [ ] **Step 2: List attached devices**

Run: `flutter devices`
Expected: the Android device (previously `RZCY51D0T1K`) and an iOS device or simulator. If no iOS simulator is booted: `xcrun simctl list devices available | grep -i iphone`, then `xcrun simctl boot <udid>`.

- [ ] **Step 3: Run on the Android device**

Run: `flutter test integration_test/n1_donation_gate_device_test.dart -d RZCY51D0T1K`
Expected: PASS (banner and support row present).

- [ ] **Step 4: Run on iOS**

Run: `flutter test integration_test/n1_donation_gate_device_test.dart -d <ios-device-or-sim-id>`
Expected: PASS (banner and support row absent). Prefer a physical iPhone if attached; otherwise run on an iOS simulator and NAME THE GAP ("verified on simulator, not physical hardware") in the task report.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/integration_test/n1_donation_gate_device_test.dart
git commit -m "test(donation): device proof that iOS hides donation entry points"
```

---

### Task 6: Regenerate iOS App Store screenshots (2.3.10)

**Files:**
- Modify (regenerated): `store/raw/ios-iphone/*.png`, `store/raw/ios-ipad/*.png`
- Modify (regenerated): `store/final/ios-iphone/*.png` (1320×2868), `store/final/ios-ipad/*.png` (2048×2732)

**Interfaces:**
- Consumes: donation gate (Tasks 1–3) already merged into this branch; `store/capture.sh`; `apps/mobile/integration_test/store_capture_test.dart`; `store/template/build.mjs`.
- Produces: twelve framed finals with iOS status bars and no donation banner, ready for App Store Connect upload.

- [ ] **Step 1: Boot the two iOS 18.x simulators**

```bash
xcrun simctl list devices available | grep -iE "iPhone 16 Plus|iPad Pro 13"
xcrun simctl boot <iphone-16-plus-udid>
xcrun simctl boot <ipad-pro-13-udid>
```

Expected: both listed as Booted (`xcrun simctl list devices | grep Booted`). Use iOS 18.x runtimes (iOS 26 sims are arm64-only and the app forces x86_64 for simulators).

- [ ] **Step 2: Capture raw iOS shots**

```bash
store/capture.sh <iphone-16-plus-udid> ios-iphone ios
store/capture.sh <ipad-pro-13-udid>    ios-ipad   ios
```

Expected: each run prints six `captured .../<name>.png` lines (scan, library, filters, pdf, search, privacy) into `store/raw/ios-iphone/` and `store/raw/ios-ipad/`.

- [ ] **Step 3: Rebuild the framed finals**

```bash
node store/template/build.mjs
```

Expected: regenerates `store/final/**` (Android classes rebuild unchanged from their existing raws — that's fine).

- [ ] **Step 4: Visually verify all 12 iOS finals**

Read every image in `store/final/ios-iphone/` and `store/final/ios-ipad/` and confirm each one: (a) iOS status bar inside the bezel, (b) NO "Enjoying the app? Tap to support it" banner, (c) caption and screen content correct. Also verify sizes:

```bash
sips -g pixelWidth -g pixelHeight store/final/ios-iphone/*.png store/final/ios-ipad/*.png
```

Expected: 1320×2868 (iphone) and 2048×2732 (ipad) exactly.

- [ ] **Step 5: Commit**

```bash
git add store/raw/ios-iphone store/raw/ios-ipad store/final/ios-iphone store/final/ios-ipad
git commit -m "chore(store): recapture iOS screenshots without donation banner (guideline 2.3.10)"
```

---

### Task 7: Version bump, full verification, Release IPA

**Files:**
- Modify: `apps/mobile/pubspec.yaml:19` (`version: 1.0.1+9` → `version: 1.0.1+10`)

**Interfaces:**
- Consumes: everything above, merged.
- Produces: green full host suite, clean analyze, `apps/mobile/build/ios/ipa/mobile.ipa` (Release, build 10).

- [ ] **Step 1: Bump the build number**

In `apps/mobile/pubspec.yaml` change:

```yaml
version: 1.0.1+10
```

- [ ] **Step 2: Format + analyze + full host suite**

```bash
cd apps/mobile
dart format lib test integration_test
flutter analyze
flutter test
```

Expected: format makes no unexpected changes, analyze reports zero issues, all host tests pass. (OpenCV-dependent host failures are environmental — see CLAUDE.md — but there should be none in the touched areas.)

- [ ] **Step 3: Commit the bump**

```bash
git add apps/mobile/pubspec.yaml
git commit -m "chore: bump to 1.0.1+10 for App Store resubmission"
```

- [ ] **Step 4: Build the Release IPA (from repo root)**

```bash
bash scripts/build-ios-release.sh
```

Expected: prints the output path `apps/mobile/build/ios/ipa/mobile.ipa` and embedded version 1.0.1 (10). If the export fails on signing ("No signing certificate iOS Distribution"), STOP and tell the user to sign into Xcode → Settings → Accounts (per CLAUDE.md), then re-run only the export.

- [ ] **Step 5: Report the user-side checklist**

Do not upload anything. Report to the user:
1. Upload `apps/mobile/build/ios/ipa/mobile.ipa` (`xcrun altool --upload-app -f apps/mobile/build/ios/ipa/mobile.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>`).
2. In App Store Connect → app → Previews and Screenshots → "View All Sizes in Media Manager": replace EVERY slot holding an Android-derived image with `store/final/ios-iphone/` (6.9") and `store/final/ios-ipad/` (13") sets.
3. Select build 10 for version 1.0.1 and resubmit.
4. Optional Resolution Center reply: donations were removed from the iOS app (guideline 3.1.1) and all screenshots were recaptured on iOS simulators (guideline 2.3.10).
