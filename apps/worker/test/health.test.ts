import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker from "../src/index";
import { checkHealth } from "../src/health";

describe("checkHealth", () => {
  it("returns true for the fully-configured test env", () => {
    expect(checkHealth(env)).toBe(true);
  });

  it("returns false when TURNSTILE_SECRET is blank", () => {
    expect(checkHealth({ ...env, TURNSTILE_SECRET: "" } as any)).toBe(false);
  });

  it("returns false when GITHUB_APP_PRIVATE_KEY is blank", () => {
    expect(checkHealth({ ...env, GITHUB_APP_PRIVATE_KEY: "" } as any)).toBe(false);
  });
});

describe("GET /health (routing)", () => {
  it("returns 200 and {ok:true} when env is fully configured", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(new Request("https://x/health"), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it("returns 405 for POST /health", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(new Request("https://x/health", { method: "POST" }), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(405);
    const body = await res.json() as { error: string };
    expect(body.error).toBe("method_not_allowed");
  });
});
