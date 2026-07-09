export interface VerifyResult { ok: boolean; reason?: string }

export async function verifyTurnstile(
  secret: string,
  token: string,
  ip: string,
  fetchImpl: typeof fetch = fetch,
): Promise<VerifyResult> {
  if (!token) return { ok: false, reason: "no_turnstile_token" };
  const form = new FormData();
  form.append("secret", secret);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  const res = await fetchImpl("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: form,
  });
  const data = (await res.json()) as { success: boolean };
  return data.success ? { ok: true } : { ok: false, reason: "turnstile_failed" };
}
