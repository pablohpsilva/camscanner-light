# Feedback Worker

## 1. What it is

A Cloudflare Worker (`feedback-worker`) that accepts in-app feedback from CamScanner Light and opens
GitHub Issues on the repository via a GitHub App. Every request is verified before an issue is
created: the primary path uses platform attestation (Apple App Attest on iOS, Google Play Integrity
on Android) backed by a server-issued one-time challenge; the universal fallback is Cloudflare
Turnstile (site-key lives in the app, token is validated server-side). Rate limiting (3
submissions per IP per hour, 300 globally per day), idempotency (600 s dedup window keyed on a
client-supplied UUID v4), body sanitization (mention neutralization, code-fence escaping, email
obfuscation), and a 16 KB body cap are all enforced before GitHub is called. Endpoints:
`GET /health`, `POST /challenge`, `POST /feedback`.

---

## 2. Prerequisites (one-time account setup)

Do each of these once before you deploy. The worker will not start accepting feedback until all
required secrets are in place.

### GitHub App

1. Go to <https://github.com/settings/apps/new>.
2. App name: anything (e.g. `camscanner-feedback`). Homepage URL: the repo URL.
3. Permissions — Repository permissions only:
   - **Issues**: Read & write
   - Everything else: leave at No access or None.
4. Disable webhooks (uncheck "Active").
5. Create the app. Note the **App ID** shown on the app's settings page.
6. Generate a private key (scroll down → "Generate a private key"). Download the `.pem` file.
7. Install the app on `pablohpsilva/camscanner-light`:
   - Left sidebar → Install App → Install → "Only select repositories" →
     choose `camscanner-light`.
   - After install, the URL is
     `https://github.com/settings/installations/<INSTALLATION_ID>` — note the numeric ID.
8. Collect: **App ID**, **Installation ID**, **private-key `.pem`** (the full file content).

### Cloudflare

```bash
npx wrangler login
```

### Cloudflare Turnstile

1. Go to the Cloudflare dashboard → Turnstile → Add site.
2. Widget type: **Managed**.
3. Allowed hostnames: leave blank (native app, no browser Origin).
4. Collect: **Site key** (shipped inside the Flutter app as `TURNSTILE_SITE_KEY`) and
   **Secret key** (stored as the `TURNSTILE_SECRET` Worker secret).

### Google Play Integrity (Android attestation)

Play Integrity is optional for the first deploy — if its secrets are missing or invalid the
Android path automatically falls back to Turnstile. To enable full attestation:

