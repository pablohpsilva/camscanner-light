import type { FeedbackInput } from "../validate";
export interface VerifyResult { ok: boolean; reason?: string }
export interface Verifier { verify(input: FeedbackInput, ip: string): Promise<VerifyResult>; }
