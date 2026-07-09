import type { Env } from "./env";
import { checkHealth } from "./health";
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
    if (url.pathname === "/health") {
      if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405);
      return checkHealth(env) ? json({ ok: true }, 200) : json({ ok: false }, 503);
    }
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
