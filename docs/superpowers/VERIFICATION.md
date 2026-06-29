# Verification Protocol (binding)

This protocol exists because a "done" was once claimed on a check that **silently
did nothing** (`timeout` was missing, the command produced no output, and absence
of output was mistaken for success — with a stale side-signal filling the gap).
It must never recur. Every step, feature, and acceptance criterion is gated by
the rules below. This protocol is part of the Definition of Done.

## The rules (every acceptance criterion)

1. **Criterion → command → marker.** Each acceptance checkbox maps to an exact
   command and an exact expected **success marker** in that command's output. A
   box is ticked only when the captured actual output contains the marker.
2. **Silence is FAILURE.** Missing marker, empty output, or an unverified command
   is a FAIL — never a pass. Absence of evidence is not evidence.
3. **Assert exit codes.** A non-zero exit (unless explicitly expected) is a FAIL,
   independent of output.
4. **Tool preconditions.** Verify every tool the check relies on exists
   (`command -v <tool>`) before using it. A missing tool is a FAIL, not a skip.
   (This is the exact bug that slipped through: `timeout` was absent.)
5. **Negative control.** Where state could be stale, first force the system into
   a known-**failing** state (force-stop the app, delete the build artifact,
   clear the cache) so a stale pass is impossible. Then prove the action under
   test moves it to the passing state.
6. **No cache masking.** Run build/test/analyze with caching disabled
   (`--skip-nx-cache`) so a cached result can neither mask a failure nor stand in
   for a real run.
7. **Reproduce independently.** Never tick a box from another agent's report.
   Re-run the check yourself and observe the output.
8. **Store evidence.** Logs and screenshots are written to
   `.superpowers/verify/` (git-ignored) and referenced from the spec checkbox.

## The mechanism (per step)

- **Every step ships a verify script:** `scripts/verify/<step>.sh`, sourcing
  `scripts/verify/lib.sh`. It encodes all of the step's acceptance criteria as
  asserts (rules 1–6), saves evidence, prints a PASS/FAIL line per criterion, and
  **exits non-zero if any criterion fails**. `lib.sh` treats a missing marker as
  FAIL by construction, so rule 2 cannot be forgotten.
- **The progression gate is the script's exit code.** A step is "done" only when
  `scripts/verify/<step>.sh` exits 0, **observed**, not narrated.
- **On-device UI is verified programmatically, not by screenshot.** Any step that
  adds/changes UI ships an `apps/mobile/integration_test/<step>_*.dart` test that
  pumps the **real app on each device** and asserts the rendered widget tree; the
  verify script runs it via `verify_integration_android` /
  `verify_integration_ios` (in `lib.sh`), which gate on "All tests passed!".
  Screenshots are **corroborating only**. Each new UI test must be
  **mutation-checked** once (inject a guaranteed-false assertion → confirm the
  gate FAILS, then revert) so the test is provably non-vacuous.
- **Independent adversarial verifier.** After the implementer and the task
  reviewer, a **separate** subagent runs `scripts/verify/<step>.sh` from a clean
  state, tries to **disprove** "done," and reports PASS/FAIL per criterion with
  evidence. The controller marks the step complete only when the independent
  verifier agrees. The controller does not self-certify device/runtime criteria.

## Authoring a step's verify script

For each acceptance criterion, add one assert that:
- names the criterion,
- runs the real command (cache disabled),
- checks exit code **and** the positive marker,
- applies a negative control if stale state is possible,
- writes its log/screenshot to `$EVIDENCE_DIR`.

If a criterion genuinely cannot be machine-checked, that is itself a finding —
make the script print it as a FAIL with the reason, never a silent skip.

## Device-launch signals (learned the hard way)

The device checks went through several false-fails before settling on a
per-platform **reliable** signal. Use device-side state, not the `flutter run`
tool's stdout, where the tool is flaky:

- **Android — poll device state** (`dumpsys activity … ResumedActivity`). The
  `flutter run` stdout is unreliable: DDS (Dart Debug Service) connection errors
  make the tool exit non-zero *after* the app has actually launched. The app
  being the resumed activity (after a force-stop negative control) is the truth.
- **iOS — poll the fresh-per-run log marker** "A Dart VM Service … is available".
  On the simulator the tool reliably reaches this; the `launchctl list` probe is
  the flaky part (false-negative while `flutter run` holds the device).
- **Screenshots:** wait ~6s after the launch signal before capturing, so the
  shot shows the rendered UI, not the native splash. A splash screenshot is
  misleading evidence even when the gate is correctly green.
