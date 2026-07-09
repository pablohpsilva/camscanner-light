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
