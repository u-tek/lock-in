// ES256 JSON Web Tokens signed with Web Crypto, which Workers and Node both have, so there are no
// dependencies. APNs provider tokens are the only user in M0; Sign in with Apple's client secret
// (M2) is the same signature with different claims.

const encoder = new TextEncoder();

export function base64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string" ? encoder.encode(data) : new Uint8Array(data);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * The DER bytes inside a PKCS#8 PEM: the `.p8` file Apple lets you download once.
 *
 * Tolerates what happens to a key on its way into a secret: Windows line endings, a byte order
 * mark, or newlines flattened to a literal `\n`. Errors never include the key itself.
 */
export function pemToPKCS8(pem: string): ArrayBuffer {
  if (pem.includes("BEGIN EC PRIVATE KEY")) {
    throw new Error("Expected a PKCS#8 key (BEGIN PRIVATE KEY), like Apple's .p8 file, not a SEC1 EC key");
  }
  const body = pem
    .replace(/\\[rn]/g, "")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/[\s﻿]+/g, "");
  if (body.length === 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(body)) {
    throw new Error("The private key isn't a PEM .p8 file");
  }
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/** Imports a `.p8` key for ES256 signing. Not extractable: the key never leaves Web Crypto again. */
export function importP8(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("pkcs8", pemToPKCS8(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

export interface JWTHeader {
  /** The key's ID from the developer portal. */
  kid: string;
  typ?: "JWT";
}

/**
 * Signs `claims` as an ES256 JWT. The header is `{"alg":"ES256","kid":…}`, which is all APNs wants.
 *
 * Web Crypto returns the raw r||s signature that JWS wants, not DER, so no conversion is needed.
 */
export async function signES256(header: JWTHeader, claims: Record<string, unknown>, key: CryptoKey): Promise<string> {
  const signingInput = `${base64url(JSON.stringify({ alg: "ES256", ...header }))}.${base64url(JSON.stringify(claims))}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(signature)}`;
}
