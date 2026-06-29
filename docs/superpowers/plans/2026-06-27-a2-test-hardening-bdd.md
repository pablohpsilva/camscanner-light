# A2 Test-Hardening + Executable BDD Infrastructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Strengthen the project's TDD/BDD so the written Given/When/Then scenarios ARE the tests (executable, traceable), close the one A2 coverage asymmetry, exercise the real camera plugin path on-device, and add a coverage floor to the gate.

**Architecture:** Four independent work items, layered onto the already-gated A2. Items 1–3 retrofit A2 (new tests + gate asserts). Item 4 introduces `bdd_widget_test` (`.feature` → generated on-device tests) as the go-forward BDD standard, with A2's scenarios converted as the reference example. The existing `ScanDependencies` fake-injection seam is reused so BDD steps stay deterministic on-device.

**Tech Stack:** Flutter, `flutter_test`, `integration_test`, `bdd_widget_test` + `build_runner` (new dev deps), `camera`/`permission_handler` (already present), the existing `scripts/verify/lib.sh` harness.

## Global Constraints

- TDD/BDD first; SOLID, KISS, DRY. No cloud/network.
- Every new on-device test is the AUTHORITATIVE UI check, **mutation-verified once** by the independent verifier.
- The gate is `scripts/verify/a2.sh` exiting 0; silence = FAIL; caches disabled (`--skip-nx-cache`); negative controls; no silent skips (per `../VERIFICATION.md`).
- Exact UI strings/keys already established by A2 (reuse verbatim): AppBar `'Scan'`; rationale `'Camera access is needed to scan documents'`; `FilledButton` `'Open Settings'`; `'Camera unavailable on this device'`; keys `Key('scan-preview')`, `Key('fake-preview')`, text `'FAKE PREVIEW'`.
- App id `com.camscannerlight.mobile`; package `mobile`. Branch `feat/step-0-monorepo-foundation`.

---

## Task 1: Coverage floor in the gate

**Files:**
- Modify: `scripts/verify/lib.sh` (add `assert_coverage_floor`)
- Modify: `scripts/verify/a2.sh` (call it)

**Interfaces:**
- Produces: `assert_coverage_floor <min_percent>` — runs `flutter test --coverage` in `apps/mobile`, parses `coverage/lcov.info` (sum of `LH:` / sum of `LF:` → line %), PASS iff exit 0 AND percent ≥ min AND lcov.info non-empty; FAIL on any miss (silence = FAIL).

- [ ] **Step 1: Measure current coverage** — Run `cd apps/mobile && flutter test --coverage` then compute line % from `coverage/lcov.info` (`awk -F: '/^LF:/{f+=$2} /^LH:/{h+=$2} END{printf "%.1f\n", 100*h/f}'`). Record the number.

- [ ] **Step 2: Add `assert_coverage_floor` to `lib.sh`** (place near `assert_cmd`):
```bash
# assert_coverage_floor <min_percent> : flutter test --coverage, gate on line %.
assert_coverage_floor() {
  local floor="$1" log="$EVIDENCE_DIR/coverage.log" lcov="$ROOT/apps/mobile/coverage/lcov.info"
  ( cd "$ROOT/apps/mobile" && flutter test --coverage >"$log" 2>&1 ); local rc=$?
  if [ "$rc" -ne 0 ]; then fail "coverage: flutter test --coverage exit $rc (see $log)"; return 1; fi
  if [ ! -s "$lcov" ]; then fail "coverage: lcov.info missing/empty [silence=fail]"; return 1; fi
  local pct; pct="$(awk -F: '/^LF:/{f+=$2} /^LH:/{h+=$2} END{if(f>0) printf "%.1f", 100*h/f; else print "0"}' "$lcov")"
  if awk "BEGIN{exit !($pct >= $floor)}"; then
    pass "coverage: ${pct}% line coverage ≥ floor ${floor}%"; return 0
  fi
  fail "coverage: ${pct}% line coverage BELOW floor ${floor}% (see $log)"; return 1
}
```

- [ ] **Step 3: Call it in `a2.sh`** after the analyze assert, before the device section. Use a floor a few points below the measured value (headroom against churn) — e.g. if measured ≥ 90, set floor `85`:
```bash
assert_coverage_floor 85
```
Pick the actual floor from Step 1 (round down to a stable number; never set it above current).

- [ ] **Step 4: Run the gate's non-device part** — `VERIFY_SKIP_DEVICE=1 bash scripts/verify/a2.sh` should now show the coverage PASS line (and still FAIL overall on the skip-device guard — that's expected). Confirm the coverage line is PASS.

