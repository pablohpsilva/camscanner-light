import { env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { X509Certificate, X509CertificateGenerator } from "@peculiar/x509";
import { verifyAppAttest, isPinnedAppleRoot } from "../src/verify/app_attest";

describe("verifyAppAttest (failure paths)", () => {
  it("rejects empty attestation", async () => {
    const r = await verifyAppAttest(env, "kid", "", "chal");
    expect(r.ok).toBe(false);
  });
  it("rejects non-CBOR garbage", async () => {
    const r = await verifyAppAttest(env, "kid", btoa("not cbor at all"), "chal");
    expect(r.ok).toBe(false);
  });
  it("rejects a CBOR object missing attStmt/authData", async () => {
    // minimal CBOR map {"x":1} base64
    const r = await verifyAppAttest(env, "kid", btoa("\xa1axa\x01"), "chal");
    expect(r.ok).toBe(false);
  });
});

describe("isPinnedAppleRoot", () => {
  it("accepts the real Apple App Attest Root CA by raw bytes", () => {
    // The Apple root PEM is the same constant embedded in app_attest.ts.
    // Constructing from the same PEM must yield true — byte-for-byte match.
    const APPLE_APP_ATTEST_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEA3YsaNkGNM8k5MtqxjWyPRj1sdOWmfvDktdmT
XTh6+kmr9Xr1L+2i5+iw0PZ3S8VG
-----END CERTIFICATE-----`;
    const realRoot = new X509Certificate(APPLE_APP_ATTEST_ROOT);
    expect(isPinnedAppleRoot(realRoot)).toBe(true);
  });

  it("rejects a name-forged self-signed cert whose subject DN matches the Apple root", async () => {
    // This directly proves the vulnerability (CVE-class: attestation bypass via DN
    // forgery) is closed. A cert with the exact same subject as the Apple root but
    // signed by a different key MUST NOT pass the gate.
    const alg = { name: "ECDSA", namedCurve: "P-384", hash: "SHA-384" } as const;
    const keys = await crypto.subtle.generateKey(alg, false, ["sign", "verify"]);
    const rogue = await X509CertificateGenerator.createSelfSigned({
      serialNumber: "01",
      name: "CN=Apple App Attest Root CA, O=Apple Inc., ST=California",
      notBefore: new Date("2020-01-01"),
      notAfter: new Date("2045-01-01"),
      keys,
      signingAlgorithm: alg,
    });
    expect(isPinnedAppleRoot(rogue)).toBe(false);
  });
});
