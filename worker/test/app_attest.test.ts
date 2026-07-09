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