- [ ] **Step 5: Commit** — `git add scripts/verify/lib.sh scripts/verify/a2.sh && git commit -m "test(a2): add coverage floor to the verify gate"`

---

## Task 2: Unavailable-state on-device integration test (retrofit A2)

**Files:**
- Create: `apps/mobile/integration_test/a2_camera_unavailable_test.dart`
- Modify: `scripts/verify/a2.sh` (two more device asserts)

**Interfaces:**
- Consumes: `app.runCamScannerApp`, `unavailableScanDependencies()` (already in `test/support/fake_scan.dart`).

- [ ] **Step 1: Write the test** (mirrors the denied/ready ones):
```dart
// On-device integration test for A2 (no-camera / unavailable path).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: no-camera shows the unavailable message on device',
      (tester) async {
    app.runCamScannerApp(scanDependencies: unavailableScanDependencies());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.text('Camera unavailable on this device'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsNothing);
  });
}
```

- [ ] **Step 2: Sanity-run on Android** — `cd apps/mobile && flutter test integration_test/a2_camera_unavailable_test.dart -d <emulator-id>` → `All tests passed!`

- [ ] **Step 3: Add to `a2.sh`** (with the other device runs):
```bash
verify_integration_android a2_camera_unavailable_test.dart
verify_integration_ios     a2_camera_unavailable_test.dart
```

- [ ] **Step 4: Commit** — `git add apps/mobile/integration_test/a2_camera_unavailable_test.dart scripts/verify/a2.sh && git commit -m "test(a2): on-device integration test for the unavailable state"`

---

## Task 3: Real-plugin path test on Android (retrofit A2)

**Files:**
- Create: `apps/mobile/integration_test/a2_camera_real_android_test.dart`
- Modify: `scripts/verify/lib.sh` (add `verify_integration_android_real`)
- Modify: `scripts/verify/a2.sh` (call it, AFTER the fakes-based android runs so the app is already installed)

**Interfaces:**
- Produces: `verify_integration_android_real <tf>` — ensures emulator, `flutter install -d <dev>` (so the package exists), `adb pm grant <APP_ID> CAMERA`, then runs `flutter test integration_test/<tf> -d <dev>`, gating on "All tests passed!". Android-only (iOS sim has no camera).

**Pre-req note:** the Android emulator's back camera must be `VirtualScene`/`Emulated` (the AVD default) so the real `camera` plugin can initialize. If it cannot, the screen goes `unavailable` and the test FAILS — that is a real finding (fix the AVD), never mask it.

- [ ] **Step 1: Write the real-deps test** (NO injected fakes — exercises the real `camera` + `permission_handler`):
```dart
// On-device integration test exercising the REAL camera plugin path (Android).
// Permission is pre-granted by the harness (verify_integration_android_real),
// so the real permission_handler resolves to granted and the real camera
// initializes, rendering a real CameraPreview. Android-only.
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: real camera plugin renders a live CameraPreview on Android',
      (tester) async {
    app.runCamScannerApp(); // production deps — real plugins
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    // Real camera init can take a moment; pump until the preview appears.
    for (var i = 0; i < 50 && find.byType(CameraPreview).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget,
        reason: 'real camera should initialize and render a live preview '
            '(if this fails, the emulator AVD back camera must be VirtualScene/Emulated)');
    expect(find.text('Camera unavailable on this device'), findsNothing);
  });
}
```

- [ ] **Step 2: Add `verify_integration_android_real` to `lib.sh`**:
```bash
# Exercises the REAL camera/permission path: install the app, grant CAMERA, run.
verify_integration_android_real() {
  local tf="$1" dev; dev="$(_ensure_android)"
  [ -z "$dev" ] && { fail "android(real): no emulator"; return 1; }
  ( cd "$ROOT/apps/mobile" && flutter install -d "$dev" >/dev/null 2>&1 )
  "$ADB" -s "$dev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null
  verify_integration "android-real" "$dev" "$tf"
}
```

- [ ] **Step 3: Sanity-run** — boot emulator, `flutter install`, `adb shell pm grant com.camscannerlight.mobile android.permission.CAMERA`, then `flutter test integration_test/a2_camera_real_android_test.dart -d <id>` → `All tests passed!`. If it lands on `unavailable`, fix the AVD camera (cold-boot with back camera = VirtualScene) and retry; if the emulator genuinely cannot provide a camera, STOP and report it — do not weaken the assertion.

- [ ] **Step 4: Call it in `a2.sh`** AFTER `verify_integration_android a2_camera_ready_test.dart` (app already installed):
```bash
verify_integration_android_real a2_camera_real_android_test.dart
```

