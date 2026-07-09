import { b64url, pemToPkcs8 } from "./crypto_util";

export async function googleAccessToken(
  email: string,
  privateKeyPem: string,
  scope: string,
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(new TextEncoder().encode(JSON.stringify({
    iss: email, scope, aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  })));
  const signingInput = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)),
  );
  const jwt = `${signingInput}.${b64url(sig)}`;
  const res = await fetchImpl("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")}&assertion=${jwt}`,
  });
  const data = (await res.json()) as { access_token?: string };
  if (!data.access_token) throw new Error("google_token_failed");
  return data.access_token;
}
