import type { Env } from "./env";

export async function issueChallenge(env: Env): Promise<string> {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const value = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  await env.FEEDBACK_KV.put(`chal:${value}`, "1", { expirationTtl: 300 });
  return value;
}

export async function consumeChallenge(env: Env, value: string): Promise<boolean> {
  const key = `chal:${value}`;
  const found = await env.FEEDBACK_KV.get(key);
  if (!found) return false;
  await env.FEEDBACK_KV.delete(key);
  return true;
}
