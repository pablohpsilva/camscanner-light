import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { getCached, putCached } from "../src/idempotency";

describe("idempotency", () => {
  it("returns null before set, value after set", async () => {
    const key = "abc";
    expect(await getCached(env, key)).toBeNull();
    await putCached(env, key, { issueUrl: "https://github.com/x/y/issues/1" });
    expect(await getCached(env, key)).toEqual({ issueUrl: "https://github.com/x/y/issues/1" });
  });
});