- Each check keeps a **negative control** (force-stop / terminate before launch)
  and writes a **fresh per-run log**, so a positive signal proves *this* run.

## BDD scenario authoring standard (from A2 Task 4)

BDD scenarios are authored as `.feature` files (Gherkin syntax) under
`apps/mobile/integration_test/` and generated into on-device integration tests
by `bdd_widget_test` + `build_runner` (version 2.1.4+).

- **Mode: on-device integration tests.** `bdd_widget_test` detects that a
  `.feature` file lives inside `integration_test/` AND that `integration_test`
  is a dev dependency, and automatically emits
  `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` plus the
  `integration_test` import in the generated `*_test.dart`.
- **Step definitions** live in `test/step/` (shared across widget and
  integration tests via `stepFolderName: step` in `apps/mobile/build.yaml`).
- **Generated files are committed** to the repository (idempotent; regenerate
  with `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`).
  The gate does NOT run `build_runner` — it runs the committed generated tests
  directly via `verify_integration_android`/`verify_integration_ios`.
- **From A3 onwards**, every new BDD scenario is authored as a `.feature` file
  first; the generated `*_test.dart` is committed alongside. Hand-written
  integration tests are used only for non-BDD cases (e.g. real-plugin paths).

## Known limitations / future hardening

1. **Patch checks should exercise the code path, not just grep for a string.**
   `step-0.sh` greps for the shim text as a proxy; a partially-applied patch could
   pass the grep. Mitigated today by the runtime `nx show project` assert. Prefer
   a check that runs the patched path.
2. **Back-to-back device runs** can still degrade the emulator (port/DDS
   exhaustion). Give a cooldown between full script runs; the per-platform
   signals above tolerate a single degraded run, but a fresh device is best.
3. **Programmatic on-device UI validation — RESOLVED.** Feature steps now ship an
   `integration_test` that asserts the rendered widget tree on each device (see
   "On-device UI" above); the screenshot is corroborating only. (`gfxinfo "Total
   frames rendered"` does not track Flutter/Impeller, so it must not be used as a
   render signal — it was removed.)
4. **`verify_integration` infra-vs-real retry — RESOLVED.** Retry is now decided
   by `_is_infra_only_failure`: a failure is retried only when the log shows a
   build/load/connection problem AND contains **no** `TestFailure` /
   `EXCEPTION CAUGHT BY FLUTTER TEST` (the reliable marker of a real assertion
   failure) — NOT by the `[E]` marker, which transient infra errors also print.
   On a `device offline` infra failure the helper first runs `_android_recover`
   (reconnect, else cold-boot) before retrying (up to 3 attempts). This still
   never retries a real assertion failure. Multi-test-per-platform evidence logs
   are written per `(platform, test-file)` so runs no longer overwrite each other
   (rule 8).
5. **Real-plugin RUNTIME tests cannot be gated via `flutter test`.** A test that
   drives the REAL `permission_handler` / `camera` plugins at runtime cannot pass
   under `flutter test`: the real permission request raises the OS permission
   dialog (Android `GrantPermissionsActivity`; iOS the system alert), which the
   `integration_test` driver cannot tap, and `flutter test`'s install→run→
   **uninstall** lifecycle leaves no window to pre-grant (a pre-grant is wiped by
   the next run's fresh install). On Android the camera2 API additionally requires
   the OS runtime CAMERA grant, so a real preview can never render there. The gate
   therefore exercises the real plugins only by **compiling + linking** them into
   every on-device build (the BDD device builds), and asserts behavior via the
   `ScanDependencies` fake-injection seam (deterministic, dialog-free). The real
   *runtime* camera/preview is verified **manually** via
   `apps/mobile/tool/manual_real_camera_check.sh`, which installs the APK with
   `adb install -g` (grants CAMERA at install, bypassing the dialog) and launches
   the app for visual inspection. A fully-automated real-plugin gate would require
   native UIAutomator/Espresso instrumentation (outside Flutter's
   `integration_test`) — deferred as future hardening.

   **Planned (A3+): opt-in real-device smoke lane.** When physical devices are
   connected, an opt-in lane (`REAL_DEVICE=1`) will run the real-plugin paths on
   hardware — Android pre-granted via `adb pm grant` for a real-camera gate; iOS
   real camera as a manual "Allow once" observed check (no simulator camera
   exists). It stays SEPARATE from the always-on fast gate (unit + widget +
   BDD-with-fakes) and runs pre-release / on demand, not per-commit. Its payoff
   begins at **A3 (capture → image)** where real image bytes, file I/O, and
   rendering matter — so it is wired in then, not at A2 (preview-only).
