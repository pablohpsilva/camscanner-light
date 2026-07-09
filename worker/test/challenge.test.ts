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
