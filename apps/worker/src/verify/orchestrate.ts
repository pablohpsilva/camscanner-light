import type { FeedbackInput } from "../validate";
import type { VerifyResult } from "./verifier";

export type AttestFn = (input: FeedbackInput, ip: string) => Promise<VerifyResult>;
export type TurnstileFn = (input: FeedbackInput, ip: string) => Promise<VerifyResult>;

export async function verifyCaller(
  input: FeedbackInput,
  ip: string,
  attest: AttestFn,
  turnstile: TurnstileFn,
): Promise<VerifyResult> {
  if (input.attestation) {
    const a = await attest(input, ip);
    if (a.ok) return a;
  }
  const t = await turnstile(input, ip);
  if (t.ok) return t;
  return { ok: false, reason: "unverified" };
}