- [ ] **Step 5: Commit** — `git add apps/mobile/integration_test/a2_camera_real_android_test.dart scripts/verify/lib.sh scripts/verify/a2.sh && git commit -m "test(a2): exercise the real camera plugin path on Android (pre-granted)"`

---

## Task 4: Executable Gherkin BDD infrastructure (`bdd_widget_test`)

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (dev deps `bdd_widget_test`, `build_runner`)
- Create: `apps/mobile/integration_test/features/*.feature` (A2 scenarios)
- Create: step definitions + a generated-test config so `.feature` files compile to on-device integration tests
- Modify: `scripts/verify/lib.sh` and/or `a2.sh` (run codegen + the generated BDD tests in the gate)
- Update: `docs/superpowers/VERIFICATION.md` + `plans/00-plans-index.md` (BDD-from-`.feature` is the standard from A3)

**Interfaces:**
- Produces: `.feature` files as the SOURCE of the BDD scenarios; generated `*.feature.dart` on-device tests; a documented step-definition pattern reused per feature.

> This item introduces codegen. SPIKE it first (Step 1) to confirm `bdd_widget_test` can target `integration_test` with `IntegrationTestWidgetsFlutterBinding` on a real device. If the tool cannot cleanly target on-device integration tests, fall back to: keep `.feature` files as the authored source and generate WIDGET-level BDD tests (still executable Given/When/Then), while the hand-written on-device integration tests remain the device authority — and record that decision. Do not block the other items on this.

- [ ] **Step 1 (SPIKE): Add deps and confirm targeting** — `cd apps/mobile && flutter pub add dev:bdd_widget_test dev:build_runner`. Read the `bdd_widget_test` docs/options. Create a trivial `.feature` + step and confirm `dart run build_runner build` generates a runnable test. Determine whether it can emit an `integration_test`-compatible test (binding + `-d <device>`). Record the finding in the report.

- [ ] **Step 2: Author A2 `.feature` files** — express the three A2 scenarios as Gherkin (reuse the exact strings). Example `integration_test/features/scan_permission.feature`:
```gherkin
Feature: Scan camera permission and preview
  Scenario: Permission denied shows a rationale and a path to Settings
    Given the app is launched with camera permission denied
    When I tap the Scan button
    Then I see "Camera access is needed to scan documents"
    And I see the "Open Settings" button

  Scenario: Permission granted shows the live preview
    Given the app is launched with camera permission granted
    When I tap the Scan button
    Then I see the camera preview

  Scenario: No camera shows the unavailable message
    Given the app is launched with no camera available
    When I tap the Scan button
    Then I see "Camera unavailable on this device"
```

- [ ] **Step 3: Implement step definitions** — map each Given to `runCamScannerApp` with the matching `ScanDependencies` preset (granted/denied/unavailable), When to a FAB tap, Then to the existing finders (text, the `scan-preview` key). Keep steps DRY and reusable for A3.

- [ ] **Step 4: Wire codegen + run in the gate** — add a gate step that runs `dart run build_runner build --delete-conflicting-outputs` then runs the generated BDD test(s) on each device via `verify_integration_*`. Generated files: either commit them (simpler gate) or regenerate in the gate (cleaner) — pick one and document it. If on-device targeting works (Step 1), the generated BDD tests REPLACE the hand-written `a2_camera_denied/ready/unavailable` tests (DRY — `.feature` is the single source); otherwise they supplement at the widget level and the hand-written device tests remain.

- [ ] **Step 5: Update docs** — `VERIFICATION.md`: BDD scenarios are authored as `.feature` files and generated into tests; `plans/00-plans-index.md`: note the BDD-from-`.feature` standard applies from A3.

- [ ] **Step 6: Commit** — one commit for the BDD infra + A2 feature files + docs.

---

## Definition of Done (gate)

- `scripts/verify/a2.sh` exits 0 (`GATE: PASS`) including: the coverage floor PASS; the unavailable-state device runs; the real-plugin Android run; and (if Step 1 succeeded) the generated BDD device tests.
- Every NEW on-device test mutation-checked once by the independent verifier.
- An independent adversarial verifier runs `a2.sh` from clean and agrees.
- `.feature` files exist as the authored BDD source and the standard is documented for A3+.

## Self-Review notes

- DRY: BDD step definitions reuse the `ScanDependencies` presets and existing finders; if on-device BDD generation works, the hand-written denied/ready/unavailable device tests are removed in favor of the generated ones.
- YAGNI: no `permanentlyDenied` view test (renders identically today), no golden tests.
- Risk: Task 3 depends on the emulator providing a virtual camera; Task 4 depends on `bdd_widget_test` targeting on-device integration tests — both have explicit fallbacks/findings rather than silent weakening.
