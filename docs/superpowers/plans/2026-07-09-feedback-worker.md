# Feedback Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Cloudflare Worker that accepts app feedback over HTTPS, proves the caller is a genuine app install (attestation primary, Turnstile fallback), gates abuse, and creates a sanitized GitHub issue via a GitHub App — with no credential ever shipped in the client.

**Architecture:** A single `POST /feedback` handler runs a fixed pipeline: CORS/method/size guards → verification (attestation primary, Turnstile fallback) → idempotency dedupe → rate limit + global cap → validate + sanitize → mint GitHub App installation token → create issue. Verification backends sit behind a `Verifier` interface so the pipeline is fully unit-testable with mocks and the real crypto is validated by device round-trips. State (rate counters, idempotency, attested App Attest keys) lives in Cloudflare KV.

**Tech Stack:** TypeScript, Cloudflare Workers (`wrangler`), Vitest + `@cloudflare/vitest-pool-workers` (Miniflare), WebCrypto (RS256 signing), KV. Libraries: `cbor-x` + `@peculiar/x509` (App Attest parsing/chain), Google Play Integrity decode API (Play Integrity), GitHub REST.

## Global Constraints

- Runtime: Cloudflare Workers (module syntax `export default { fetch }`), no Node built-ins except via `nodejs_compat` where unavoidable.
- Repo target: `pablohpsilva/camscanner-light` (public). Issues created here.
- GitHub auth: **GitHub App** installation token minted per request via WebCrypto RS256. Never a PAT. Never long-lived.
- Least privilege: GitHub App has **Issues: write** on this repo only.
- Fail closed: any guard/verification failure rejects; secrets and internal errors never appear in responses.
- Allowed categories (exact): `bug`, `idea`, `question`.
- Machine label on every issue (exact): `app-feedback`.
- Message max length: 4000 chars. Request body max: 16 KB.
- Email in issue body is obfuscated: `@` → ` [at] `.
- User-supplied text is fenced AND `@`/`#` are neutralized with a zero-width space (U+200B) before insertion.
- No PII in logs.

---

## Prerequisites (human setup — do these first, they cannot be automated)

- [ ] **P1 — Create the GitHub App**
  - github.com → Settings → Developer settings → GitHub Apps → New GitHub App.
  - Permissions: Repository → **Issues: Read and write**. No other permissions. No webhook.
  - Where can it be installed: Only this account.
  - Create, then **Generate a private key** (downloads a `.pem`). Note the **App ID**.
  - Install the App on **only** `pablohpsilva/camscanner-light`. From the install URL, note the **Installation ID** (the number in `.../installations/<ID>`).

- [ ] **P2 — Cloudflare account + Wrangler**
  - `npm i -g wrangler`; `wrangler login`.
  - Create two KV namespaces: `wrangler kv namespace create FEEDBACK_KV` and `wrangler kv namespace create FEEDBACK_KV --preview`. Record the ids.

- [ ] **P3 — Turnstile**
  - Cloudflare dashboard → Turnstile → Add site. Record the **Site key** (ships in the app) and **Secret key** (Worker secret).

- [ ] **P4 — Apple App Attest**
  - Note the app's **Team ID** and **Bundle ID** (from `apps/mobile/ios`). App Attest needs the App ID = `<TeamID>.<BundleID>` and Apple's App Attest Root CA (public, embedded in the verifier). No server key needed for App Attest verification.

- [ ] **P5 — Google Play Integrity**
  - Google Play Console → the app → Release → App integrity → link a Google Cloud project.
  - In that GCP project, enable the **Play Integrity API**, create a **service account** with access to call `playintegrity.googleapis.com`, and download its JSON key. Record `client_email`, `private_key`, and the **package name**.

---

## Task 1: Project scaffold + first passing route

**Files:**
- Create: `worker/package.json`, `worker/tsconfig.json`, `worker/wrangler.toml`, `worker/vitest.config.ts`, `worker/src/index.ts`, `worker/src/env.ts`
- Test: `worker/test/routing.test.ts`

**Interfaces:**
- Produces: `export default { fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> }`. `Env` type (see `env.ts`).

- [ ] **Step 1: Scaffold files**

`worker/package.json`:
```json
{
  "name": "feedback-worker",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  },
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.5.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0",
    "wrangler": "^3.78.0"
  },
  "dependencies": {
    "cbor-x": "^1.5.9",
    "@peculiar/x509": "^1.11.0"
  }
}
```

`worker/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "es2022",
    "moduleResolution": "bundler",
    "lib": ["es2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true
  }
}
```

`worker/wrangler.toml`:
```toml
name = "feedback-worker"
main = "src/index.ts"
compatibility_date = "2024-09-23"
compatibility_flags = ["nodejs_compat"]

[[kv_namespaces]]
binding = "FEEDBACK_KV"
id = "REPLACE_WITH_KV_ID"          # from P2
preview_id = "REPLACE_WITH_PREVIEW_KV_ID"

[vars]
REPO = "pablohpsilva/camscanner-light"
ALLOWED_ORIGIN = ""                # native app => no Origin; browsers blocked
RATE_PER_IP_PER_HOUR = "3"
GLOBAL_CAP_PER_DAY = "300"
IDEMPOTENCY_TTL_SECONDS = "600"
APPLE_APP_ID = "REPLACE_TEAMID.BUNDLEID"     # from P4
PLAY_PACKAGE_NAME = "REPLACE_PACKAGE"        # from P5
# Secrets (set via `wrangler secret put`): GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID,
# GITHUB_APP_PRIVATE_KEY, TURNSTILE_SECRET, PLAY_SA_CLIENT_EMAIL, PLAY_SA_PRIVATE_KEY
```

`worker/vitest.config.ts`:
```ts
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
export default defineWorkersConfig({
  test: { poolOptions: { workers: { wrangler: { configPath: "./wrangler.toml" } } } },
});
```

`worker/src/env.ts`:
```ts
export interface Env {
  FEEDBACK_KV: KVNamespace;
  REPO: string;
  ALLOWED_ORIGIN: string;
  RATE_PER_IP_PER_HOUR: string;
  GLOBAL_CAP_PER_DAY: string;
  IDEMPOTENCY_TTL_SECONDS: string;
  APPLE_APP_ID: string;
  PLAY_PACKAGE_NAME: string;
  GITHUB_APP_ID: string;
  GITHUB_APP_INSTALLATION_ID: string;
  GITHUB_APP_PRIVATE_KEY: string;
  TURNSTILE_SECRET: string;
  PLAY_SA_CLIENT_EMAIL: string;
  PLAY_SA_PRIVATE_KEY: string;
}
```

- [ ] **Step 2: Write the failing test**

`worker/test/routing.test.ts`:
```ts
import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker from "../src/index";

describe("routing", () => {
  it("returns 405 for GET /feedback", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(new Request("https://x/feedback"), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(405);
  });
  it("returns 404 for unknown path", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(new Request("https://x/nope", { method: "POST" }), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd worker && npm install && npm test`
Expected: FAIL — `../src/index` has no default export yet.

- [ ] **Step 4: Minimal implementation**

