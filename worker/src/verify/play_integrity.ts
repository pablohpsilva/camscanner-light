import type { Env } from "../env";
import type { VerifyResult } from "./verifier";
import { googleAccessToken } from "../google_token";

export async function verifyPlayIntegrity(
  env: Env,
  token: string,
  expectedChallenge: string,
  fetchImpl: typeof fetch = fetch,
): Promise<VerifyResult> {
  if (!token) return { ok: false, reason: "no_play_token" };
  const at = await googleAccessToken(
    env.PLAY_SA_CLIENT_EMAIL,
    env.PLAY_SA_PRIVATE_KEY,
    "https://www.googleapis.com/auth/playintegrity",
    fetchImpl,
  );
  const url = `https://playintegrity.googleapis.com/v1/${env.PLAY_PACKAGE_NAME}:decodeIntegrityToken`;
  const res = await fetchImpl(url, {
    method: "POST",
    headers: { authorization: `Bearer ${at}`, "content-type": "application/json" },
    body: JSON.stringify({ integrityToken: token }),
  });
  if (!res.ok) return { ok: false, reason: "play_decode_failed" };
  const data = (await res.json()) as { tokenPayloadExternal?: any };
  const p = data.tokenPayloadExternal;
  if (!p) return { ok: false, reason: "play_no_payload" };
  if (p.requestDetails?.requestHash !== expectedChallenge) return { ok: false, reason: "play_challenge_mismatch" };
  if (p.requestDetails?.requestPackageName !== env.PLAY_PACKAGE_NAME) return { ok: false, reason: "play_package_mismatch" };
  if (p.appIntegrity?.appRecognitionVerdict !== "PLAY_RECOGNIZED") return { ok: false, reason: "play_app_unrecognized" };
  const dev: string[] = p.deviceIntegrity?.deviceRecognitionVerdict ?? [];
  if (!dev.includes("MEETS_DEVICE_INTEGRITY")) return { ok: false, reason: "play_device_integrity" };
  return { ok: true };
}
