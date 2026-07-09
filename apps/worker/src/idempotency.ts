import type { Env } from "./env";

export async function getCached(env: Env, key: string): Promise<{ issueUrl: string } | null> {
  const v = await env.FEEDBACK_KV.get(`idem:${key}`);
  return v ? (JSON.parse(v) as { issueUrl: string }) : null;
}
export async function putCached(env: Env, key: string, value: { issueUrl: string }): Promise<void> {
  await env.FEEDBACK_KV.put(`idem:${key}`, JSON.stringify(value), {
    expirationTtl: Number(env.IDEMPOTENCY_TTL_SECONDS),
  });
}
