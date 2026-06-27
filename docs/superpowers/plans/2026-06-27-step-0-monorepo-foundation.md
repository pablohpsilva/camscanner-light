# Step 0 — Monorepo Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a runnable Nx monorepo containing one Flutter app (`apps/mobile`) that launches a blank screen on iOS and Android.

**Architecture:** An Nx workspace (pnpm, integrated) at the repo root manages projects. The Flutter app is a first-class Nx project via the `@nxrocks/nx-flutter` plugin, exposing `run`/`build`/`test`/`lint` targets. No product features — this proves the workspace, tooling, and build pipeline every later step depends on.

**Tech Stack:** Nx, pnpm, `@nxrocks/nx-flutter`, Flutter (Dart), iOS + Android toolchains.

## Global Constraints

Copied verbatim from `docs/superpowers/specs/00-overview-roadmap.md`. Every task implicitly includes these.

- **TDD/BDD first, always** — tests/specs before implementation.
- **SOLID, KISS, DRY** for every feature, class, component, function.
- **Definition of Done (binding):** nothing is "done" until every acceptance criterion maps to a passing test (TDD unit/widget + BDD where user-facing), the full suite is run and **observed** green, quality gates (analyze/lint) pass, and the work is **reviewed and double-checked** with evidence. "Looks right" / "should pass" is not done.
- **Privacy spine:** documents never leave the device (no cloud/network for document data).
- **Package manager:** pnpm.
- **Flutter app project name:** `mobile` (folder `apps/mobile`).
- **Bundle / package ID:** `com.camscannerlight.mobile`.
- **Organization identifier:** `com.camscannerlight`.
- **Platforms generated now:** iOS + Android only.

**Note on Step 0 & TDD:** Step 0 produces no app logic, so its gate is **verification-by-evidence** (commands run, output shown) plus the **default Flutter widget test** that the generator creates. The first hand-written TDD cycle begins at Task A1 (next plan).

## Progression Gate (binding)

**Do not start the next step's plan until this one is fully done.** "Done" means
every acceptance checkbox in the matching spec is **developed, tested, fulfilled,
and working** — observed green, quality gates clean, reviewed and double-checked.
Each step lives in its **own plan file** (see `00-plans-index.md`), and code is
split across **multiple focused, single-responsibility files** (SOLID) — never
one large file. The next plan (Task A1) is written **only after** Step 0 passes
this gate.

---

### Task 1: Verify the local toolchain

**Files:** none (environment check).

**Interfaces:**
- Consumes: nothing.
- Produces: a verified Flutter + Node + pnpm environment for later tasks.

- [ ] **Step 1: Verify Flutter, a device, Node, and pnpm are installed**

Run:
```bash
flutter --version
flutter doctor
node --version
pnpm --version
```
Expected: `flutter --version` prints a Flutter 3.x+ version; `flutter doctor` shows checkmarks for the Android toolchain and (on macOS) Xcode with no blocking ✗; `node --version` ≥ v20; `pnpm --version` ≥ 9.

- [ ] **Step 2: Confirm at least one iOS simulator and one Android emulator are available**

Run:
```bash
flutter emulators
xcrun simctl list devices available | grep -i iphone   # macOS only
```
Expected: at least one Android emulator listed, and at least one available iPhone simulator.

If any check fails, stop and install the missing toolchain before continuing. These are prerequisites, not part of the build.

---

### Task 2: Initialize the Nx workspace (pnpm)

**Files:**
- Create: `package.json`
- Create: `nx.json`
- Create: `pnpm-workspace.yaml`
- Modify: `.gitignore` (already present; ensure Nx/Flutter entries)

**Interfaces:**
- Consumes: verified pnpm from Task 1.
- Produces: a working `pnpm nx` CLI at the repo root; `apps/` as the Nx app location.

- [ ] **Step 1: Create the root package.json**

Create `package.json`:
```json
{
  "name": "camscanner-light",
  "version": "0.0.0",
  "private": true,
  "packageManager": "pnpm@9.0.0",
  "devDependencies": {}
}
```

- [ ] **Step 2: Add Nx and the Flutter plugin as dev dependencies**