1. In [Google Play Console](https://play.google.com/console) → your app
   (`com.camscannerlight.mobile`) → Release → Setup → App integrity → Link a Cloud project.
   Enable the **Play Integrity API** in that GCP project.
2. In [GCP Console](https://console.cloud.google.com) → IAM & Admin → Service accounts →
   Create service account. Grant it no roles (the Play Integrity API call uses the OAuth scope
   directly). Generate a **JSON key**.
3. From the JSON key file collect:
   - `client_email` → `PLAY_SA_CLIENT_EMAIL`
   - `private_key` (the full `-----BEGIN PRIVATE KEY-----…-----END PRIVATE KEY-----` block,
     newlines included) → `PLAY_SA_PRIVATE_KEY`
4. The package name `com.camscannerlight.mobile` is already in `wrangler.toml`.
   The cloud project number is embedded in the Play Console link step and is not needed by the
   worker directly (the worker calls the Play Integrity API with a service-account OAuth token
   and decodes the integrity token server-side).

### Apple App Attest (iOS attestation)

No server secret is needed — the worker embeds Apple's App Attest Root CA directly and verifies
the certificate chain offline.

What you do need on the **app side**:
- Enable the **App Attest** capability in the app's target (Xcode → Signing & Capabilities).
- The App ID used by the worker is `DGLKF29HPV.com.camscannerlight.mobile`
  (team prefix `.` bundle ID). This is already set as `APPLE_APP_ID` in `wrangler.toml`
  once you fill it in.

---

## 3. Configure & deploy

### 3a. Create the KV namespace

```bash
npx wrangler kv namespace create FEEDBACK_KV
npx wrangler kv namespace create FEEDBACK_KV --preview
```

Each command prints a namespace ID. Put both into `wrangler.toml`:

```toml
[[kv_namespaces]]
binding = "FEEDBACK_KV"
id      = "<id from first command>"
preview_id = "<id from second command>"
```

### 3b. Fill in `[vars]` in `wrangler.toml`

The following non-secret values need to be set before deploy. The file ships with placeholder
strings — replace them:

```toml
[vars]
REPO                    = "pablohpsilva/camscanner-light"   # already correct
APPLE_APP_ID            = "DGLKF29HPV.com.camscannerlight.mobile"
PLAY_PACKAGE_NAME       = "com.camscannerlight.mobile"
ALLOWED_ORIGIN          = ""                # empty = native-app only (no browser Origin allowed)
RATE_PER_IP_PER_HOUR    = "3"
GLOBAL_CAP_PER_DAY      = "300"
IDEMPOTENCY_TTL_SECONDS = "600"
```

`ALLOWED_ORIGIN` is intentionally empty: the native Flutter app sends no `Origin` header, and any
browser request that sends a non-empty `Origin` that does not match this value is rejected with
`403 forbidden_origin`.

### 3c. Set secrets

Run one `wrangler secret put` per secret. Wrangler will prompt you to paste the value:

```bash
# Required — /health returns 503 without these
npx wrangler secret put GITHUB_APP_ID
npx wrangler secret put GITHUB_APP_INSTALLATION_ID
npx wrangler secret put GITHUB_APP_PRIVATE_KEY      # paste the full PEM including header/footer lines
npx wrangler secret put TURNSTILE_SECRET

# Android attestation — can be placeholder strings for a Turnstile-only first deploy
npx wrangler secret put PLAY_SA_CLIENT_EMAIL
npx wrangler secret put PLAY_SA_PRIVATE_KEY         # paste the full PEM from the GCP JSON key
```

`GITHUB_APP_PRIVATE_KEY` and `PLAY_SA_PRIVATE_KEY` are multi-line PEM values. Paste the entire
block (including `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` and the embedded
newlines) when prompted; Wrangler stores it verbatim.

For `PLAY_SA_CLIENT_EMAIL` / `PLAY_SA_PRIVATE_KEY`, any non-empty placeholder (e.g. `placeholder`)
is sufficient for a first deploy: if Play Integrity verification fails the worker falls back to
Turnstile automatically. Android feedback will work — it just won't have Play Integrity backing
until you set the real credentials.

### 3d. Deploy

```bash
npx wrangler deploy
```

Note the Worker URL printed at the end (e.g. `https://feedback-worker.<your-subdomain>.workers.dev`).

### 3e. Optional staging environment

Add an `[env.staging]` block to `wrangler.toml` pointing `REPO` at a throwaway test repo:

```toml
[env.staging]
[env.staging.vars]
REPO = "pablohpsilva/feedback-test"
```

Deploy staging:

```bash
npx wrangler deploy --env staging
```

Staging secrets are set per-environment: `npx wrangler secret put <NAME> --env staging`.

---

## 4. Wire the app

The Flutter app reads the Worker URL and Turnstile site key from `--dart-define` values at build
time.

```bash
# Development / device run
flutter run \
  --dart-define=FEEDBACK_WORKER_URL=https://feedback-worker.<subdomain>.workers.dev \
  --dart-define=TURNSTILE_SITE_KEY=<site-key-from-turnstile>

# Release builds
flutter build apk --release \
  --dart-define=FEEDBACK_WORKER_URL=https://feedback-worker.<subdomain>.workers.dev \
  --dart-define=TURNSTILE_SITE_KEY=<site-key-from-turnstile>

flutter build ios --release \
  --dart-define=FEEDBACK_WORKER_URL=https://feedback-worker.<subdomain>.workers.dev \
  --dart-define=TURNSTILE_SITE_KEY=<site-key-from-turnstile>
```

The app checks `GET {FEEDBACK_WORKER_URL}/health` on startup and hides the feedback entry point
until it receives `200 {"ok":true}`.

---

## 5. Verify / smoke test

### Health check

```bash
curl -i https://feedback-worker.<subdomain>.workers.dev/health
```

Expected when all required secrets are set:

```
HTTP/2 200
content-type: application/json
{"ok":true}
```

Returns `503 {"ok":false}` if any of `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`,
`GITHUB_APP_PRIVATE_KEY`, or `TURNSTILE_SECRET` is blank. The check is local — no outbound call.

### Fails-closed smoke test

```bash
curl -i -X POST https://feedback-worker.<subdomain>.workers.dev/feedback \
  -H 'content-type: application/json' \
  -d '{"category":"bug","message":"test","idempotencyKey":"00000000-0000-0000-0000-000000000000","diagnostics":{"appVersion":"","build":"","os":"","device":"","locale":""}}'
```

Expected: `401 {"error":"unverified"}` — the pipeline ran all the way through validation and
attempted attestation/Turnstile verification, found nothing valid, and failed closed. A GitHub
issue is never opened.

### Request/response contract

All responses are `application/json`.

#### `GET /health`

| Status | Body | When |
|--------|------|------|
| `200` | `{"ok":true}` | Required secrets present |
| `503` | `{"ok":false}` | Any required secret is blank |
| `405` | `{"error":"method_not_allowed"}` | Non-GET method |

#### `POST /challenge`

Returns a server-issued one-time challenge token (base64url, 32 random bytes, TTL 300 s) that
the mobile client passes back inside the `attestation.challenge` field of a subsequent
`/feedback` call. Required only for the attestation path; Turnstile-only clients skip this.

| Status | Body | When |
|--------|------|------|
| `200` | `{"challenge":"<base64url>"}` | Always (if origin allowed) |
| `403` | `{"error":"forbidden_origin"}` | Browser Origin that isn't `ALLOWED_ORIGIN` |
| `405` | `{"error":"method_not_allowed"}` | Non-POST method |

#### `POST /feedback`

Request body (JSON, `content-type: application/json`, max 16 KB):

```jsonc
{
  "category": "bug" | "idea" | "question",   // required
  "message": "<string, max 4000 chars>",      // required, non-empty
  "idempotencyKey": "<UUID v4>",              // required
  "diagnostics": {                            // required object
    "appVersion": "<string>",
    "build": "<string>",
    "os": "<string>",
    "device": "<string>",
    "locale": "<string>"
  },
  "email": "<optional email, max 254 chars>",
  "turnstileToken": "<Cloudflare Turnstile token>",   // for Turnstile path
  "attestation": {                            // for platform attestation path
    "platform": "ios" | "android",
    "token": "<attestation token, max 12000 chars>",
    "challenge": "<challenge from POST /challenge, max 200 chars>",
    "keyId": "<iOS App Attest key ID, max 200 chars>"  // iOS only
  }
}
```

At least one of `turnstileToken` (Turnstile path) or `attestation` (platform path) must be
present and pass verification.

| Status | Body | When |
|--------|------|------|
| `201` | `{"ok":true,"issueUrl":"<github-url>"}` | Issue created |
| `200` | `{"ok":true,"issueUrl":"<github-url>","duplicate":true}` | Idempotency hit — same `idempotencyKey` within TTL |
| `400` | `{"error":"invalid","detail":"<reason>"}` | Body fails validation (bad category, empty message, malformed UUID, bad email, missing diagnostics, etc.) |
| `400` | `{"error":"bad_json"}` | Body is not valid JSON |
| `401` | `{"error":"unverified"}` | Neither attestation nor Turnstile passed |
| `401` | `{"error":"bad_challenge"}` | Attestation challenge not found or already used |
| `403` | `{"error":"forbidden_origin"}` | Browser Origin not in allowlist |
| `405` | `{"error":"method_not_allowed"}` | Non-POST method |
| `413` | `{"error":"payload_too_large"}` | Body exceeds 16 KB |
| `415` | `{"error":"unsupported_media_type"}` | `content-type` is not `application/json` |
| `429` | `{"error":"rate_limited"}` | IP exceeded 3 submissions in the current hour |
| `429` | `{"error":"global_cap"}` | Global daily cap (300) reached |
| `502` | `{"error":"upstream_failed"}` | GitHub API call failed |
| `503` | `{"ok":false}` | Worker is not healthy (missing secrets) |

---

## 6. Tests & local dev

### Run tests

```bash
cd apps/worker
npm test
```

Uses [Vitest](https://vitest.dev) with
[@cloudflare/vitest-pool-workers](https://www.npmjs.com/package/@cloudflare/vitest-pool-workers)
(Miniflare). The test environment is self-contained: throwaway RSA keys, a fake Turnstile secret,
and fake GitHub App credentials are injected via the `miniflare.bindings` block in
`vitest.config.ts`. No real outbound calls are made during tests — all external fetches are
intercepted by mocks in the individual test files.

Test files live in `test/` and cover: routing, health, challenge issuance, idempotency, rate
limits, input validation, output sanitization, Turnstile verification, Play Integrity
verification, App Attest verification, GitHub issue creation, and the full pipeline.

### Local development

```bash
cd apps/worker
npm run dev          # wrangler dev — serves on http://localhost:8787
```

Secrets for local dev can be placed in a `.dev.vars` file (gitignored):

```ini
GITHUB_APP_ID=123456
GITHUB_APP_INSTALLATION_ID=12345
GITHUB_APP_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----
TURNSTILE_SECRET=<your-secret>
PLAY_SA_CLIENT_EMAIL=sa@project.iam.gserviceaccount.com
PLAY_SA_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----
```

The KV namespace will use the `preview_id` from `wrangler.toml` when running `wrangler dev`.
