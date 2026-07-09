import { describe, it, expect } from "vitest";
import { neutralizeMentions, fenceBlock, obfuscateEmail, slugTitle } from "../src/sanitize";

describe("sanitize", () => {
  it("neutralizes @mentions and #refs with zero-width space", () => {
    const out = neutralizeMentions("hi @maintainer see #123");
    expect(out).toContain("@​maintainer");
    expect(out).toContain("#​123");
  });
  it("wraps content in a code fence", () => {
    expect(fenceBlock("hello")).toBe("```\nhello\n```");
  });
  it("neutralizes backtick fences inside the message", () => {
    expect(fenceBlock("a```b")).not.toContain("\n```b");
  });
  it("obfuscates an email", () => {
    expect(obfuscateEmail("user@example.com")).toBe("user [at] example.com");
  });
  it("builds a bounded, mention-free title", () => {
    const t = slugTitle("bug", "@here everything is broken ".repeat(10));
    expect(t.startsWith("[bug]")).toBe(true);
    expect(t.length).toBeLessThanOrEqual(80);
    expect(t).not.toContain("@here");
  });
});
