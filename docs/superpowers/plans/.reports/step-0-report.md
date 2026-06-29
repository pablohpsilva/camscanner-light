# Step 0 Implementation Report

**Date:** 2026-06-27
**Branch:** feat/step-0-monorepo-foundation
**Status:** DONE_WITH_CONCERNS (analyze + test green; device launches pending controller)

---

## Commits

| Hash | Message |
|------|---------|
| f2e345b | chore: initialize Nx workspace with pnpm and nx-flutter plugin |
| bc7fbc0 | feat: generate Flutter app at apps/mobile via nx-flutter |
| f1b6666 | chore: set bundle id com.camscannerlight.mobile and restrict to iOS+Android |
| b1dd134 | docs: close Step 0 acceptance criteria (analyze + test verified) |

---

## Task Outcomes

### Task 2: Nx workspace init

- Created `package.json` with `"packageManager": "pnpm@11.0.9"` (plan said 9.0.0; matched installed version — see Deviations).
- Created `pnpm-workspace.yaml` with `apps/*` and `libs/*` packages; had to add `onlyBuiltDependencies: [nx]` and `allowBuilds: nx: true` to allow nx postinstall scripts (pnpm 11 blocks build scripts by default).
- Installed `nx@20.8.4` and `@nxrocks/nx-flutter@10.0.1` (plan said `nx@latest` which resolved to 23.0.1 — see Deviations).
- Created `nx.json` with plugin registered.
- `pnpm nx report` confirms: nx 20.8.4, @nxrocks/nx-flutter 10.0.1 registered.

### Task 3: Flutter app generation

- Generator is `@nxrocks/nx-flutter:project` (aliases: proj, new, create) — NOT `:application`. The `--help` inspection confirmed this.
- Positional arg is `directory`; used `--name=mobile` separately for the project name.
- `platforms` takes an array; passed as `--platforms=android --platforms=ios`.
- Generated successfully: `apps/mobile` contains `android/`, `ios/`, `lib/`, `test/`, `project.json`.
- `pnpm nx show project mobile` confirms targets: `analyze`, `test`, `run`, `build-apk`, `build-ipa`, etc.
- `flutter pub get` was run automatically by the generator.

### Task 4: Bundle ID and platform scope

- Android `applicationId` in `apps/mobile/android/app/build.gradle.kts` was already `com.camscannerlight.mobile` — generator set it correctly from `--org=com.camscannerlight` + project name `mobile`.
- iOS `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj` was already `com.camscannerlight.mobile` for the Runner target (RunnerTests gets `com.camscannerlight.mobile.RunnerTests`).
- No web/windows/macos/linux platform folders generated (platforms were restricted to android+ios by the generator flag).
- Updated root `.gitignore` to add `apps/mobile/ios/Pods/` (was missing).

### Task 5 (non-device): Quality gates

**mobile:analyze:**
```
Analyzing mobile...
No issues found! (ran in 5.7s)
NX   Successfully ran target analyze for project mobile
```

**mobile:test:**
```
00:00 +0: Counter increments smoke test
00:00 +1: All tests passed!
NX   Successfully ran target test for project mobile
```

Both gates: GREEN.

---

## Deviations from Plan

### 1. nx@latest → nx@20.8.4 (CRITICAL)

The plan says `pnpm add -D nx@latest @nxrocks/nx-flutter@latest`. `nx@latest` resolved to `23.0.1`. `@nxrocks/nx-flutter@10.0.1` imports `@nx/workspace/src/utilities/fileutils` which is not in `@nx/workspace`'s package.json exports. Node.js 24 strictly enforces package exports, causing `ERR_PACKAGE_PATH_NOT_EXPORTED`.

**Resolution:** Downgraded to `nx@20.8.4`, `@nx/devkit@20.8.4`, `@nx/workspace@20.8.4`. Even then the import fails because the subpath was never exported.

**Additional patch:** Applied a runtime patch to two files in the installed plugin:
- `node_modules/.pnpm/@nxrocks+nx-flutter@10.0.1_.../flutter-utils.js`
- `node_modules/.pnpm/@nxrocks+nx-flutter@10.0.1_.../deps-utils.js`

Both files had `const fileutils_1 = require("@nx/workspace/src/utilities/fileutils");` replaced with `const fileutils_1 = { fileExists: require("fs").existsSync };`. This is a trivially correct shim — `fileExists` was just wrapping `fs.existsSync`.

**IMPORTANT:** This patch lives in `node_modules/` and will NOT survive `pnpm install`. The controller must run `pnpm install` followed by re-applying this patch, or use `patch-package` / `.pnpmfile.cjs` to make it persistent. A `.pnpmfile.cjs` hook approach is strongly recommended before any other developer clones and installs.

### 2. Generator name: `application` → `project`

The plan uses `@nxrocks/nx-flutter:application`. The actual generator is `@nxrocks/nx-flutter:project` (aliases: proj, new, create). The plan's `--help` inspection step caught this correctly.

### 3. Generator flag: positional `mobile` is directory, not name

The plan passes `mobile` as the first positional arg assuming it's the project name. The generator schema shows the first positional arg is `directory`. Used `apps/mobile` as positional arg and `--name=mobile` for the project name.

### 4. packageManager version: pnpm@9.0.0 → pnpm@11.0.9

Used the actually-installed pnpm version (11.0.9) in `package.json`'s `packageManager` field to avoid corepack mismatches.

### 5. pnpm-workspace.yaml: extra fields added by pnpm 11

pnpm 11 added `allowBuilds: nx: true` and `onlyBuiltDependencies: [nx]` to allow nx's postinstall script. These are required for nx to compile its native binaries.

---

## Concerns for Controller

1. **BLOCKING — node_modules patch is not persistent.** Any `pnpm install` will revert the two patched files, breaking `pnpm nx` entirely. Recommend adding a `.pnpmfile.cjs` that patches at install time, or using the `patch` field in package.json (pnpm 9+ supports `patchedDependencies`). This must be addressed before the next developer runs install.

2. **nx version pinned at 20.8.4 instead of latest.** The `@nxrocks/nx-flutter` plugin uses a private `@nx/workspace` internal API that was removed from the package exports. Until the plugin is updated to use the public API (or until a patched version is published), nx cannot be upgraded to 21+. Monitor `@nxrocks/nx-flutter` releases.

3. **Mobile:test warning: 4 outdated packages.** The test output shows 4 packages with newer versions incompatible with constraints (`matcher`, `meta`, `test_api`, `vector_math`). These are transitive dev deps from the flutter SDK and are not blocking, but worth noting.

4. **Device launches (Task 5 Steps 3–4) are NOT done.** The controller must verify `pnpm nx run mobile:run` on both an iOS simulator and Android emulator. The `run` target is defined and wired correctly; this is strictly a device-session step.

---

## File Inventory

| File | Status |
|------|--------|
| `package.json` | Created |
| `pnpm-lock.yaml` | Created |
| `pnpm-workspace.yaml` | Created (with pnpm 11 build allowances) |
| `nx.json` | Created + updated by generator |
| `.gitignore` | Updated (added ios/Pods/) |
| `apps/mobile/**` | Generated by nx-flutter:project |
| `apps/mobile/project.json` | Generated (Nx targets) |
| `apps/mobile/android/app/build.gradle.kts` | applicationId = com.camscannerlight.mobile (correct) |
| `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` | PRODUCT_BUNDLE_IDENTIFIER = com.camscannerlight.mobile (correct) |
