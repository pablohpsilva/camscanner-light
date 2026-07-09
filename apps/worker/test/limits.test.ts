import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { checkAndBump } from "../src/limits";

const NOW = 1_720_000_000_000;

describe("checkAndBump", () => {
  it("allows up to the per-IP hourly limit then blocks", async () => {
    const ip = "9.9.9.9";
    const limit = Number(env.RATE_PER_IP_PER_HOUR);
    for (let i = 0; i < limit; i++) {
      expect((await checkAndBump(env, ip, NOW)).ok).toBe(true);
    }
    const blocked = await checkAndBump(env, ip, NOW);
    expect(blocked.ok).toBe(false);
    if (!blocked.ok) expect(blocked.reason).toBe("rate_limited");
  });
});
