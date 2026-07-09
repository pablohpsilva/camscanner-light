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
