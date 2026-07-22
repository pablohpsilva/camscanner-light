# LLM efficiency guardrails — design

Date: 2026-07-22
Status: Approved (design), pending implementation plan
Branch: `chore/llm-guardrails`

## Goal

Make an LLM working on this repo more efficient along four axes the maintainer
identified, without losing any of the hard-won knowledge already captured in
`CLAUDE.md` and the memory index:

1. **Fewer hallucinations / wrong facts** — invented APIs, misremembered
   architecture, "should work" claims.
2. **Catch flaws proactively** — architecture smells, security holes, code that
   should be refactored.
3. **Lower per-session context cost** — the 12.3K `CLAUDE.md` loads every
   session; much of it is release-only detail.
4. **Ship the smallest, correct build** — no stale-Debug installs, no
   multi-step nightmares, verifiable Release artifacts.

Mechanism (maintainer's choice): **balanced mix** — a couple of cheap, safe
hooks that can block; the rest as structure + guidance the LLM is told to
follow. `CLAUDE.md` gets **split** into a lean always-loaded core plus
load-on-demand detail docs.

## Non-goals

- No Stop-hook self-audit (the `r-u-sure` / `verification-before-completion`
  skills already cover this; a hook would be noisy).
- No auto-`flutter analyze` on every edit (too slow to block on).
- No unrelated refactoring of app code. This change touches docs, `.claude/`
  config, and small scripts only — **no `lib/` source changes**, so the
  TDD+BDD+both-platforms gate does not apply to this work (there is no
  user-facing app behavior to test). Scripts get a lightweight smoke check.

## Deliverables

### A. Split `CLAUDE.md` → lean core + `docs/claude/` detail docs

**Lean `CLAUDE.md`** (target ~60 lines, always loaded) keeps, **verbatim**:
- the two `NON-NEGOTIABLE` sections (TDD+BDD; subagent decomposition),
- a compact Commands block,
- a compact Architecture map (DI / Drift+FTS5 / image pipeline — one tight
  paragraph each, as today),
- the host/device testing one-liner,

and **adds**:
- a **"Load-on-demand detail docs"** index pointing at the files below,
- the **Ground rules** section (deliverable B),
- a one-line pointer to the **review checklist** (deliverable C),
- the rule: *"Before any release / device-install / IAP task, read the matching
  `docs/claude/` doc — do not reproduce its steps from memory."*

**`docs/claude/` detail docs** (loaded only when the task matches). Content is
moved **verbatim** out of today's `CLAUDE.md`, not rewritten, to avoid drift:
- `docs/claude/ios-release.md` — TestFlight bump→build→upload, distribution
  signing recovery, IAP tip-jar App Store Connect prereqs, "must ship Release".
  (Source: current `CLAUDE.md` lines 168–237.)
- `docs/claude/device-install.md` — `flutter install` does-not-build trap,
  Debug-vs-Release artifact verification, launch-crash diagnosis.
  (Source: current `CLAUDE.md` lines 132–166.)
- `docs/claude/android-release.md` — `scripts/build-release.sh` + symbols.
  (Source: current `CLAUDE.md` lines 239–241.)

Acceptance: no fact present in today's `CLAUDE.md` is lost; it is either in the
lean core or in exactly one `docs/claude/` file, and the lean core links to it.

### B. Ground rules (anti-hallucination) — new section in lean core

Short, imperative bullets:
- Verify a file/symbol **exists** (Read/Grep) before referencing it in code or
  in a claim.
- Quote the actual command + its output before "done/fixed/passing".
- Name the platform on every verification claim: host-green ≠ device-verified.
- An empty `grep`/`rg` is **not** proof of absence (rtk proxy hides some
  matches) — confirm negatives with `Read`.

### C. Repo-specific review checklist — `docs/claude/review-checklist.md`

A catalogue of *this* codebase's real, recurring failure modes (distilled from
the memory index) so review is targeted, not generic. Seeded entries:
- absolute paths persisted (iOS container GUID changes) — must store relative,
- native-isolate OOM (uncatchable) — respect the 12.5MP camera cap / timeouts,
- DB opened on a spawned isolate hangs — open on the root isolate,
- EXIF double-orientation (Flutter honors Orientation),
- derivative-file naming keyed to live position → cross-page collisions,
- bare fire-and-forget futures (must be `unawaited(...)` per the lint),
- R8 keep rules for scanner / mlkit / gms classes (Release-only breakage),
- silent StoreKit zero-products (IAP prereqs) rendering "tips unavailable",
- host-vs-device gap stated silently instead of named,
- `git add -A` contaminating a commit with the long-lived WIP pile.

Lean core adds one line: *"When you touch persistence / native pipeline /
build / IAP, consult `docs/claude/review-checklist.md` before and after."*

### D. Build verification — `scripts/verify-artifact.sh`

One command that, given a built `.app` / `.ipa` / `.apk` (or the default iOS
build path), asserts it is a **Release** artifact (not a Debug stub — checks
`App.framework/App` is a multi-MB AOT dylib and that `kernel_blob.bin` /
`*_snapshot_data` are absent) and prints the artifact size. Exit non-zero on a
Debug artifact. Turns the manual check in today's `CLAUDE.md` into something
runnable, and is the mechanism the install-guard hook (E1) calls.

### E. Hooks — `.claude/settings.json` (checked in, shared)

Exactly two, both cheap and safe (fast, and they block with an explanatory
message rather than silently). Placed in a **new** `.claude/settings.json`
(project-shared) — distinct from the existing personal `settings.local.json`.

1. **`flutter install` guard** (PreToolUse, Bash matcher). When the command is a
   `flutter install`, run `scripts/verify-artifact.sh`; if the artifact is a
   stale Debug stub (or missing), block with the reason and the "build first"
   command. Kills the "opens then closes" stale-Debug trap.
2. **Commit guard** (PreToolUse, Bash matcher on `git commit` / `git add`).
   Block when the staged/added set contains obvious secrets (`.p8`,
   `apiKey`/`apiIssuer`/app-specific-password literals) and warn (non-blocking)
   on `git add -A` / `git add .` (the WIP-pile contamination hazard).

Hooks must fail open on their own internal errors (never wedge the session) and
must be fast (< ~1s; no `flutter analyze`, no network).

## Testing / verification for this change

No `lib/` behavior changes, so no widget/integration tests. Instead:
- **Docs:** grep-diff old vs new to prove no `CLAUDE.md` fact was dropped.
- **`verify-artifact.sh`:** smoke-test against a known Debug and (if available)
  Release artifact, or a crafted fixture; confirm exit codes.
- **Hooks:** dry-run the hook scripts against sample commands (a stale-Debug
  install, a `git commit` with a fake `.p8`, a `git add -A`) and confirm
  block/warn/allow decisions. Paste the outputs before claiming done.

## Task decomposition (independent, parallelizable)

Per the repo's decomposition rule, implementation splits into tasks with no
shared state:
- **T1** Extract `docs/claude/{ios-release,device-install,android-release}.md`
  verbatim from `CLAUDE.md`.
- **T2** Rewrite lean `CLAUDE.md` (core + Ground rules + doc index + checklist
  pointer). Depends on T1 only for the link targets' paths (known up front, so
  effectively independent).
- **T3** Write `docs/claude/review-checklist.md`.
- **T4** Write `scripts/verify-artifact.sh` + smoke test.
- **T5** Write `.claude/settings.json` hooks + hook scripts + dry-run tests.
  Depends on T4 (calls `verify-artifact.sh`).

T1, T3, T4 are fully independent; T2 and T5 have only path-level dependencies.
