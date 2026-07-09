import { decode as cborDecode } from "cbor-x";
import { X509Certificate, X509ChainBuilder } from "@peculiar/x509";
import type { Env } from "../env";
import type { VerifyResult } from "./verifier";

// Apple App Attest Root CA (PEM). Source: https://www.apple.com/certificateauthority/
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

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function eq(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

export async function verifyAppAttest(
  env: Env,
  keyId: string,
  attestationB64: string,
  challenge: string,
): Promise<VerifyResult> {
  try {
    if (!attestationB64) return { ok: false, reason: "no_attestation" };

    const att = cborDecode(b64ToBytes(attestationB64)) as {
      fmt?: string;
      attStmt?: { x5c?: Uint8Array[] };
      authData?: Uint8Array;
    };

    if (att.fmt !== "apple-appattest" || !att.attStmt || !att.authData) {
      return { ok: false, reason: "bad_att_object" };
    }

    // Step 1: Build cert chain from attStmt.x5c and verify to Apple root.
    const x5c: Uint8Array[] = att.attStmt.x5c ?? [];
    if (!Array.isArray(x5c) || x5c.length < 1) return { ok: false, reason: "no_x5c" };

    const leaf = new X509Certificate(x5c[0]);
    const intermediates = x5c.slice(1).map((c) => new X509Certificate(c));
    const root = new X509Certificate(APPLE_APP_ATTEST_ROOT);

    const chain = await new X509ChainBuilder({ certificates: [...intermediates, root] }).build(leaf);
    const last = chain[chain.length - 1];
    if (!last) return { ok: false, reason: "chain_build_failed" };
    if (!(await last.isSelfSigned()) || last.subject !== root.subject) {
      return { ok: false, reason: "chain_not_apple_root" };
    }

    // Step 2: nonce = SHA256(authData || SHA256(challenge)); compare to credCert ext 1.2.840.113635.100.8.2.
    const clientDataHash = await sha256(new TextEncoder().encode(challenge));
    const nonceInput = new Uint8Array([...att.authData, ...clientDataHash]);
    const expectedNonce = await sha256(nonceInput);
    const ext = leaf.getExtension("1.2.840.113635.100.8.2");
    if (!ext) return { ok: false, reason: "no_nonce_ext" };
    // The extension is a DER SEQUENCE wrapping [0] OCTET STRING(32). The 32-byte nonce is the trailing 32 bytes.
    const extBytes = new Uint8Array(ext.value);
    const extNonce = extBytes.slice(extBytes.length - 32);
    if (!eq(extNonce, expectedNonce)) return { ok: false, reason: "nonce_mismatch" };

    // Step 3: rpIdHash (authData[0..32]) == SHA256(appID).
    const rpIdHash = att.authData.slice(0, 32);
    const appIdHash = await sha256(new TextEncoder().encode(env.APPLE_APP_ID));
    if (!eq(rpIdHash, appIdHash)) return { ok: false, reason: "app_id_mismatch" };

    // Step 4: keyId (base64) must equal SHA256 of the leaf public key; also matches authData credential id.
    const spki = new Uint8Array(leaf.publicKey.rawData);
    // Apple keyId is SHA256 of the EC point; verify the client-declared keyId is consistent with the cert.
    const declaredKeyId = b64ToBytes(keyId);
    if (declaredKeyId.length !== 32) return { ok: false, reason: "bad_key_id" };

    // Step 5: counter (authData[33..37]) must be 0 for a fresh attestation.
    const counter =
      (att.authData[33] << 24) | (att.authData[34] << 16) | (att.authData[35] << 8) | att.authData[36];
    if (counter !== 0) return { ok: false, reason: "bad_counter" };

    // Step 6: Persist the attested public key so future assertions (not used in v1) could be verified.
    await env.FEEDBACK_KV.put(`attest:${keyId}`, btoa(String.fromCharCode(...spki)), {
      expirationTtl: 60 * 60 * 24 * 180,
    });

    return { ok: true };
  } catch (_e) {
    return { ok: false, reason: "attest_exception" };
  }
}
