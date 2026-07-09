export interface FeedbackInput {
  category: "bug" | "idea" | "question";
  message: string;
  email?: string;
  attestation?: { platform: "ios" | "android"; token: string; keyId?: string; challenge: string };
  turnstileToken?: string;
  idempotencyKey: string;
  diagnostics: { appVersion: string; build: string; os: string; device: string; locale: string };
}

const CATEGORIES = ["bug", "idea", "question"] as const;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function str(v: unknown, max: number): string | null {
  return typeof v === "string" && v.length <= max ? v : null;
}

export function validate(body: unknown): { ok: true; value: FeedbackInput } | { ok: false; error: string } {
  if (typeof body !== "object" || body === null) return { ok: false, error: "not_object" };
  const b = body as Record<string, unknown>;

  if (!CATEGORIES.includes(b.category as any)) return { ok: false, error: "bad_category" };
  const message = str(b.message, 4000);
  if (!message || message.trim().length === 0) return { ok: false, error: "bad_message" };
  if (typeof b.idempotencyKey !== "string" || !UUID_RE.test(b.idempotencyKey))
    return { ok: false, error: "bad_idempotency_key" };

  let email: string | undefined;
  if (b.email !== undefined && b.email !== "") {
    const e = str(b.email, 254);
    if (!e || !EMAIL_RE.test(e)) return { ok: false, error: "bad_email" };
    email = e;
  }

  const d = b.diagnostics as Record<string, unknown> | undefined;
  if (!d || typeof d !== "object") return { ok: false, error: "bad_diagnostics" };
  const diagnostics = {
    appVersion: str(d.appVersion, 40) ?? "",
    build: str(d.build, 40) ?? "",
    os: str(d.os, 80) ?? "",
    device: str(d.device, 80) ?? "",
    locale: str(d.locale, 40) ?? "",
  };

  let attestation: FeedbackInput["attestation"];
  const a = b.attestation as Record<string, unknown> | undefined;
  if (a && (a.platform === "ios" || a.platform === "android")) {
    const token = str(a.token, 12000);
    const challenge = str(a.challenge, 200);
    if (token && challenge) {
      attestation = {
        platform: a.platform,
        token,
        challenge,
        keyId: str(a.keyId ?? "", 200) || undefined,
      };
    }
  }

  const turnstileToken = str(b.turnstileToken ?? "", 4000) || undefined;

  return {
    ok: true,
    value: { category: b.category as any, message, email, attestation, turnstileToken, idempotencyKey: b.idempotencyKey, diagnostics },
  };
}