Run:
```bash
pnpm add -D nx@latest @nxrocks/nx-flutter@latest
```
Expected: pnpm installs `nx` and `@nxrocks/nx-flutter`; a `pnpm-lock.yaml` is created and `node_modules/.bin/nx` exists.

- [ ] **Step 3: Create the Nx configuration**

Create `nx.json`:
```json
{
  "$schema": "./node_modules/nx/schemas/nx-schema.json",
  "namedInputs": {
    "default": ["{projectRoot}/**/*"],
    "production": ["default"]
  },
  "targetDefaults": {},
  "plugins": ["@nxrocks/nx-flutter"]
}
```

- [ ] **Step 4: Create the pnpm workspace file**

Create `pnpm-workspace.yaml`:
```yaml
packages:
  - "apps/*"
  - "libs/*"
```

- [ ] **Step 5: Verify the Nx CLI runs**

Run:
```bash
pnpm nx report
```
Expected: prints Nx version and the registered `@nxrocks/nx-flutter` plugin without error.

- [ ] **Step 6: Commit**

```bash
git add package.json pnpm-lock.yaml nx.json pnpm-workspace.yaml .gitignore
git commit -m "chore: initialize Nx workspace with pnpm and nx-flutter plugin"
```

---

### Task 3: Generate the Flutter app at apps/mobile

**Files:**
- Create: `apps/mobile/**` (generated Flutter project)
- Create: `apps/mobile/project.json` (Nx project, generated by the plugin)

**Interfaces:**
- Consumes: the Nx workspace and `@nxrocks/nx-flutter` from Task 2.
- Produces: an Nx project named `mobile` with `run`, `build`, `test`, `analyze`/`lint` targets; org `com.camscannerlight`; platforms android + ios.

- [ ] **Step 1: Inspect the generator's options (flags can vary by plugin version)**

Run:
```bash
pnpm nx g @nxrocks/nx-flutter:application --help
```
Expected: prints supported options. Confirm the names of the `directory`, `org`, and `platforms` (or `template`) options before running the generator; adjust the next step's flags to match exactly what `--help` reports.

- [ ] **Step 2: Generate the Flutter application**

Run (adjust flag names to match Step 1 if the plugin version differs):
```bash
pnpm nx g @nxrocks/nx-flutter:application mobile \
  --directory=apps/mobile \
  --org=com.camscannerlight \
  --platforms=android,ios \
  --no-interactive
```
Expected: creates `apps/mobile` with a standard Flutter project (`lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml`, `android/`, `ios/`) and an Nx `project.json`.

- [ ] **Step 3: Confirm the Nx project is recognized**

Run:
```bash
pnpm nx show project mobile
```
Expected: prints the `mobile` project with targets including `run`, `build`, `test`, and `analyze` (or `lint`).

- [ ] **Step 4: Fetch Dart/Flutter dependencies**

Run:
```bash
cd apps/mobile && flutter pub get && cd -
```
Expected: `Got dependencies!` with no errors.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile package.json pnpm-lock.yaml nx.json
git commit -m "feat: generate Flutter app at apps/mobile via nx-flutter"
```

---

### Task 4: Lock the bundle ID and platform scope

**Files:**
- Modify: `apps/mobile/android/app/build.gradle` (or `build.gradle.kts`) — `applicationId`
- Modify: `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` — `PRODUCT_BUNDLE_IDENTIFIER`
- Verify: no `web/`, `windows/`, `macos/`, `linux/` platform folders remain
- Verify: `.gitignore` excludes Flutter build artifacts

**Interfaces:**
- Consumes: the generated app from Task 3.
- Produces: an app whose iOS and Android bundle IDs are exactly `com.camscannerlight.mobile`, restricted to iOS + Android.

- [ ] **Step 1: Confirm/set the Android applicationId**

Open `apps/mobile/android/app/build.gradle` (or `.kts`) and ensure:
```gradle
applicationId = "com.camscannerlight.mobile"
```
(If the generator used `com.camscannerlight` + app name and the result already equals `com.camscannerlight.mobile`, leave it; otherwise set it to exactly that.)

- [ ] **Step 2: Confirm/set the iOS bundle identifier**

Run:
```bash
grep -n "PRODUCT_BUNDLE_IDENTIFIER" apps/mobile/ios/Runner.xcodeproj/project.pbxproj
```
Ensure each value is `com.camscannerlight.mobile` (Runner target). Edit the file to that value if it differs.

- [ ] **Step 3: Remove any non-iOS/Android platform folders**

Run:
```bash
ls apps/mobile
rm -rf apps/mobile/web apps/mobile/windows apps/mobile/macos apps/mobile/linux 2>/dev/null || true
```
Expected: only `android/` and `ios/` platform folders remain.

- [ ] **Step 4: Ensure Flutter build artifacts are ignored**

Confirm `.gitignore` contains (add any missing lines):
```
apps/mobile/.dart_tool/
apps/mobile/build/
apps/mobile/ios/Pods/
apps/mobile/.flutter-plugins
apps/mobile/.flutter-plugins-dependencies
```

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/android apps/mobile/ios .gitignore
git commit -m "chore: set bundle id com.camscannerlight.mobile and restrict to iOS+Android"
```

