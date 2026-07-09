# In-App Feedback → GitHub Issue — Design

**Date:** 2026-07-09
**Status:** Approved design, pending spec review
**Repo target:** `pablohpsilva/camscanner-light` (PUBLIC) — see Privacy section

## Goal

Let a user tap a button in the app, write feedback, and have that feedback
automatically become a GitHub issue on the project — **without ever shipping a
GitHub credential inside the app**, and without requiring the user to have a
GitHub account.

## Non-goals (YAGNI)

- No screenshot/file attachments in v1 (user-initiated upload adds complexity and
  privacy risk; revisit later).
- No in-app viewing of existing issues or reply threads.
- No user authentication / accounts.
- No app-attestation (Play Integrity / App Attest) in v1 — Turnstile + rate
  limits are the chosen defense tier; attestation is a documented future upgrade.

## Architecture

Three parts. The secret lives only in the middle tier.

```
┌──────────────┐   HTTPS POST     ┌───────────────────────┐   GitHub REST     ┌──────────────┐
│  Flutter app  │ ───────────────> │  Cloudflare Worker     │ ────────────────> │  GitHub repo  │
│  feedback form│  message + meta  │  - verify Turnstile    │  create issue     │  issues       │
│  + Turnstile  │  + Turnstile tok │  - rate limit + caps   │  (token = secret) │               │
│               │                  │  - validate content    │                   │               │
│               │                  │  - create issue        │                   │               │
└──────────────┘                  └───────────────────────┘                   └──────────────┘
```

- **GitHub token** is a Cloudflare Worker secret. Never in the app, never in git.
- The app ships only the **Worker URL** and the **public Turnstile site key** —
  both safe to embed.
- All trust and validation live in the Worker; the app is untrusted input.

### Trust boundary

The app is a public client — anyone can decompile the IPA/APK, recover the Worker
URL, and craft requests. Therefore the Worker treats every request as hostile
until it passes: (1) Turnstile human/app proof, (2) rate/volume gates, (3) strict
content validation. The Worker fails closed.

## Privacy

The target repo is **public**, so every created issue is world-readable.

- **Diagnostics** collected are non-personal (app version+build, OS version,
  device model, locale). **No scanned-document data, no file paths, no content
  from the user's library is ever collected or transmitted.**
- **Optional email:** the form field carries an explicit inline warning —
  *"Optional. This will be publicly visible on GitHub."* The Worker writes it into
  the issue body **lightly obfuscated** (e.g. `user [at] example.com`) to reduce
  automated scraping. This is a deliberate, user-consented trade-off (see decision
  log).
- The diagnostics that will be sent are shown to the user in a **transparent,
  expandable preview** on the form — nothing is collected invisibly.

## App side (Flutter)

Follows existing DI conventions: a const-constructible `FeedbackDependencies`
class holding factory typedefs for each collaborator, wired to production defaults
and overridable from `runCamScannerApp` in `main.dart` for tests.

### Entry point
- A `⋮` (overflow) `PopupMenuButton` added to the **normal** app bar in
  `lib/features/library/home_screen.dart` (`_buildNormalAppBar`), with a
  "Send feedback" item. Leaves room for future "About"/"Donate" items.

### New feature folder: `lib/features/feedback/`
- **`feedback_dependencies.dart`** — factory typedefs (`FeedbackServiceFactory`,
  device/package info providers), production wiring, test overrides.
- **`feedback_screen.dart`** — the form:
  - **Category** dropdown: `Bug` / `Idea` / `Question` (maps to GitHub labels).
  - **Message** multiline field — **required**, capped (e.g. 4000 chars).
  - **Email** field — optional, format-validated when non-empty, with the public
    visibility warning shown inline.
  - **Diagnostics preview** — expandable, shows exactly what will be sent.
  - **Turnstile** widget (invisible/managed) producing a token on submit.
  - **Submit** button with loading state.
- **`feedback_service.dart`** — `FeedbackService`:
  - Gathers diagnostics via `package_info_plus` + `device_info_plus`.
  - Builds the JSON payload `{ category, message, email?, turnstileToken,
    diagnostics{...} }`.
  - POSTs to the Worker URL over HTTPS via an injected `http.Client`.
  - Maps the response to a `FeedbackResult` sealed type:
    `success(issueUrl?) | rateLimited | invalid | offline | serverError`.
  - Holds **no secrets**.
- **`feedback_config.dart`** — compile-time Worker URL + Turnstile site key
  (via `--dart-define`, mirroring how config is handled elsewhere; safe to ship).

### New dependencies
- `http` (HTTP client), `package_info_plus`, `device_info_plus`, and a Flutter
  Cloudflare Turnstile widget package (evaluate a maintained one; fall back to a
  thin `WebView`-hosted Turnstile if no suitable package).

## Worker side (Cloudflare)

Single `POST /feedback` handler (all other routes → 405). Pseudocode order:

1. **Method/Content-Type guard** — POST + `application/json` only.
2. **Body size guard** — reject bodies over a small cap (e.g. 16 KB).
3. **Turnstile siteverify** — POST token + remote IP to Cloudflare; reject on
   failure (bot/invalid).
