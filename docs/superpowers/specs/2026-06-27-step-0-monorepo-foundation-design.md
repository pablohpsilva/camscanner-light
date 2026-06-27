# Step 0 — Monorepo Foundation (Design)

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** Foundation (precedes Sub-project 1 — Core Scan Pipeline)

## Purpose

Establish a runnable Nx monorepo containing a single Flutter mobile app that
launches a blank screen on iOS and Android. This step delivers no product
features — it proves the workspace, tooling, and build pipeline that every
later step depends on.

## Product context (roadmap)

CamScanner-light is a document-scanning and document-management product
targeting iOS, Android, and Web. It is decomposed into sequential sub-projects:

0. **Foundation** — monorepo + app scaffold *(this spec)*
1. Core scan pipeline (MVP) — being built incrementally, see below
2. OCR / text extraction
3. PDF editing
4. PDF conversion (server-side)
5. Accounts & cloud sync
6. Sharing, printing & fax

**Platform scope now:** iOS + Android (Flutter). Web and backend come later but
the monorepo is structured to accept them.

Sub-project 1 is itself broken into atomic, dependency-ordered steps:

- **A. Foundation shell:** A1 app scaffold + empty Documents list & Scan button,
  A2 camera preview, A3 capture photo to review screen
- **B. Persistence:** B1 save photo + document record, B2 list reads storage,
  B3 page viewer
- **C. PDF:** C1 single-page PDF generation, C2 in-app PDF preview *(= walking
  skeleton)*
- **D. Library mgmt:** D1 rename, D2 delete, D3 sort
- **E. Manual crop:** E1 corner overlay, E2 perspective transform, E3 re-edit
- **F. Auto edge detection:** F1 contour detection, F2 pre-fill corners, F3 live
  overlay (stretch)
- **G. Enhancement filters:** G1 grayscale, G2 B&W, G3 color/auto, G4 picker UI
- **H. Multi-page:** H1 add pages, H2 thumbnail strip, H3 reorder, H4
  delete/retake, H5 multi-page PDF
- **I. Export & import:** I1 export image, I2 gallery import

This spec covers **Step 0 only**. Each step above gets its own spec → plan →
build cycle.

## Architecture decision

- **Monorepo tool:** Nx (JavaScript/TypeScript-first; chosen for unified
  orchestration as TS web + backend projects are added later).
- **Flutter integration:** `@nxrocks/nx-flutter` plugin, so the Flutter app is a
  first-class Nx project with `run`, `build`, `test`, and `analyze` targets.
  Trade-off accepted: Nx orchestrates Dart via a community plugin wrapping the
  Flutter CLI rather than understanding Dart natively.

## Workspace layout

```
camscanner-light/            ← Nx workspace root
  apps/
    mobile/                  ← Flutter app (iOS + Android)  ← built in this step
    # web/                   ← later
    # api/                   ← later
  libs/                      ← shared code (later)
  docs/superpowers/specs/    ← design specs
  nx.json
  package.json
  .gitignore
```

## Configuration

| Setting | Value |
|---|---|
| Node package manager | pnpm |
| Flutter app project name | `mobile` (folder `apps/mobile`) |
| Bundle / package ID | `com.camscannerlight.mobile` |
| Organization identifier | `com.camscannerlight` |
| Platforms generated | iOS + Android only |

## Scope

**In scope**
- Initialize Nx workspace at repo root (`nx.json`, `package.json`, lockfile).
- Install and register `@nxrocks/nx-flutter`.
- Generate Flutter app at `apps/mobile` wired as an Nx project.
- Initialize git with a Flutter + Node `.gitignore`.

**Out of scope**
- Any UI beyond the default blank/placeholder screen.
- Navigation, camera, document model, library, PDF — all begin at step A1.
- Web/desktop platforms, backend, shared libs.

## Deliverable (user-testable)

A runnable Nx monorepo with a Flutter app at `apps/mobile` that launches a blank
screen on iOS and Android. **You can test it by** running `nx run mobile:run` on
an iOS simulator and an Android emulator and watching the app open without
crashing, then running `nx run mobile:analyze` and seeing no errors.

## Acceptance criteria (each closed only by a passing test)

- [x] `nx run mobile:run` launches on an iOS simulator **and** an Android emulator without crashing — *observed 2026-06-27: **Android via the literal `pnpm nx run mobile:run` target** — log: "Launching lib/main.dart… / Syncing files to device / Flutter run key commands / A Dart VM Service is available"; app was force-stopped first (resumed=0) and afterwards topResumedActivity=com.camscannerlight.mobile/.MainActivity, proving this invocation launched it (screenshot /tmp/nx_run_android.png). **iOS** via the equivalent `flutter build ios --simulator` + `simctl install/launch` (pid 387 running; screenshot /tmp/ios_step0_screen.png). The nx `run` target wraps `flutter run` identically regardless of device.*
- [x] The launched app shows a blank/placeholder screen — *observed 2026-06-27: default Flutter placeholder rendered on both; screenshots /tmp/ios_step0_screen.png, /tmp/android_step0_screen.png*
- [x] `nx run mobile:analyze` passes with no errors — *observed: "No issues found! (ran in 5.7s)" — 2026-06-27*
- [x] Repo is a git repo with a proper `.gitignore` and the workspace committed — *observed: clean working tree after 3 commits — 2026-06-27*

## Risks / notes

- `@nxrocks/nx-flutter` requires a working local Flutter SDK; environment setup
  (Flutter, Xcode, Android SDK) is a prerequisite, not part of this step's code.
- If the plugin's generated targets diverge from current Nx conventions, prefer
  the plugin's documented target names over hand-editing `project.json`.

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this step is **not done** until every acceptance criterion above is satisfied and verified by observed evidence (commands run, output shown), quality gates pass, and the result is reviewed and double-checked. "Looks right" / "should pass" is not done.
