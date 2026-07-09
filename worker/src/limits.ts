import type { Env } from "./env";

export async function checkAndBump(
  env: Env, ip: string, nowMs: number,
): Promise<{ ok: true } | { ok: false; reason: "rate_limited" | "global_cap" }> {
  const hour = Math.floor(nowMs / 3_600_000);
  const day = Math.floor(nowMs / 86_400_000);
  const ipKey = `rl:${ip}:${hour}`;
  const capKey = `cap:${day}`;

  const ipCount = Number((await env.FEEDBACK_KV.get(ipKey)) ?? "0");
  if (ipCount >= Number(env.RATE_PER_IP_PER_HOUR)) return { ok: false, reason: "rate_limited" };
  const capCount = Number((await env.FEEDBACK_KV.get(capKey)) ?? "0");
  if (capCount >= Number(env.GLOBAL_CAP_PER_DAY)) return { ok: false, reason: "global_cap" };

  await env.FEEDBACK_KV.put(ipKey, String(ipCount + 1), { expirationTtl: 3600 });
  await env.FEEDBACK_KV.put(capKey, String(capCount + 1), { expirationTtl: 86400 });
  return { ok: true };
}
