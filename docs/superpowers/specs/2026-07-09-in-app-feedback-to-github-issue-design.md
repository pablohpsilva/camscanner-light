# In-App Feedback → GitHub Issue — Design

**Date:** 2026-07-09
**Status:** Approved design (revised), pending spec review
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
- No offline draft persistence across app restarts (message is preserved in the
  live form on a failed send; not saved to disk).

## Architecture

Three parts. The GitHub credential lives only in the middle tier, and the app
proves its authenticity to the Worker before anything reaches GitHub.

```
┌────────────────┐   HTTPS POST         ┌──────────────────────────┐   GitHub REST      ┌──────────────┐
│  Flutter app    │ ───────────────────> │  Cloudflare Worker        │ ─────────────────> │  GitHub repo  │
│  feedback form  │  message + category  │  1. verify attestation    │  create issue      │  issues       │
│  + App Attest / │  + email? + meta     │     (App Attest / Play    │  (GitHub App       │               │
│    Play Integrity│  + attestation tok  │      Integrity) PRIMARY   │   installation     │               │
│  + Turnstile    │  + Turnstile tok     │  2. Turnstile FALLBACK    │   token, minted    │               │
│    (fallback)   │  + idempotency key   │  3. rate limit + caps     │   per request)     │               │
│                 │                      │  4. dedupe idempotency    │                    │               │
│                 │                      │  5. validate + sanitize   │                    │               │
│                 │                      │  6. create issue          │                    │               │
└────────────────┘                      └──────────────────────────┘                    └──────────────┘
```

- **GitHub credential** is a **GitHub App private key**, stored as a Cloudflare
  Worker secret. The Worker mints a **short-lived installation token** per
  request. Never in the app, never in git, never long-lived.
- The app ships only the **Worker URL**, the **public Turnstile site key**, and
  the platform attestation config (safe to embed).
- All trust and validation live in the Worker; the app is untrusted input.

### Trust boundary

The app is a public client — anyone can decompile the IPA/APK, recover the Worker
URL, and craft requests. The Worker treats every request as hostile until it
passes, in order:

1. **Attestation (primary):** App Attest (iOS) / Play Integrity (Android) proves
   the request came from a genuine, unmodified install of *this* app.
2. **Turnstile (fallback):** covers cases where attestation is unavailable
   (e.g. Play Integrity quota exhaustion, older OS, attestation transient
   failure) so legitimate users are never hard-blocked, while bots still face a
   human-proof challenge.
3. **Rate limiting + caps**, **idempotency dedupe**, **content validation +
   sanitization** (below).

The Worker fails closed: if neither attestation nor Turnstile passes, reject.

## Privacy

The target repo is **public**, so every created issue is world-readable.

- **Diagnostics** collected are non-personal (app version+build, OS version,
  device model, locale). **No scanned-document data, no file paths, no content
  from the user's library is ever collected or transmitted.**
- **Optional email:** the form field carries an explicit inline warning —
  *"Optional. This will be publicly visible on GitHub."* The Worker writes it into
  the issue body **lightly obfuscated** (e.g. `user [at] example.com`) to reduce
  automated scraping. Deliberate, user-consented trade-off (see decision log).
- The diagnostics that will be sent are shown to the user in a **transparent,
  expandable preview** on the form — nothing is collected invisibly.

### Disclosure obligations (shipping-blockers)

Collecting email + device diagnostics and transmitting them to Cloudflare and
GitHub must be disclosed:

- **`apps/web/privacy.html`** — add a "Feedback" section: what is collected (email
  if provided, device diagnostics, the message), where it goes (Cloudflare Worker
  → public GitHub issue), and that email will be publicly visible.
- **Apple App Store privacy nutrition labels** — declare "Contact Info → Email
  Address" (optional, user-provided) and "Diagnostics"/"Identifiers" as
  applicable, linked to app functionality, not tracking.
- **Google Play Data Safety** form — declare the same data types, collection
  purpose "App functionality / feedback", not shared for ads.

## Content safety (issue body sanitization)

User-supplied text (message, and email) must not be able to weaponize GitHub
formatting. The Worker:

- **Wraps the raw user message in a fenced code block** in the issue body so
  Markdown does not render, AND neutralizes GitHub notification/reference tokens
  in user text: `@mentions` (would ping arbitrary users) and `#123`
  (cross-links/noises other issues) — e.g. by inserting a zero-width space after
  `@`/`#` or HTML-escaping. This prevents the feedback box from being used to
  spam-notify people or pollute the issue graph.
- Escapes the title similarly (derived from category + a short, sanitized slug).
- Length-bounds and strips control characters from every field before use.

## App side (Flutter)

Follows existing DI conventions: a const-constructible `FeedbackDependencies`
class holding factory typedefs for each collaborator, wired to production defaults
and overridable from `runCamScannerApp` in `main.dart` for tests. (App is **not**
localized today — English strings, consistent with the rest of the app.)

