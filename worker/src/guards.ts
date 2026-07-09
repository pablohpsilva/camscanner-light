import type { Env } from "./env";
import { json } from "./index";

const MAX_BODY_BYTES = 16 * 1024;

export async function guardRequest(
  request: Request,
  env: Env,
): Promise<{ ok: true; body: unknown } | { ok: false; response: Response }> {
  const origin = request.headers.get("origin");
  // Native app sends no Origin. Any browser Origin that isn't the allowlisted one is rejected.
  if (origin && origin !== env.ALLOWED_ORIGIN) {
    return { ok: false, response: json({ error: "forbidden_origin" }, 403) };
  }
  const ct = request.headers.get("content-type") ?? "";
  if (!ct.includes("application/json")) {
    return { ok: false, response: json({ error: "unsupported_media_type" }, 415) };
  }
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) {
    return { ok: false, response: json({ error: "payload_too_large" }, 413) };
  }
  try {
    return { ok: true, body: JSON.parse(raw) };
  } catch {
    return { ok: false, response: json({ error: "bad_json" }, 400) };
  }
}