---

### Task 5: Verify the Definition of Done and gate Step 0

This task closes the spec's acceptance checkboxes. Each is closed only by observed evidence.

**Files:** none (verification + commit).

**Interfaces:**
- Consumes: the configured app from Tasks 3–4.
- Produces: a verified, committed Step 0 foundation ready for Task A1.

- [ ] **Step 1: Static analysis is clean**

Run:
```bash
pnpm nx run mobile:analyze
```
(If the plugin names the target `lint`, run `pnpm nx run mobile:lint`.)
Expected: completes with **no analyzer errors**. → closes *"`nx run mobile:analyze` passes with no errors."*

- [ ] **Step 2: The generated default widget test passes**

Run:
```bash
pnpm nx run mobile:test
```
Expected: the default `widget_test.dart` passes (All tests passed). This is Step 0's automated test gate.

- [ ] **Step 3: App launches on an Android emulator**

Run (start an emulator first if needed via `flutter emulators --launch <id>`):
```bash
pnpm nx run mobile:run
```
Expected: the app builds and launches on the Android emulator showing a blank/placeholder screen, no crash. Capture the result (screenshot/log). → contributes to *"launches … without crashing"* and *"shows a blank/placeholder screen."*

- [ ] **Step 4: App launches on an iOS simulator (macOS)**

Run (boot a simulator first if needed via `open -a Simulator`):
```bash
pnpm nx run mobile:run
```
Selecting the iOS simulator as the target. Expected: builds and launches on the iPhone simulator, blank screen, no crash. → completes *"launches on an iOS simulator AND an Android emulator without crashing."*

- [ ] **Step 5: Confirm the repo state**

Run:
```bash
git status
git log --oneline -5
```
Expected: working tree clean; the generated workspace is committed. → closes *"Repo is a git repo with a proper `.gitignore` and the workspace committed."*

- [ ] **Step 6: Tick the spec checkboxes and double-check**

Open `docs/superpowers/specs/2026-06-27-step-0-monorepo-foundation-design.md` and tick each acceptance checkbox now backed by evidence from Steps 1–5. Re-run Step 1 and Step 2 once more to confirm nothing regressed (double-check). Commit:
```bash
git add docs/superpowers/specs/2026-06-27-step-0-monorepo-foundation-design.md
git commit -m "docs: close Step 0 acceptance criteria (verified)"
```

---

## Self-Review

**1. Spec coverage** (`2026-06-27-step-0-monorepo-foundation-design.md`):
- Nx workspace init → Task 2. Plugin install/register → Task 2. Flutter app at `apps/mobile` as Nx project → Task 3. Git + `.gitignore` → already initialized; Tasks 2/4 maintain it. Acceptance criteria (run on iOS+Android, blank screen, analyze clean, committed) → Task 5. Config values (pnpm, name `mobile`, bundle id, org, iOS+Android) → Tasks 2–4 / Global Constraints. All covered.

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"write tests for the above". The one variable point — exact `nx-flutter` generator flag names — is handled by an explicit `--help` verification step (Task 3 Step 1), not a vague instruction.

**3. Type consistency:** Project name `mobile`, target names `run`/`build`/`test`/`analyze` (with `lint` fallback noted), bundle id `com.camscannerlight.mobile`, org `com.camscannerlight` used consistently across Tasks 2–5.