### Entry point
- A `⋮` (overflow) `PopupMenuButton` added to the **normal** app bar in
  `lib/features/library/home_screen.dart` (`_buildNormalAppBar`), with a
  "Send feedback" item. Leaves room for future "About"/"Donate" items.

### New feature folder: `lib/features/feedback/`
- **`feedback_dependencies.dart`** — factory typedefs (`FeedbackServiceFactory`,
  device/package info providers, attestation provider, Turnstile provider),
  production wiring, test overrides.
- **`feedback_screen.dart`** — the form:
  - **Category** dropdown: `Bug` / `Idea` / `Question` (maps to GitHub labels).
  - **Message** multiline field — **required**, capped (e.g. 4000 chars).
  - **Email** field — optional, format-validated when non-empty, with the public
    visibility warning shown inline.
  - **Diagnostics preview** — expandable, shows exactly what will be sent.
  - Hosts the **Turnstile** widget (WebView-based) for the fallback token.
  - **Submit** button with loading state (disabled while in-flight).
- **`attestation_provider.dart`** — thin wrapper producing a platform attestation
  token: App Attest on iOS, Play Integrity on Android (via a maintained plugin or
  a small platform channel). Returns `null` gracefully when unavailable so the
  service can fall back to Turnstile.
- **`feedback_service.dart`** — `FeedbackService`:
  - Gathers diagnostics via `package_info_plus` + `device_info_plus`.
  - Requests an **attestation token**; obtains a **Turnstile token** as fallback.
  - Generates a client **idempotency key** (UUID) per submission attempt.
  - Builds the JSON payload `{ category, message, email?, attestationToken?,
    turnstileToken?, idempotencyKey, diagnostics{...} }`.
  - POSTs to the Worker URL over HTTPS via an injected `http.Client`.
  - Maps the response to a `FeedbackResult` sealed type:
    `success(issueUrl?) | duplicate | rejectedUnverified | rateLimited | invalid |
    offline | serverError`.
  - Holds **no secrets**.
- **`feedback_config.dart`** — compile-time Worker URL + Turnstile site key +
  attestation identifiers (via `--dart-define`; all safe to ship).

### New dependencies
- `http`, `package_info_plus`, `device_info_plus`, `uuid` (idempotency key),
  a Cloudflare Turnstile Flutter widget (or a thin WebView-hosted Turnstile), and
  attestation plugin(s) for App Attest / Play Integrity (or a small platform
  channel if no maintained package fits).

## Worker side (Cloudflare)

Single `POST /feedback` handler (all other routes → 405). Order:

1. **CORS / origin lockdown** — the endpoint is for the native app, not browsers.
   Reject disallowed `Origin` headers and preflights; do not emit permissive CORS
   headers. (Native app requests have no forbidden Origin.)
2. **Method / Content-Type guard** — POST + `application/json` only.
3. **Body size guard** — reject bodies over a small cap (e.g. 16 KB).
4. **Attestation verification (primary)** — verify App Attest / Play Integrity
   token against Apple/Google. On success, request is trusted.
5. **Turnstile siteverify (fallback)** — only if attestation is absent/failed;
   verify the Turnstile token. If neither passes → 401 `rejectedUnverified`.
6. **Idempotency dedupe** — if the idempotency key was seen recently (KV, short
   TTL), return the prior result instead of creating a second issue.
7. **Rate limiting** — per-IP (e.g. 3/hour) + global daily cap (circuit breaker);
   over-cap → 429.
8. **Content validation + sanitization** — required `message` (non-empty, ≤ cap),
   `category` in allowed enum, optional `email` matches a simple pattern,
   diagnostics fields expected shape/length; strip control chars; apply the
   Content-safety rules above.
9. **Mint GitHub App installation token** — using the GitHub App ID + private key
   (Worker secrets), mint a short-lived installation token scoped to the repo.
10. **Create issue** — `POST /repos/{owner}/{repo}/issues`:
    - Title: category + sanitized short slug of the message.
    - Body: fenced+neutralized message, fenced diagnostics block, obfuscated
      email if given.
    - Labels: category label + machine label `app-feedback`.
11. **Respond** — minimal JSON `{ ok, issueUrl?, duplicate? }`; typed error codes
    otherwise. Never echo secrets or raw internal errors. Store the result under
    the idempotency key.

### Config (Wrangler secrets/vars)
- Secrets: `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_INSTALLATION_ID`,
  `TURNSTILE_SECRET`, plus attestation verification config (Apple App Attest root/
  key id; Google Play Integrity service-account/API config).
- Vars: `REPO` (`pablohpsilva/camscanner-light`), rate/cap limits, allowed
  categories.
- KV namespace(s): rate-limit counters + idempotency store.

### Least privilege
The **GitHub App** is installed on **only this repo** with **Issues: write** and
nothing else. Installation tokens are short-lived and auto-expire. If the Worker
URL is abused, worst case is spam issues on one repo — no code access, no other
repos, no long-lived credential to leak.

