import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { createIssue } from "../src/github";

function githubMock(captured: { body?: any }): typeof fetch {
  return (async (url: string, init: any) => {
    if (String(url).includes("access_tokens")) return new Response(JSON.stringify({ token: "ghs_test" }), { status: 201 });
    if (String(url).includes("/issues")) {
      captured.body = JSON.parse(init.body);
      return new Response(JSON.stringify({ html_url: "https://github.com/pablohpsilva/camscanner-light/issues/7" }), { status: 201 });
    }
    return new Response("{}", { status: 200 });
  }) as any;
}

const input: any = {
  category: "bug", message: "crash @maintainer see #12", email: "u@e.com",
  idempotencyKey: "k", diagnostics: { appVersion: "1.0.0", build: "42", os: "iOS 18.3", device: "iPhone15,2", locale: "en_US" },
};

describe("createIssue", () => {
  it("creates an issue, applies labels, neutralizes mentions and obfuscates email", async () => {
    const cap: { body?: any } = {};
    const r = await createIssue(env, input, 1_720_000_000_000, githubMock(cap));
    expect(r.issueUrl).toContain("/issues/7");
    expect(cap.body.labels).toContain("app-feedback");
    expect(cap.body.labels).toContain("bug");
    expect(cap.body.body).toContain("@​maintainer");
    expect(cap.body.body).toContain("#​12");
    expect(cap.body.body).toContain("u [at] e.com");
    expect(cap.body.title.startsWith("[bug]")).toBe(true);
  });
});
