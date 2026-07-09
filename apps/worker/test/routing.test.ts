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