## Error handling

- **App:** offline → "Check your connection and try again"; 401 unverified →
  "Couldn't verify the app, please try again"; 429 → "You've sent a few already —
  try again later"; duplicate → treat as success (don't alarm the user); 4xx
  invalid → "Please check your message"; 5xx → "Couldn't send right now, try
  again." The typed message is **preserved in the form** on failure so nothing the
  user wrote is lost.
- **Worker:** fail closed. Structured logs without PII. GitHub API failure → 502;
  secrets and internal detail never leave the Worker.

## Testing (non-negotiable: TDD + BDD, Android AND iOS)

### TDD — host tests (`flutter test`)
- `FeedbackService`: payload construction (categories, optional email, diagnostics
  shape, idempotency key, attestation-present vs Turnstile-fallback) and
  response→`FeedbackResult` mapping (incl. `duplicate`, `rejectedUnverified`),
  driven by a **fake `http.Client`** and fake attestation/Turnstile providers.
  Test-first (red → green).
- `FeedbackScreen` widget tests: required-message validation, email format, char
  cap, diagnostics preview toggle, submit disabled while in-flight, email public-
  visibility warning present — with a fake `FeedbackService`.

### BDD — `.feature`
- `test/features/feedback/feedback.feature` with `bdd_widget_test` generating
  `*_test.dart`, steps shared in `test/step/`:
  - Submitting valid feedback shows a success state.
  - Empty message blocks submission.
  - Offline shows the connection error and keeps the typed message.
  - Rate-limited shows the friendly retry message.
  - Unverified (attestation + Turnstile both fail) shows the verify message.
- Regenerate via `dart run build_runner build --delete-conflicting-outputs`.

### Device tests — real Android AND real iOS
- `integration_test/feedback_submit_device_test.dart` points at a **staging
  Worker** (creating issues in a **test repo**) and asserts a successful
  submission round-trips — proving `package_info_plus`, `device_info_plus`,
  **real App Attest / Play Integrity**, Turnstile WebView, and TLS networking work
  natively on **both** platforms. Run with `-d <device-id>` on each. Attestation
  especially cannot be validated on host or simulator for all cases — any platform
  where a path can't run is named as an explicit gap, never silently skipped.

### Worker tests
- Unit tests (Vitest + Miniflare/`workers` runner): attestation-accept and
  -reject, Turnstile-fallback-accept/reject, both-fail→401, per-IP rate-limit,
  global cap, idempotency dedupe (second identical key returns first result, no
  2nd issue), CORS rejection, content validation (missing/oversized/bad category/
  bad email), **@mention/#-injection neutralization**, GitHub-App token minting
  and issue creation with a **mocked** GitHub fetch. No live GitHub calls in CI.

## Deliverables / repo layout

- `lib/features/feedback/` — Flutter feature (files above) + overflow-menu entry
  in `home_screen.dart`.
- `worker/` (or sibling location — see open items) — Cloudflare Worker source,
  `wrangler.toml`, Worker unit tests, README covering GitHub App setup, secret
  setup, attestation config, and staging vs production config.
- **`apps/web/privacy.html`** — add the Feedback disclosure section.
- **Store disclosure checklist** (doc/task): Apple privacy nutrition labels + Play
  Data Safety updates to complete before the release that ships this feature.
- Tests as listed under Testing.

## Decision log

- **Serverless proxy** (Cloudflare Workers) over no-backend URL-prefill (real users
  lack GitHub accounts) and over a non-existent existing backend.
- **Abuse defense:** native attestation (App Attest / Play Integrity) as PRIMARY,
  Turnstile as FALLBACK, plus rate limits, global cap, idempotency, and content
  sanitization. (Upgraded from Turnstile-only after review.)
- **GitHub auth:** **GitHub App** (short-lived installation tokens) over a
  fine-grained PAT (which expires ≤1yr and needs manual rotation).
- **Content safety:** neutralize `@mention`/`#ref` and fence user text to stop
  notification/reference abuse (added after review).
- **Privacy:** update `apps/web/privacy.html` + Apple/Play store disclosures
  (added after review).
- **Idempotency + CORS lockdown** added after review.
- **Payload:** free-text message + non-personal diagnostics + category picker.
  Screenshot attachment deferred.
- **Optional email** with public-visibility warning + Worker-side obfuscation,
  since the repo is public and the user accepted this trade-off.
- **Same (public) repo** for issues, per user decision.

## Open items to resolve during planning

- Exact Worker source location in this monorepo (`worker/`, `apps/worker/`, or a
  separate repo).
- Choice of Flutter Turnstile widget + attestation plugin(s) vs. thin platform
  channels / WebView.
- Concrete numeric limits (per-IP rate, global daily cap, message length,
  idempotency TTL).
- GitHub App creation + installation on the repo (one-time manual setup) and how
  the private key is delivered to Wrangler secrets.
