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
