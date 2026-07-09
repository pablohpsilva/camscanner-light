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
