import type { Env } from "./env";
import type { FeedbackInput } from "./validate";
import { fenceBlock, neutralizeMentions, obfuscateEmail, slugTitle } from "./sanitize";
import { b64url, pemToPkcs8 } from "./crypto_util";

async function appJwt(env: Env, nowMs: number): Promise<string> {
  const now = Math.floor(nowMs / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({ iat: now - 60, exp: now + 540, iss: env.GITHUB_APP_ID })));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToPkcs8(env.GITHUB_APP_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)));
  return `${signingInput}.${b64url(sig)}`;
}

export async function mintInstallationToken(env: Env, nowMs: number, fetchImpl: typeof fetch = fetch): Promise<string> {
  const jwt = await appJwt(env, nowMs);
  const res = await fetchImpl(`https://api.github.com/app/installations/${env.GITHUB_APP_INSTALLATION_ID}/access_tokens`, {
    method: "POST",
    headers: { authorization: `Bearer ${jwt}`, accept: "application/vnd.github+json", "user-agent": "feedback-worker" },
  });
  const data = (await res.json()) as { token?: string };
  if (!data.token) throw new Error("installation_token_failed");
  return data.token;
}

export async function createIssue(
  env: Env, input: FeedbackInput, nowMs: number, fetchImpl: typeof fetch = fetch,
): Promise<{ issueUrl: string }> {
  const token = await mintInstallationToken(env, nowMs, fetchImpl);
  const title = slugTitle(input.category, input.message);
  const emailLine = input.email ? `\n**Contact:** ${obfuscateEmail(input.email)}\n` : "";
  const d = input.diagnostics;
  const body =
    `**Category:** ${input.category}\n${emailLine}\n` +
    `### Message\n${fenceBlock(neutralizeMentions(input.message))}\n\n` +
    `### Diagnostics\n` +
    "```\n" +
    `app: ${d.appVersion} (${d.build})\nos: ${d.os}\ndevice: ${d.device}\nlocale: ${d.locale}\n` +
    "```\n\n_Submitted via in-app feedback._";

  const res = await fetchImpl(`https://api.github.com/repos/${env.REPO}/issues`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "user-agent": "feedback-worker",
    },
    body: JSON.stringify({ title, body, labels: [input.category, "app-feedback"] }),
  });
  if (!res.ok) throw new Error(`github_issue_failed_${res.status}`);
  const data = (await res.json()) as { html_url: string };
  return { issueUrl: data.html_url };
}