4. **Rate limiting**
   - Per-IP: e.g. max 3 submissions/hour (KV counter or Workers rate-limit
     binding).
   - Global daily cap: circuit breaker (e.g. N/day) to bound a flood; over-cap →
     429.
5. **Content validation** — required `message` (non-empty, ≤ cap), `category` in
   the allowed enum, optional `email` matches a simple pattern, diagnostics fields
   are the expected shape and length-bounded; strip control characters.
6. **Create issue** — `POST /repos/{owner}/{repo}/issues` with the secret token:
   - Title derived from category + a short slug of the message.
   - Body: the message, a fenced diagnostics block, and obfuscated email if given.
   - Labels: the category label + a machine label `app-feedback`.
7. **Respond** — minimal JSON `{ ok, issueUrl? }` on success; typed error codes
   otherwise. Never echo the token or raw internal errors.

### Config (Wrangler secrets/vars)
- Secrets: `GITHUB_TOKEN` (fine-grained PAT scoped to issues on this repo only),
  `TURNSTILE_SECRET`.
- Vars: `REPO` (`pablohpsilva/camscanner-light`), rate/cap limits, allowed
  categories.
- KV namespace (or rate-limit binding) for counters.

### Least privilege
The GitHub token is a **fine-grained PAT** with **Issues: write** on **only this
repo** — nothing else. If the Worker URL is abused, worst case is spam issues on
one repo, closeable/deletable, with no access to code or other repos.

## Error handling

- **App:** offline → "Check your connection and try again"; 429 → "You've sent a
  few already — please try again later"; 4xx invalid → "Please check your
  message"; 5xx → "Couldn't send right now, try again." The typed message is
  **preserved in the form** on failure so nothing the user wrote is lost.
- **Worker:** fail closed — any validation miss rejects. Structured logs without
  PII. GitHub API failure → 502 to the app; the secret and internal detail never
  leave the Worker.

## Testing (non-negotiable: TDD + BDD, Android AND iOS)

### TDD — host tests (`flutter test`)
- `FeedbackService`: payload construction (categories, optional email present/
  absent, diagnostics shape) and response→`FeedbackResult` mapping, driven by a
  **fake `http.Client`**. Written test-first (red → green).
- `FeedbackScreen` widget tests: required-message validation, email format
  validation, char cap, diagnostics preview toggle, submit disabled while
  in-flight — with a fake `FeedbackService`.

### BDD — `.feature`
- `test/features/feedback/feedback.feature` (Gherkin) with `bdd_widget_test`
  generating `*_test.dart`, steps shared in `test/step/`:
  - Submitting valid feedback shows a success state.
  - Empty message blocks submission.
  - Offline shows the connection error and keeps the typed message.
  - Rate-limited shows the friendly retry message.
- Regenerate via `dart run build_runner build --delete-conflicting-outputs`.

### Device tests — real Android AND real iOS
- `integration_test/feedback_submit_device_test.dart` points at a **staging
  Worker** (which creates issues in a **test repo**, not production) and asserts a
  successful submission round-trips — proving `package_info_plus`,
  `device_info_plus`, Turnstile, and TLS networking work natively on **both**
  platforms. Run with `-d <device-id>` on each. Any platform where this can't run
  is named as an explicit gap, never silently skipped.

### Worker tests
- Unit tests (Vitest + Miniflare/`workers` test runner): Turnstile-reject path,
  per-IP rate-limit, global cap, content validation (missing/oversized/bad
  category/bad email), and issue creation with a **mocked** GitHub fetch. No live
  GitHub calls in CI.

## Deliverables / repo layout

- `lib/features/feedback/` — Flutter feature (files above).
- Overflow-menu entry in `home_screen.dart`.
- `worker/` (or a sibling location TBD-with-user) — Cloudflare Worker source,
  `wrangler.toml`, Worker unit tests, and a README covering secret setup and
  staging vs production config.
- Tests as listed under Testing.

## Decision log

- **Serverless proxy** chosen over no-backend URL-prefill (real users lack GitHub
  accounts) and over an existing backend (none). Cloudflare Workers chosen for
  free tier, no cold start, built-in Turnstile/KV/rate-limiting.
- **Abuse defense tier:** Turnstile + rate limit + caps + content validation. App
  attestation deferred as a future upgrade.
- **Payload:** free-text message + non-personal diagnostics + category picker.
  Screenshot attachment deferred.
- **Optional email** included, with public-visibility warning + Worker-side
  obfuscation, because the target repo is public and the user accepted this
  trade-off.
- **Same (public) repo** for issues, per user decision, rather than a dedicated
  private feedback repo.

## Open items to resolve during planning

- Exact Worker source location in this monorepo (`worker/`, `apps/worker/`, or a
  separate repo).
- Choice of Flutter Turnstile widget package vs. a WebView-hosted fallback.
- Concrete numeric limits (per-IP rate, global daily cap, message length).
