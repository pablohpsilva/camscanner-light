import { describe, it, expect } from "vitest";
import { validate } from "../src/validate";

const base = {
  category: "bug",
  message: "It crashed on export",
  idempotencyKey: "11111111-1111-1111-1111-111111111111",
  diagnostics: { appVersion: "1.0.0", build: "42", os: "iOS 18.3", device: "iPhone15,2", locale: "en_US" },
};

describe("validate", () => {
  it("accepts a minimal valid payload", () => {
    const r = validate(base);
    expect(r.ok).toBe(true);
  });
  it("rejects empty message", () => {
    expect(validate({ ...base, message: "   " }).ok).toBe(false);
  });
  it("rejects message over 4000 chars", () => {
    expect(validate({ ...base, message: "a".repeat(4001) }).ok).toBe(false);
  });
  it("rejects unknown category", () => {
    expect(validate({ ...base, category: "spam" }).ok).toBe(false);
  });
  it("rejects malformed email when present", () => {
    expect(validate({ ...base, email: "not-an-email" }).ok).toBe(false);
  });
  it("accepts a valid email", () => {
    expect(validate({ ...base, email: "a@b.com" }).ok).toBe(true);
  });
  it("rejects missing idempotencyKey", () => {
    const { idempotencyKey, ...noKey } = base;
    expect(validate(noKey).ok).toBe(false);
  });
});