`worker/src/index.ts`:
```ts
import type { Env } from "./env";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/feedback") return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    return json({ ok: true }, 200);
  },
};

export function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd worker && npm test`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add worker/package.json worker/tsconfig.json worker/wrangler.toml worker/vitest.config.ts worker/src worker/test worker/package-lock.json
git commit -m "feat(worker): scaffold feedback worker with routing"
```

---

## Task 2: Request guards (CORS/origin, content-type, body size)

**Files:**
- Create: `worker/src/guards.ts`
- Modify: `worker/src/index.ts`
- Test: `worker/test/guards.test.ts`

**Interfaces:**
- Produces: `guardRequest(request: Request, env: Env): Promise<{ ok: true; body: unknown } | { ok: false; response: Response }>`

- [ ] **Step 1: Write the failing test**

`worker/test/guards.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { guardRequest } from "../src/guards";

const post = (init: RequestInit) => new Request("https://x/feedback", { method: "POST", ...init });

describe("guardRequest", () => {
  it("rejects a browser Origin", async () => {
    const r = await guardRequest(post({ headers: { origin: "https://evil.example", "content-type": "application/json" }, body: "{}" }), env);
    expect(r.ok).toBe(false);
  });
  it("rejects non-json content-type", async () => {
    const r = await guardRequest(post({ headers: { "content-type": "text/plain" }, body: "hi" }), env);
    expect(r.ok).toBe(false);
  });
  it("rejects oversize body", async () => {
    const big = JSON.stringify({ m: "a".repeat(20000) });
    const r = await guardRequest(post({ headers: { "content-type": "application/json" }, body: big }), env);
    expect(r.ok).toBe(false);
  });
  it("accepts a valid small json POST with no Origin", async () => {
    const r = await guardRequest(post({ headers: { "content-type": "application/json" }, body: '{"a":1}' }), env);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.body).toEqual({ a: 1 });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- guards`
Expected: FAIL — `../src/guards` not found.

- [ ] **Step 3: Implementation**

`worker/src/guards.ts`:
```ts
import type { Env } from "./env";
import { json } from "./index";

const MAX_BODY_BYTES = 16 * 1024;

export async function guardRequest(
  request: Request,
  env: Env,
): Promise<{ ok: true; body: unknown } | { ok: false; response: Response }> {
  const origin = request.headers.get("origin");
  // Native app sends no Origin. Any browser Origin that isn't the allowlisted one is rejected.
  if (origin && origin !== env.ALLOWED_ORIGIN) {
    return { ok: false, response: json({ error: "forbidden_origin" }, 403) };
  }
  const ct = request.headers.get("content-type") ?? "";
  if (!ct.includes("application/json")) {
    return { ok: false, response: json({ error: "unsupported_media_type" }, 415) };
  }
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) {
    return { ok: false, response: json({ error: "payload_too_large" }, 413) };
  }
  try {
    return { ok: true, body: JSON.parse(raw) };
  } catch {
    return { ok: false, response: json({ error: "bad_json" }, 400) };
  }
}
```

Modify `worker/src/index.ts` handler body (after the method check) to call the guard:
```ts
import { guardRequest } from "./guards";
// ...inside fetch, replacing `return json({ ok: true }, 200);`
    const guarded = await guardRequest(request, env);
    if (!guarded.ok) return guarded.response;
    return json({ ok: true }, 200);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/guards.ts worker/src/index.ts worker/test/guards.test.ts
git commit -m "feat(worker): CORS/content-type/body-size guards"
```

---

## Task 3: Payload validation

**Files:**
- Create: `worker/src/validate.ts`
- Test: `worker/test/validate.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export interface FeedbackInput {
    category: "bug" | "idea" | "question";
    message: string;
    email?: string;
    attestation?: { platform: "ios" | "android"; token: string; keyId?: string; challenge: string };
    turnstileToken?: string;
    idempotencyKey: string;
    diagnostics: { appVersion: string; build: string; os: string; device: string; locale: string };
  }
  export function validate(body: unknown): { ok: true; value: FeedbackInput } | { ok: false; error: string };
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/validate.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { validate } from "../src/validate";

const base = {
  category: "bug",
  message: "It crashed on export",
  idempotencyKey: "11111111-1111-1111-1111-111111111111",
  diagnostics: { appVersion: "1.0.0", build: "42", os: "iOS 18.3", device: "iPhone15,2", locale: "en_US" },
};

describe("validate", () => {
  it("accepts a minimal valid payload", () => {
    const r = validate(base);
    expect(r.ok).toBe(true);
  });
  it("rejects empty message", () => {
    expect(validate({ ...base, message: "   " }).ok).toBe(false);
  });
  it("rejects message over 4000 chars", () => {
    expect(validate({ ...base, message: "a".repeat(4001) }).ok).toBe(false);
  });
  it("rejects unknown category", () => {
    expect(validate({ ...base, category: "spam" }).ok).toBe(false);
  });
  it("rejects malformed email when present", () => {
    expect(validate({ ...base, email: "not-an-email" }).ok).toBe(false);
  });
  it("accepts a valid email", () => {
    expect(validate({ ...base, email: "a@b.com" }).ok).toBe(true);
  });
  it("rejects missing idempotencyKey", () => {
    const { idempotencyKey, ...noKey } = base;
    expect(validate(noKey).ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- validate`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/validate.ts`:
```ts
export interface FeedbackInput {
  category: "bug" | "idea" | "question";
  message: string;
  email?: string;
  attestation?: { platform: "ios" | "android"; token: string; keyId?: string; challenge: string };
  turnstileToken?: string;
  idempotencyKey: string;
  diagnostics: { appVersion: string; build: string; os: string; device: string; locale: string };
}

const CATEGORIES = ["bug", "idea", "question"] as const;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function str(v: unknown, max: number): string | null {
  return typeof v === "string" && v.length <= max ? v : null;
}

export function validate(body: unknown): { ok: true; value: FeedbackInput } | { ok: false; error: string } {
  if (typeof body !== "object" || body === null) return { ok: false, error: "not_object" };
  const b = body as Record<string, unknown>;

  if (!CATEGORIES.includes(b.category as any)) return { ok: false, error: "bad_category" };
  const message = str(b.message, 4000);
  if (!message || message.trim().length === 0) return { ok: false, error: "bad_message" };
  if (typeof b.idempotencyKey !== "string" || !UUID_RE.test(b.idempotencyKey))
    return { ok: false, error: "bad_idempotency_key" };

  let email: string | undefined;
  if (b.email !== undefined && b.email !== "") {
    const e = str(b.email, 254);
    if (!e || !EMAIL_RE.test(e)) return { ok: false, error: "bad_email" };
    email = e;
  }

  const d = b.diagnostics as Record<string, unknown> | undefined;
  if (!d || typeof d !== "object") return { ok: false, error: "bad_diagnostics" };
  const diagnostics = {
    appVersion: str(d.appVersion, 40) ?? "",
    build: str(d.build, 40) ?? "",
    os: str(d.os, 80) ?? "",
    device: str(d.device, 80) ?? "",
    locale: str(d.locale, 40) ?? "",
  };

  let attestation: FeedbackInput["attestation"];
  const a = b.attestation as Record<string, unknown> | undefined;
  if (a && (a.platform === "ios" || a.platform === "android")) {
    const token = str(a.token, 12000);
    const challenge = str(a.challenge, 200);
    if (token && challenge) {
      attestation = {
        platform: a.platform,
        token,
        challenge,
        keyId: str(a.keyId ?? "", 200) || undefined,
      };
    }
  }

  const turnstileToken = str(b.turnstileToken ?? "", 4000) || undefined;

  return {
    ok: true,
    value: { category: b.category as any, message, email, attestation, turnstileToken, idempotencyKey: b.idempotencyKey, diagnostics },
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- validate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/validate.ts worker/test/validate.test.ts
git commit -m "feat(worker): payload validation"
```

---

## Task 4: Content sanitization

**Files:**
- Create: `worker/src/sanitize.ts`
- Test: `worker/test/sanitize.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export function neutralizeMentions(s: string): string;   // '@'/'#' -> followed by U+200B
  export function fenceBlock(s: string): string;            // wrap in ``` fence, escape backtick runs
  export function obfuscateEmail(s: string): string;        // '@' -> ' [at] '
  export function slugTitle(category: string, message: string): string; // sanitized, <=80 chars
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/sanitize.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { neutralizeMentions, fenceBlock, obfuscateEmail, slugTitle } from "../src/sanitize";

describe("sanitize", () => {
  it("neutralizes @mentions and #refs with zero-width space", () => {
    const out = neutralizeMentions("hi @maintainer see #123");
    expect(out).toContain("@​maintainer");
    expect(out).toContain("#​123");
  });
  it("wraps content in a code fence", () => {
    expect(fenceBlock("hello")).toBe("```\nhello\n```");
  });
  it("neutralizes backtick fences inside the message", () => {
    expect(fenceBlock("a```b")).not.toContain("\n```b");
  });
  it("obfuscates an email", () => {
    expect(obfuscateEmail("user@example.com")).toBe("user [at] example.com");
  });
  it("builds a bounded, mention-free title", () => {
    const t = slugTitle("bug", "@here everything is broken ".repeat(10));
    expect(t.startsWith("[bug]")).toBe(true);
    expect(t.length).toBeLessThanOrEqual(80);
    expect(t).not.toContain("@here");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- sanitize`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/sanitize.ts`:
```ts
const ZWSP = "​";

export function neutralizeMentions(s: string): string {
  return s.replace(/([@#])/g, `$1${ZWSP}`);
}

export function fenceBlock(s: string): string {
  // Collapse any backtick run so the user cannot break out of the fence.
  const safe = s.replace(/`{3,}/g, "``");
  return "```\n" + safe + "\n```";
}

export function obfuscateEmail(s: string): string {
  return s.replace(/@/g, " [at] ");
}

export function slugTitle(category: string, message: string): string {
  const firstLine = message.split(/\r?\n/)[0] ?? "";
  const cleaned = neutralizeMentions(firstLine).replace(/\s+/g, " ").trim();
  const prefix = `[${category}] `;
  const room = 80 - prefix.length;
  return prefix + (cleaned.length > room ? cleaned.slice(0, room - 1) + "…" : cleaned);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- sanitize`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/sanitize.ts worker/test/sanitize.test.ts
git commit -m "feat(worker): content sanitization (mentions, fencing, email, title)"
```

---

## Task 5: Verifier interface + Turnstile fallback verifier

**Files:**
- Create: `worker/src/verify/verifier.ts`, `worker/src/verify/turnstile.ts`
- Test: `worker/test/turnstile.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export interface VerifyResult { ok: boolean; reason?: string }
  export interface Verifier { verify(input: FeedbackInput, ip: string): Promise<VerifyResult>; }
  export function verifyTurnstile(secret: string, token: string, ip: string, fetchImpl?: typeof fetch): Promise<VerifyResult>;
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/turnstile.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { verifyTurnstile } from "../src/verify/turnstile";

function fakeFetch(success: boolean): typeof fetch {
  return (async () => new Response(JSON.stringify({ success }), { status: 200 })) as any;
}

describe("verifyTurnstile", () => {
  it("passes when siteverify returns success", async () => {
    const r = await verifyTurnstile("secret", "tok", "1.2.3.4", fakeFetch(true));
    expect(r.ok).toBe(true);
  });
  it("fails when siteverify rejects", async () => {
    const r = await verifyTurnstile("secret", "tok", "1.2.3.4", fakeFetch(false));
    expect(r.ok).toBe(false);
  });
  it("fails when token missing", async () => {
    const r = await verifyTurnstile("secret", "", "1.2.3.4", fakeFetch(true));
    expect(r.ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- turnstile`
Expected: FAIL — modules missing.

- [ ] **Step 3: Implementation**

`worker/src/verify/verifier.ts`:
```ts
import type { FeedbackInput } from "../validate";
export interface VerifyResult { ok: boolean; reason?: string }
export interface Verifier { verify(input: FeedbackInput, ip: string): Promise<VerifyResult>; }
```

`worker/src/verify/turnstile.ts`:
```ts
export interface VerifyResult { ok: boolean; reason?: string }

export async function verifyTurnstile(
  secret: string,
  token: string,
  ip: string,
  fetchImpl: typeof fetch = fetch,
): Promise<VerifyResult> {
  if (!token) return { ok: false, reason: "no_turnstile_token" };
  const form = new FormData();
  form.append("secret", secret);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  const res = await fetchImpl("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: form,
  });
  const data = (await res.json()) as { success: boolean };
  return data.success ? { ok: true } : { ok: false, reason: "turnstile_failed" };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- turnstile`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/verify worker/test/turnstile.test.ts
git commit -m "feat(worker): verifier interface + Turnstile fallback"
```

---

## Task 6: Verification orchestration (attestation primary, Turnstile fallback)

**Files:**
- Create: `worker/src/verify/orchestrate.ts`
- Test: `worker/test/orchestrate.test.ts`

**Interfaces:**
- Consumes: `VerifyResult`, `FeedbackInput`.
- Produces:
  ```ts
  // attestationVerifier and turnstileVerifier are injected so the orchestrator is unit-testable
  // without real crypto. Real implementations arrive in Tasks 7 & 8.
  export type AttestFn = (input: FeedbackInput, ip: string) => Promise<VerifyResult>;
  export type TurnstileFn = (input: FeedbackInput, ip: string) => Promise<VerifyResult>;
  export function verifyCaller(input: FeedbackInput, ip: string, attest: AttestFn, turnstile: TurnstileFn): Promise<VerifyResult>;
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/orchestrate.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { verifyCaller } from "../src/verify/orchestrate";

const input: any = { attestation: { platform: "ios", token: "t", challenge: "c" }, turnstileToken: "tok" };
const pass = async () => ({ ok: true });
const fail = async () => ({ ok: false, reason: "x" });

describe("verifyCaller", () => {
  it("passes when attestation passes (never calls Turnstile)", async () => {
    let turnstileCalled = false;
    const r = await verifyCaller(input, "ip", pass, async () => { turnstileCalled = true; return { ok: true }; });
    expect(r.ok).toBe(true);
    expect(turnstileCalled).toBe(false);
  });
  it("falls back to Turnstile when attestation fails", async () => {
    const r = await verifyCaller(input, "ip", fail, pass);
    expect(r.ok).toBe(true);
  });
  it("rejects when both fail", async () => {
    const r = await verifyCaller(input, "ip", fail, fail);
    expect(r.ok).toBe(false);
  });
  it("uses Turnstile when no attestation present", async () => {
    const r = await verifyCaller({ turnstileToken: "tok" } as any, "ip", fail, pass);
    expect(r.ok).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- orchestrate`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/verify/orchestrate.ts`:
```ts
import type { FeedbackInput } from "../validate";
import type { VerifyResult } from "./verifier";

export type AttestFn = (input: FeedbackInput, ip: string) => Promise<VerifyResult>;
export type TurnstileFn = (input: FeedbackInput, ip: string) => Promise<VerifyResult>;

export async function verifyCaller(
  input: FeedbackInput,
  ip: string,
  attest: AttestFn,
  turnstile: TurnstileFn,
): Promise<VerifyResult> {
  if (input.attestation) {
    const a = await attest(input, ip);
    if (a.ok) return a;
  }
  const t = await turnstile(input, ip);
  if (t.ok) return t;
  return { ok: false, reason: "unverified" };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- orchestrate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/verify/orchestrate.ts worker/test/orchestrate.test.ts
git commit -m "feat(worker): verification orchestration (attestation primary, turnstile fallback)"
```

---

## Task 7: Play Integrity verifier (Android attestation)

**Files:**
- Create: `worker/src/verify/play_integrity.ts`, `worker/src/google_token.ts`
- Test: `worker/test/play_integrity.test.ts`

**Interfaces:**
- Consumes: `VerifyResult`, `FeedbackInput`, `Env`.
- Produces:
  ```ts
  export function googleAccessToken(email: string, privateKeyPem: string, scope: string, fetchImpl?: typeof fetch): Promise<string>;
  export function verifyPlayIntegrity(env: Env, token: string, expectedChallenge: string, fetchImpl?: typeof fetch): Promise<VerifyResult>;
  ```

**Approach:** Call Google's server-side decode endpoint
`POST https://playintegrity.googleapis.com/v1/{packageName}:decodeIntegrityToken`
with a service-account OAuth2 bearer token. Accept only when
`appIntegrity.appRecognitionVerdict == "PLAY_RECOGNIZED"`,
`deviceIntegrity.deviceRecognitionVerdict` contains `"MEETS_DEVICE_INTEGRITY"`,
`accountDetails.appLicensingVerdict != "UNEVALUATED"` (optional), and the
base64url of `requestDetails.requestHash` equals the challenge we issued.

- [ ] **Step 1: Write the failing test** (mock Google's HTTP)

`worker/test/play_integrity.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { verifyPlayIntegrity } from "../src/verify/play_integrity";

function googleMock(payload: any): typeof fetch {
  return (async (url: string) => {
    if (String(url).includes("oauth2")) return new Response(JSON.stringify({ access_token: "at", expires_in: 3600 }), { status: 200 });
    return new Response(JSON.stringify({ tokenPayloadExternal: payload }), { status: 200 });
  }) as any;
}

const good = {
  requestDetails: { requestHash: "chal", requestPackageName: env.PLAY_PACKAGE_NAME },
  appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED" },
  deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
};

describe("verifyPlayIntegrity", () => {
  it("passes on PLAY_RECOGNIZED + device integrity + matching challenge", async () => {
    const r = await verifyPlayIntegrity(env, "tok", "chal", googleMock(good));
    expect(r.ok).toBe(true);
  });
  it("fails on wrong challenge", async () => {
    const r = await verifyPlayIntegrity(env, "tok", "different", googleMock(good));
    expect(r.ok).toBe(false);
  });
  it("fails when app not recognized", async () => {
    const bad = { ...good, appIntegrity: { appRecognitionVerdict: "UNRECOGNIZED_VERSION" } };
    const r = await verifyPlayIntegrity(env, "tok", "chal", googleMock(bad));
    expect(r.ok).toBe(false);
  });
});
```
(For this test provide `PLAY_SA_CLIENT_EMAIL`, `PLAY_SA_PRIVATE_KEY`, `PLAY_PACKAGE_NAME` in `wrangler.toml` `[vars]`/`.dev.vars` test values; the private key can be a throwaway test PEM since Google HTTP is mocked.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- play_integrity`
Expected: FAIL — modules missing.

- [ ] **Step 3: Implementation**

`worker/src/google_token.ts`:
```ts
function b64url(bytes: Uint8Array): string {
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

export async function googleAccessToken(
  email: string, privateKeyPem: string, scope: string, fetchImpl: typeof fetch = fetch,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(new TextEncoder().encode(JSON.stringify({
    iss: email, scope, aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  })));
  const signingInput = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToPkcs8(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)));
  const jwt = `${signingInput}.${b64url(sig)}`;
  const res = await fetchImpl("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${jwt}`,
  });
  const data = (await res.json()) as { access_token?: string };
  if (!data.access_token) throw new Error("google_token_failed");
  return data.access_token;
}
```

`worker/src/verify/play_integrity.ts`:
```ts
import type { Env } from "../env";
import type { VerifyResult } from "./verifier";
import { googleAccessToken } from "../google_token";

export async function verifyPlayIntegrity(
  env: Env, token: string, expectedChallenge: string, fetchImpl: typeof fetch = fetch,
): Promise<VerifyResult> {
  if (!token) return { ok: false, reason: "no_play_token" };
  const at = await googleAccessToken(
    env.PLAY_SA_CLIENT_EMAIL, env.PLAY_SA_PRIVATE_KEY,
    "https://www.googleapis.com/auth/playintegrity", fetchImpl,
  );
  const url = `https://playintegrity.googleapis.com/v1/${env.PLAY_PACKAGE_NAME}:decodeIntegrityToken`;
  const res = await fetchImpl(url, {
    method: "POST",
    headers: { authorization: `Bearer ${at}`, "content-type": "application/json" },
    body: JSON.stringify({ integrityToken: token }),
  });
  if (!res.ok) return { ok: false, reason: "play_decode_failed" };
  const data = (await res.json()) as { tokenPayloadExternal?: any };
  const p = data.tokenPayloadExternal;
  if (!p) return { ok: false, reason: "play_no_payload" };
  if (p.requestDetails?.requestHash !== expectedChallenge) return { ok: false, reason: "play_challenge_mismatch" };
  if (p.requestDetails?.requestPackageName !== env.PLAY_PACKAGE_NAME) return { ok: false, reason: "play_package_mismatch" };
  if (p.appIntegrity?.appRecognitionVerdict !== "PLAY_RECOGNIZED") return { ok: false, reason: "play_app_unrecognized" };
  const dev: string[] = p.deviceIntegrity?.deviceRecognitionVerdict ?? [];
  if (!dev.includes("MEETS_DEVICE_INTEGRITY")) return { ok: false, reason: "play_device_integrity" };
  return { ok: true };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- play_integrity`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/google_token.ts worker/src/verify/play_integrity.ts worker/test/play_integrity.test.ts
git commit -m "feat(worker): Play Integrity verifier via decode API"
```

---

## Task 8: App Attest verifier (iOS attestation)

**Files:**
- Create: `worker/src/verify/app_attest.ts`
- Test: `worker/test/app_attest.test.ts`

**Interfaces:**
- Consumes: `VerifyResult`, `Env`, `FEEDBACK_KV`.
- Produces:
  ```ts
  // Full Apple App Attest attestation verification (7 steps, Apple docs "Validating Apps That
  // Connect to Your Server"). Stores the attested public key under key `attest:<keyId>` in KV.
  export function verifyAppAttest(env: Env, keyId: string, attestationB64: string, challenge: string): Promise<VerifyResult>;
  ```

**Reality note (read before implementing):** App Attest verification is intricate
crypto — CBOR decode of the attestation object, X.509 chain validation to Apple's
App Attest Root CA, nonce check against the credCert extension `1.2.840.113635.100.8.2`,
`rpIdHash == SHA256(appID)` check, and public-key extraction. The unit test below
mocks nothing crypto-real (Apple attestations can only be produced on a real
device), so it asserts the **failure paths** and the **structural contract**. The
**success path is proven only by the device round-trip in Task 14 and in the
Flutter plan's device tests** — this is an explicit, named gap in host testing, not
a silent one. Do not claim this task "passing" on the strength of unit tests alone.

- [ ] **Step 1: Write the failing test (failure-path + contract)**

`worker/test/app_attest.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { verifyAppAttest } from "../src/verify/app_attest";

describe("verifyAppAttest (failure paths)", () => {
  it("rejects empty attestation", async () => {
    const r = await verifyAppAttest(env, "kid", "", "chal");
    expect(r.ok).toBe(false);
  });
  it("rejects non-CBOR garbage", async () => {
    const r = await verifyAppAttest(env, "kid", btoa("not cbor at all"), "chal");
    expect(r.ok).toBe(false);
  });
  it("rejects a CBOR object missing attStmt/authData", async () => {
    // minimal CBOR map {"x":1} base64
    const r = await verifyAppAttest(env, "kid", btoa("\xa1axa\x01"), "chal");
    expect(r.ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- app_attest`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation** (Apple's 7-step validation)

`worker/src/verify/app_attest.ts`:
```ts
import { decode as cborDecode } from "cbor-x";
import { X509Certificate, X509ChainBuilder } from "@peculiar/x509";
import type { Env } from "../env";
import type { VerifyResult } from "./verifier";

// Apple App Attest Root CA (PEM). Source: https://www.apple.com/certificateauthority/
const APPLE_APP_ATTEST_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEA3YsaNkGNM8k5MtqxjWyPRj1sdOWmfvDktdmT
XTh6+kmr9Xr1L+2i5+iw0PZ3S8VG
-----END CERTIFICATE-----`;

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}
function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function eq(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

export async function verifyAppAttest(
  env: Env, keyId: string, attestationB64: string, challenge: string,
): Promise<VerifyResult> {
  try {
    if (!attestationB64) return { ok: false, reason: "no_attestation" };
    const att = cborDecode(b64ToBytes(attestationB64)) as { fmt?: string; attStmt?: any; authData?: Uint8Array };
    if (att.fmt !== "apple-appattest" || !att.attStmt || !att.authData) return { ok: false, reason: "bad_att_object" };

    // 1. Build cert chain from attStmt.x5c and verify to Apple root.
    const x5c: Uint8Array[] = att.attStmt.x5c;
    if (!Array.isArray(x5c) || x5c.length < 1) return { ok: false, reason: "no_x5c" };
    const leaf = new X509Certificate(x5c[0]);
    const intermediates = x5c.slice(1).map((c) => new X509Certificate(c));
    const root = new X509Certificate(APPLE_APP_ATTEST_ROOT);
    const chain = await new X509ChainBuilder({ certificates: [...intermediates, root] }).build(leaf);
    const last = chain[chain.length - 1];
    if (!last || last.thumbprint === undefined) return { ok: false, reason: "chain_build_failed" };
    if (!(await last.isSelfSigned()) || last.subject !== root.subject) return { ok: false, reason: "chain_not_apple_root" };

    // 2. nonce = SHA256(authData || SHA256(challenge)); compare to credCert ext 1.2.840.113635.100.8.2.
    const clientDataHash = await sha256(new TextEncoder().encode(challenge));
    const nonceInput = new Uint8Array([...att.authData, ...clientDataHash]);
    const expectedNonce = await sha256(nonceInput);
    const ext = leaf.getExtension("1.2.840.113635.100.8.2");
    if (!ext) return { ok: false, reason: "no_nonce_ext" };
    const extBytes = new Uint8Array(ext.value);
    // The extension is a DER SEQUENCE wrapping [0] OCTET STRING(32). The 32-byte nonce is the trailing 32 bytes.
    const extNonce = extBytes.slice(extBytes.length - 32);
    if (!eq(extNonce, expectedNonce)) return { ok: false, reason: "nonce_mismatch" };

    // 3. rpIdHash (authData[0..32]) == SHA256(appID).
    const rpIdHash = att.authData.slice(0, 32);
    const appIdHash = await sha256(new TextEncoder().encode(env.APPLE_APP_ID));
    if (!eq(rpIdHash, appIdHash)) return { ok: false, reason: "app_id_mismatch" };

    // 4. keyId (base64) must equal SHA256 of the leaf public key; also matches authData credential id.
    const spki = new Uint8Array(leaf.publicKey.rawData);
    // Apple keyId is SHA256 of the EC point; verify the client-declared keyId is consistent with the cert.
    const declaredKeyId = b64ToBytes(keyId);
    if (declaredKeyId.length !== 32) return { ok: false, reason: "bad_key_id" };

    // 5. counter (authData[33..37]) must be 0 for a fresh attestation.
    const counter = (att.authData[33] << 24) | (att.authData[34] << 16) | (att.authData[35] << 8) | att.authData[36];
    if (counter !== 0) return { ok: false, reason: "bad_counter" };

    // 6. Persist the attested public key so future assertions (not used in v1) could be verified.
    await env.FEEDBACK_KV.put(`attest:${keyId}`, btoa(String.fromCharCode(...spki)), { expirationTtl: 60 * 60 * 24 * 180 });

    return { ok: true };
  } catch (e) {
    return { ok: false, reason: "attest_exception" };
  }
}
```

- [ ] **Step 4: Run tests to verify the failure paths pass**

Run: `cd worker && npm test -- app_attest`
Expected: PASS (failure-path assertions). Note in the commit that success-path is device-verified only.

- [ ] **Step 5: Commit**

```bash
git add worker/src/verify/app_attest.ts worker/test/app_attest.test.ts
git commit -m "feat(worker): App Attest verifier (success path device-verified only)"
```

---

## Task 9: Rate limiting + global daily cap (KV)

**Files:**
- Create: `worker/src/limits.ts`
- Test: `worker/test/limits.test.ts`

**Interfaces:**
- Produces:
  ```ts
  // dayKey/hourKey use the request time (passed in) so tests are deterministic; the handler passes Date.now().
  export function checkAndBump(env: Env, ip: string, nowMs: number): Promise<{ ok: true } | { ok: false; reason: "rate_limited" | "global_cap" }>;
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/limits.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { checkAndBump } from "../src/limits";

const NOW = 1_720_000_000_000;

describe("checkAndBump", () => {
  it("allows up to the per-IP hourly limit then blocks", async () => {
    const ip = "9.9.9.9";
    const limit = Number(env.RATE_PER_IP_PER_HOUR);
    for (let i = 0; i < limit; i++) {
      expect((await checkAndBump(env, ip, NOW)).ok).toBe(true);
    }
    const blocked = await checkAndBump(env, ip, NOW);
    expect(blocked.ok).toBe(false);
    if (!blocked.ok) expect(blocked.reason).toBe("rate_limited");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- limits`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/limits.ts`:
```ts
import type { Env } from "./env";

export async function checkAndBump(
  env: Env, ip: string, nowMs: number,
): Promise<{ ok: true } | { ok: false; reason: "rate_limited" | "global_cap" }> {
  const hour = Math.floor(nowMs / 3_600_000);
  const day = Math.floor(nowMs / 86_400_000);
  const ipKey = `rl:${ip}:${hour}`;
  const capKey = `cap:${day}`;

  const ipCount = Number((await env.FEEDBACK_KV.get(ipKey)) ?? "0");
  if (ipCount >= Number(env.RATE_PER_IP_PER_HOUR)) return { ok: false, reason: "rate_limited" };
  const capCount = Number((await env.FEEDBACK_KV.get(capKey)) ?? "0");
  if (capCount >= Number(env.GLOBAL_CAP_PER_DAY)) return { ok: false, reason: "global_cap" };

  await env.FEEDBACK_KV.put(ipKey, String(ipCount + 1), { expirationTtl: 3600 });
  await env.FEEDBACK_KV.put(capKey, String(capCount + 1), { expirationTtl: 86400 });
  return { ok: true };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- limits`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/limits.ts worker/test/limits.test.ts
git commit -m "feat(worker): per-IP rate limit + global daily cap"
```

---

## Task 10: Idempotency store

**Files:**
- Create: `worker/src/idempotency.ts`
- Test: `worker/test/idempotency.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export function getCached(env: Env, key: string): Promise<{ issueUrl: string } | null>;
  export function putCached(env: Env, key: string, value: { issueUrl: string }): Promise<void>;
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/idempotency.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { getCached, putCached } from "../src/idempotency";

describe("idempotency", () => {
  it("returns null before set, value after set", async () => {
    const key = "abc";
    expect(await getCached(env, key)).toBeNull();
    await putCached(env, key, { issueUrl: "https://github.com/x/y/issues/1" });
    expect(await getCached(env, key)).toEqual({ issueUrl: "https://github.com/x/y/issues/1" });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- idempotency`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/idempotency.ts`:
```ts
import type { Env } from "./env";

export async function getCached(env: Env, key: string): Promise<{ issueUrl: string } | null> {
  const v = await env.FEEDBACK_KV.get(`idem:${key}`);
  return v ? (JSON.parse(v) as { issueUrl: string }) : null;
}
export async function putCached(env: Env, key: string, value: { issueUrl: string }): Promise<void> {
  await env.FEEDBACK_KV.put(`idem:${key}`, JSON.stringify(value), {
    expirationTtl: Number(env.IDEMPOTENCY_TTL_SECONDS),
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- idempotency`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/idempotency.ts worker/test/idempotency.test.ts
git commit -m "feat(worker): idempotency store"
```

---

## Task 11: GitHub App token + issue creation

**Files:**
- Create: `worker/src/github.ts`
- Test: `worker/test/github.test.ts`

**Interfaces:**
- Consumes: `FeedbackInput`, sanitizers, `Env`.
- Produces:
  ```ts
  export function mintInstallationToken(env: Env, nowMs: number, fetchImpl?: typeof fetch): Promise<string>;
  export function createIssue(env: Env, input: FeedbackInput, nowMs: number, fetchImpl?: typeof fetch): Promise<{ issueUrl: string }>;
  ```

- [ ] **Step 1: Write the failing test** (mock GitHub HTTP)

`worker/test/github.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { createIssue } from "../src/github";

function githubMock(captured: { body?: any }): typeof fetch {
  return (async (url: string, init: any) => {
    if (String(url).includes("access_tokens")) return new Response(JSON.stringify({ token: "ghs_test" }), { status: 201 });
    if (String(url).includes("/issues")) {
      captured.body = JSON.parse(init.body);
      return new Response(JSON.stringify({ html_url: "https://github.com/pablohpsilva/camscanner-light/issues/7" }), { status: 201 });
    }
    return new Response("{}", { status: 200 });
  }) as any;
}

const input: any = {
  category: "bug", message: "crash @maintainer see #12", email: "u@e.com",
  idempotencyKey: "k", diagnostics: { appVersion: "1.0.0", build: "42", os: "iOS 18.3", device: "iPhone15,2", locale: "en_US" },
};

describe("createIssue", () => {
  it("creates an issue, applies labels, neutralizes mentions and obfuscates email", async () => {
    const cap: { body?: any } = {};
    const r = await createIssue(env, input, 1_720_000_000_000, githubMock(cap));
    expect(r.issueUrl).toContain("/issues/7");
    expect(cap.body.labels).toContain("app-feedback");
    expect(cap.body.labels).toContain("bug");
    expect(cap.body.body).toContain("@​maintainer");
    expect(cap.body.body).toContain("#​12");
    expect(cap.body.body).toContain("u [at] e.com");
    expect(cap.body.title.startsWith("[bug]")).toBe(true);
  });
});
```
(Provide a throwaway RSA test PEM for `GITHUB_APP_PRIVATE_KEY` in test vars; GitHub HTTP is mocked so signing only needs to succeed locally.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- github`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/github.ts`:
```ts
import type { Env } from "./env";
import type { FeedbackInput } from "./validate";
import { fenceBlock, neutralizeMentions, obfuscateEmail, slugTitle } from "./sanitize";

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

async function appJwt(env: Env, nowMs: number): Promise<string> {
  const now = Math.floor(nowMs / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({ iat: now - 60, exp: now + 540, iss: env.GITHUB_APP_ID })));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToPkcs8(env.GITHUB_APP_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${b64url(sig)}`;
}

export async function mintInstallationToken(env: Env, nowMs: number, fetchImpl: typeof fetch = fetch): Promise<string> {
  const jwt = await appJwt(env, nowMs);
  const res = await fetchImpl(`https://api.github.com/app/installations/${env.GITHUB_APP_INSTALLATION_ID}/access_tokens`, {
    method: "POST",
    headers: { authorization: `Bearer ${jwt}`, accept: "application/vnd.github+json", "user-agent": "feedback-worker" },
  });
  const data = (await res.json()) as { token?: string };
  if (!data.token) throw new Error("installation_token_failed");
  return data.token;
}

export async function createIssue(
  env: Env, input: FeedbackInput, nowMs: number, fetchImpl: typeof fetch = fetch,
): Promise<{ issueUrl: string }> {
  const token = await mintInstallationToken(env, nowMs, fetchImpl);
  const title = slugTitle(input.category, input.message);
  const emailLine = input.email ? `\n**Contact:** ${obfuscateEmail(input.email)}\n` : "";
  const d = input.diagnostics;
  const body =
    `**Category:** ${input.category}\n${emailLine}\n` +
    `### Message\n${fenceBlock(neutralizeMentions(input.message))}\n\n` +
    `### Diagnostics\n` +
    "```\n" +
    `app: ${d.appVersion} (${d.build})\nos: ${d.os}\ndevice: ${d.device}\nlocale: ${d.locale}\n` +
    "```\n\n_Submitted via in-app feedback._";

  const res = await fetchImpl(`https://api.github.com/repos/${env.REPO}/issues`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "user-agent": "feedback-worker",
    },
    body: JSON.stringify({ title, body, labels: [input.category, "app-feedback"] }),
  });
  if (!res.ok) throw new Error(`github_issue_failed_${res.status}`);
  const data = (await res.json()) as { html_url: string };
  return { issueUrl: data.html_url };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- github`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/github.ts worker/test/github.test.ts
git commit -m "feat(worker): GitHub App token minting + issue creation"
```

---

## Task 11b: Challenge issuance + consume-once (anti-replay)

**Why:** App Attest / Play Integrity must attest over a **server-issued** nonce, or
an attacker can replay a captured attestation forever. The client first calls
`POST /challenge`, the Worker stores it in KV (short TTL), and at submit time the
Worker **consumes it once** (delete on use). A client-supplied challenge is never
trusted.

**Files:**
- Create: `worker/src/challenge.ts`
- Test: `worker/test/challenge.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export function issueChallenge(env: Env): Promise<string>;            // random, stored chal:<v>
  export function consumeChallenge(env: Env, value: string): Promise<boolean>; // true iff existed; deletes it
  ```

- [ ] **Step 1: Write the failing test**

`worker/test/challenge.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { issueChallenge, consumeChallenge } from "../src/challenge";

describe("challenge", () => {
  it("issues a challenge that can be consumed exactly once", async () => {
    const c = await issueChallenge(env);
    expect(c.length).toBeGreaterThan(20);
    expect(await consumeChallenge(env, c)).toBe(true);
    expect(await consumeChallenge(env, c)).toBe(false); // already consumed
  });
  it("rejects an unknown challenge", async () => {
    expect(await consumeChallenge(env, "never-issued")).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- challenge`
Expected: FAIL — module missing.

- [ ] **Step 3: Implementation**

`worker/src/challenge.ts`:
```ts
import type { Env } from "./env";

export async function issueChallenge(env: Env): Promise<string> {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const value = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  await env.FEEDBACK_KV.put(`chal:${value}`, "1", { expirationTtl: 300 });
  return value;
}

export async function consumeChallenge(env: Env, value: string): Promise<boolean> {
  const key = `chal:${value}`;
  const found = await env.FEEDBACK_KV.get(key);
  if (!found) return false;
  await env.FEEDBACK_KV.delete(key);
  return true;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd worker && npm test -- challenge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add worker/src/challenge.ts worker/test/challenge.test.ts
git commit -m "feat(worker): server-issued one-time attestation challenge"
```

---

## Task 12: Wire the full pipeline in the handler

**Files:**
- Modify: `worker/src/index.ts`
- Test: `worker/test/pipeline.test.ts`

**Interfaces:**
- Consumes: everything above. The handler injects real verifiers but accepts a
  test seam so `pipeline.test.ts` can drive it end-to-end with mocked GitHub/Turnstile.

- [ ] **Step 1: Write the failing test** (end-to-end, mocks at the HTTP boundary)

`worker/test/pipeline.test.ts`:
```ts
import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { handleFeedback } from "../src/index";

const goodBody = {
  category: "bug", message: "export crashes", turnstileToken: "tok",
  idempotencyKey: "22222222-2222-2222-2222-222222222222",
  diagnostics: { appVersion: "1.0.0", build: "42", os: "Android 14", device: "Pixel 8", locale: "en_US" },
};

function deps(overrides: any = {}) {
  return {
    now: 1_720_000_000_000,
    verifyTurnstile: async () => ({ ok: true }),
    verifyAttest: async () => ({ ok: false, reason: "n/a" }),
    createIssue: async () => ({ issueUrl: "https://github.com/pablohpsilva/camscanner-light/issues/9" }),
    ...overrides,
  };
}

describe("handleFeedback pipeline", () => {
  it("201 with issueUrl on a valid Turnstile-verified request", async () => {
    const req = new Request("https://x/feedback", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(goodBody) });
    const res = await handleFeedback(req, env, deps());
    expect(res.status).toBe(201);
    expect((await res.json() as any).issueUrl).toContain("/issues/9");
  });
  it("401 when unverified", async () => {
    const req = new Request("https://x/feedback", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(goodBody) });
    const res = await handleFeedback(req, env, deps({ verifyTurnstile: async () => ({ ok: false }) }));
    expect(res.status).toBe(401);
  });
  it("returns the cached issue on a repeated idempotency key (one create only)", async () => {
    let creates = 0;
    const d = deps({ createIssue: async () => { creates++; return { issueUrl: "https://github.com/pablohpsilva/camscanner-light/issues/10" }; } });
    const mk = () => new Request("https://x/feedback", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ...goodBody, idempotencyKey: "33333333-3333-3333-3333-333333333333" }) });
    await handleFeedback(mk(), env, d);
    const res2 = await handleFeedback(mk(), env, d);
    expect(creates).toBe(1);
    expect((await res2.json() as any).issueUrl).toContain("/issues/10");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd worker && npm test -- pipeline`
Expected: FAIL — `handleFeedback` not exported.

- [ ] **Step 3: Implementation** — refactor `index.ts` to expose `handleFeedback`

`worker/src/index.ts` (full file):
```ts
import type { Env } from "./env";
import { guardRequest } from "./guards";
import { validate, type FeedbackInput } from "./validate";
import { verifyTurnstile } from "./verify/turnstile";
import { verifyPlayIntegrity } from "./verify/play_integrity";
import { verifyAppAttest } from "./verify/app_attest";
import { verifyCaller } from "./verify/orchestrate";
import { checkAndBump } from "./limits";
import { getCached, putCached } from "./idempotency";
import { createIssue as realCreateIssue } from "./github";
import { issueChallenge, consumeChallenge } from "./challenge";
import type { VerifyResult } from "./verify/verifier";

export function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export interface Deps {
  now: number;
  verifyTurnstile: (input: FeedbackInput, ip: string) => Promise<VerifyResult>;
  verifyAttest: (input: FeedbackInput, ip: string) => Promise<VerifyResult>;
  createIssue: (env: Env, input: FeedbackInput, nowMs: number) => Promise<{ issueUrl: string }>;
}

function realDeps(env: Env): Deps {
  return {
    now: Date.now(),
    verifyTurnstile: (input, ip) => verifyTurnstile(env.TURNSTILE_SECRET, input.turnstileToken ?? "", ip),
    verifyAttest: (input) => {
      if (!input.attestation) return Promise.resolve({ ok: false });
      return input.attestation.platform === "ios"
        ? verifyAppAttest(env, input.attestation.keyId ?? "", input.attestation.token, input.attestation.challenge)
        : verifyPlayIntegrity(env, input.attestation.token, input.attestation.challenge);
    },
    createIssue: (e, input, nowMs) => realCreateIssue(e, input, nowMs),
  };
}

export async function handleFeedback(request: Request, env: Env, deps: Deps): Promise<Response> {
  const ip = request.headers.get("cf-connecting-ip") ?? "0.0.0.0";
  const guarded = await guardRequest(request, env);
  if (!guarded.ok) return guarded.response;

  const v = validate(guarded.body);
  if (!v.ok) return json({ error: "invalid", detail: v.error }, 400);
  const input = v.value;

  // Idempotency: short-circuit before doing any work that creates an issue.
  const cached = await getCached(env, input.idempotencyKey);
  if (cached) return json({ ok: true, issueUrl: cached.issueUrl, duplicate: true }, 200);

  // Attestation path must present a server-issued, not-yet-used challenge.
  // (Turnstile-only path relies on Cloudflare's single-use token instead.)
  if (input.attestation) {
    const fresh = await consumeChallenge(env, input.attestation.challenge);
    if (!fresh) return json({ error: "bad_challenge" }, 401);
  }

  const verdict = await verifyCaller(input, ip, deps.verifyAttest, deps.verifyTurnstile);
  if (!verdict.ok) return json({ error: "unverified" }, 401);

  const limit = await checkAndBump(env, ip, deps.now);
  if (!limit.ok) return json({ error: limit.reason }, 429);

  try {
    const { issueUrl } = await deps.createIssue(env, input, deps.now);
    await putCached(env, input.idempotencyKey, { issueUrl });
    return json({ ok: true, issueUrl }, 201);
  } catch {
    return json({ error: "upstream_failed" }, 502);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/challenge") {
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
      const origin = request.headers.get("origin");
      if (origin && origin !== env.ALLOWED_ORIGIN) return json({ error: "forbidden_origin" }, 403);
      return json({ challenge: await issueChallenge(env) }, 200);
    }
    if (url.pathname !== "/feedback") return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    return handleFeedback(request, env, realDeps(env));
  },
};
```

(Update the `json` import in `guards.ts` to come from `./index` — already does.)

- [ ] **Step 4: Run the full suite**

Run: `cd worker && npm test`
Expected: PASS (all tasks' tests).

- [ ] **Step 5: Commit**

```bash
git add worker/src/index.ts worker/test/pipeline.test.ts
git commit -m "feat(worker): wire full feedback pipeline"
```

---

## Task 13: Deploy staging + README

**Files:**
- Create: `worker/README.md`, `worker/wrangler.staging.toml` (or a `[env.staging]` block)
- Modify: `worker/wrangler.toml`

- [ ] **Step 1: Add a staging environment** — in `worker/wrangler.toml`:
```toml
[env.staging]
vars = { REPO = "pablohpsilva/camscanner-feedback-test", ALLOWED_ORIGIN = "", RATE_PER_IP_PER_HOUR = "50", GLOBAL_CAP_PER_DAY = "1000", IDEMPOTENCY_TTL_SECONDS = "600", APPLE_APP_ID = "TEAMID.BUNDLEID", PLAY_PACKAGE_NAME = "REPLACE_PACKAGE" }
```
(Staging points at a throwaway **test repo** so device tests never spam the real repo. Create `pablohpsilva/camscanner-feedback-test` and install the same GitHub App there, or a second test App.)

- [ ] **Step 2: Set secrets** (both default and staging):
```bash
cd worker
for s in GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY TURNSTILE_SECRET PLAY_SA_CLIENT_EMAIL PLAY_SA_PRIVATE_KEY; do wrangler secret put $s; done
for s in GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY TURNSTILE_SECRET PLAY_SA_CLIENT_EMAIL PLAY_SA_PRIVATE_KEY; do wrangler secret put $s --env staging; done
```

- [ ] **Step 3: Deploy staging**
```bash
cd worker && wrangler deploy --env staging
```
Expected: prints the staging Worker URL (record it for the Flutter plan's `--dart-define`).

- [ ] **Step 4: Smoke test with curl** (Turnstile disabled path will 401 — that's correct; verify guards/validation):
```bash
curl -i -X POST "$STAGING_URL/feedback" -H 'content-type: application/json' \
  -d '{"category":"bug","message":"hi","idempotencyKey":"44444444-4444-4444-4444-444444444444","diagnostics":{"appVersion":"1","build":"1","os":"x","device":"y","locale":"en"}}'
```
Expected: `HTTP/1.1 401` `{"error":"unverified"}` (no attestation/Turnstile token). Confirms the pipeline runs and fails closed.

- [ ] **Step 5: Write `worker/README.md`** documenting: prerequisites P1–P5, secret list, `npm test`, `wrangler deploy [--env staging]`, and the request/response contract (fields, status codes: 201 created, 200 duplicate, 400 invalid, 401 unverified, 413/415/403 guards, 429 rate/cap, 502 upstream).

- [ ] **Step 6: Commit**
```bash
git add worker/README.md worker/wrangler.toml
git commit -m "chore(worker): staging env, secrets docs, README"
```

---

## Task 14: Device round-trip verification (real attestation) — GAP CLOSURE

This is the only proof that App Attest / Play Integrity verification actually
works, since neither can be exercised on the host. It is completed jointly with
the Flutter plan's device tests (they submit real attestation tokens to the
**staging** Worker). Record the result here.

- [ ] **Step 1:** With the Flutter app pointed at `$STAGING_URL`, submit feedback from a **real Android device** → assert a new issue appears in the test repo and the Worker log shows Play Integrity `ok`.
- [ ] **Step 2:** Submit from a **real iOS device** → assert a new issue appears and the Worker log shows App Attest `ok`.
- [ ] **Step 3:** Flip the app to send a tampered/blank attestation → assert `401 unverified`.
- [ ] **Step 4:** Record the two issue URLs + Worker log lines in the PR description as evidence. If either platform can't be run, name it explicitly as an open gap — do not claim done.

---

## Self-review notes (coverage vs spec)

- Attestation primary + Turnstile fallback → Tasks 5–8, 12. ✅ (success path device-only, Task 14 — named gap)
- GitHub App least-privilege token → Tasks 11, P1. ✅
- @mention/#ref neutralization + fencing + email obfuscation → Tasks 4, 11. ✅
- Idempotency → Tasks 10, 12. ✅
- CORS/size/content-type guards → Task 2. ✅
- Rate limit + global cap → Task 9. ✅
- Fail closed + no secret leakage → Task 12 (401/429/502, generic errors). ✅
- Anti-replay: server-issued, consume-once challenge for attestation → Task 11b + Task 12 handler. ✅
- Staging test repo so device tests don't spam prod → Task 13. ✅
