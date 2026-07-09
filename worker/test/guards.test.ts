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
