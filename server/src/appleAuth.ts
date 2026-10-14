// Sign in with Apple, server side (docs/milestones/M2.md):
//
// * verifying the identity token the app sends: an RS256 JWT signed with one of Apple's published
//   keys, for our bundle ID, unexpired; its `sub` is the account's stable Apple user id;
// * swapping the one-time authorisation code for a refresh token, and revoking that token when the
//   account is deleted, as Apple requires. Both need a client secret: an ES256 JWT signed with the
//   Sign in with Apple key (SIWA_KEY_ID, SIWA_PRIVATE_KEY). Without that key they're skipped.
//
// No dependencies: Web Crypto verifies RS256 and signs ES256 in Workers and Node alike. Nothing here
// logs a token, a code or a `sub`.

import type { Env } from "./env.ts";
import { fromBase64url, importP8, signES256 } from "./jwt.ts";

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_KEYS_URL = `${APPLE_ISSUER}/auth/keys`;
export const APPLE_TOKEN_URL = `${APPLE_ISSUER}/auth/token`;
export const APPLE_REVOKE_URL = `${APPLE_ISSUER}/auth/revoke`;

/** Apple's keys change rarely; a day's cache per isolate, refetched early for a key we haven't seen. */
export const KEYS_CACHE_SECONDS = 24 * 60 * 60;
/** At most one fetch of Apple's keys a minute, however many tokens name an unknown key. */
export const KEYS_MIN_REFETCH_SECONDS = 60;
/** Tolerance for our clock and Apple's disagreeing about `exp` and `iat`. */
export const CLOCK_SKEW_SECONDS = 60;
/** Identity tokens are about 1 KB; anything this long isn't one. */
const MAX_TOKEN_LENGTH = 8 * 1024;

/** The identity token isn't one we accept: the app gets 401 `apple_token_invalid`. */
export class AppleTokenError extends Error {
  override name = "AppleTokenError";
}

/** Apple's keys couldn't be fetched and none are cached: the app gets 502 `apple_unavailable`. */
export class AppleUnavailableError extends Error {
  override name = "AppleUnavailableError";
}

export interface AppleDependencies {
  fetch?: typeof fetch;
  /** Unix seconds. */
  now?: () => number;
}

/** Apple's public keys (https://appleid.apple.com/auth/keys) by `kid`, cached. */
export class AppleKeys {
  private readonly fetcher: typeof fetch;
  private readonly now: () => number;
  private keys = new Map<string, CryptoKey>();
  /** Last successful fetch, and last attempt, in Unix seconds. */
  private fetchedAt = Number.NEGATIVE_INFINITY;
  private attemptedAt = Number.NEGATIVE_INFINITY;
  private refreshing: Promise<void> | undefined;

  constructor(dependencies: AppleDependencies = {}) {
    const fetcher = dependencies.fetch ?? fetch;
    this.fetcher = (input, init) => fetcher(input, init);
    this.now = dependencies.now ?? (() => Date.now() / 1000);
  }

  /**
   * The key with this id, or undefined if Apple doesn't publish one. Fetches when the cache is a day
   * old, and once more for an unknown id (at most once a minute). Throws `AppleUnavailableError`
   * only when there are no keys at all to check against.
   */
  async find(kid: string): Promise<CryptoKey | undefined> {
    if (this.now() - this.fetchedAt >= KEYS_CACHE_SECONDS && this.mayFetch()) await this.refresh();
    if (!this.keys.has(kid) && this.mayFetch()) await this.refresh();
    if (this.fetchedAt === Number.NEGATIVE_INFINITY) throw new AppleUnavailableError("Couldn't fetch Apple's keys");
    return this.keys.get(kid);
  }

  /** A fetch in flight can always be joined; a new one waits a minute after the last. */
  private mayFetch(): boolean {
    return this.refreshing !== undefined || this.now() - this.attemptedAt >= KEYS_MIN_REFETCH_SECONDS;
  }

  /** Concurrent requests share one fetch. Failures keep whatever keys are cached. */
  private refresh(): Promise<void> {
    this.refreshing ??= this.load().finally(() => {
      this.refreshing = undefined;
    });
    return this.refreshing;
  }

  private async load(): Promise<void> {
    this.attemptedAt = this.now();
    try {
      const response = await this.fetcher(APPLE_KEYS_URL, { headers: { accept: "application/json" } });
      if (!response.ok) throw new Error(`status ${response.status}`);
      const body = (await response.json()) as { keys?: unknown };
      if (!Array.isArray(body.keys)) throw new Error("no keys");
      const keys = new Map<string, CryptoKey>();
      for (const jwk of body.keys as Array<Record<string, unknown>>) {
        if (jwk?.kty !== "RSA" || typeof jwk.kid !== "string" || typeof jwk.n !== "string" || typeof jwk.e !== "string") continue;
        if (jwk.alg !== undefined && jwk.alg !== "RS256") continue;
        try {
          keys.set(
            jwk.kid,
            await crypto.subtle.importKey("jwk", { kty: "RSA", n: jwk.n, e: jwk.e }, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, [
              "verify",
            ]),
          );
        } catch {
          // A key Web Crypto can't read can't have signed anything we'd accept.
        }
      }
      if (keys.size === 0) throw new Error("no usable keys");
      this.keys = keys;
      this.fetchedAt = this.attemptedAt;
    } catch (error) {
      console.error(`apple: couldn't fetch Apple's keys (${error instanceof Error ? error.message : "unknown error"})`);
    }
  }
}

// One cache per isolate. Tests inject `fetch` or a clock and get a fresh one each time.
let sharedKeys: AppleKeys | undefined;

export function appleKeys(dependencies: AppleDependencies): AppleKeys {
  if (dependencies.fetch !== undefined || dependencies.now !== undefined) return new AppleKeys(dependencies);
  sharedKeys ??= new AppleKeys();
  return sharedKeys;
}

export interface IdentityClaims {
  /** Apple's stable id for this user and our team. */
  sub: string;
}

export interface VerifyOptions {
  /** The app's bundle ID: the `aud` Apple puts in tokens for a native app. */
  audience: string;
  keys: AppleKeys;
  /** Unix seconds. */
  now: number;
}

const decoder = new TextDecoder();

function decodePart(part: string, what: string): Record<string, unknown> {
  try {
    const value = JSON.parse(decoder.decode(fromBase64url(part))) as unknown;
    if (typeof value === "object" && value !== null && !Array.isArray(value)) return value as Record<string, unknown>;
  } catch {
    // Reported below.
  }
  throw new AppleTokenError(`The token's ${what} isn't base64url JSON`);
}

/**
 * Verifies a Sign in with Apple identity token: RS256 with one of Apple's keys, issuer
 * https://appleid.apple.com, audience the bundle ID, not expired, with a `sub`. The email and
 * everything else in it is ignored. Throws `AppleTokenError` (or `AppleUnavailableError`).
 */
export async function verifyIdentityToken(token: string, options: VerifyOptions): Promise<IdentityClaims> {
  if (token.length === 0 || token.length > MAX_TOKEN_LENGTH) throw new AppleTokenError("Not an identity token");
  const parts = token.split(".");
  if (parts.length !== 3) throw new AppleTokenError("Not a JWT");
  const [headerPart = "", claimsPart = "", signaturePart = ""] = parts;

  const header = decodePart(headerPart, "header");
  if (header.alg !== "RS256") throw new AppleTokenError("The token isn't RS256");
  if (typeof header.kid !== "string" || header.kid.length === 0) throw new AppleTokenError("The token names no key");

  const key = await options.keys.find(header.kid);
  if (key === undefined) throw new AppleTokenError("The token is signed with a key Apple doesn't publish");
  let signature: Uint8Array<ArrayBuffer>;
  try {
    signature = fromBase64url(signaturePart);
  } catch {
    throw new AppleTokenError("The token's signature isn't base64url");
  }
  const signed = new TextEncoder().encode(`${headerPart}.${claimsPart}`);
  if (!(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signed))) {
    throw new AppleTokenError("The token's signature doesn't verify");
  }

  const claims = decodePart(claimsPart, "claims");
  if (claims.iss !== APPLE_ISSUER) throw new AppleTokenError("The token isn't from Apple");
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(options.audience)) throw new AppleTokenError("The token is for another app");
  if (typeof claims.exp !== "number" || claims.exp + CLOCK_SKEW_SECONDS <= options.now) throw new AppleTokenError("The token has expired");
  if (claims.iat !== undefined && (typeof claims.iat !== "number" || claims.iat - CLOCK_SKEW_SECONDS > options.now)) {
    throw new AppleTokenError("The token was issued in the future");
  }
  if (typeof claims.sub !== "string" || claims.sub.length === 0 || claims.sub.length > 255) throw new AppleTokenError("The token has no subject");
  return { sub: claims.sub };
}

// The Sign in with Apple key: token exchange and revocation.

export interface SiwaConfig {
  teamId: string;
  keyId: string;
  /** The contents of the Sign in with Apple .p8 file. */
  privateKey: string;
  /** The bundle ID: Sign in with Apple's client ID for a native app. */
  clientId: string;
}

let warnedUnconfigured = false;

/**
 * The Sign in with Apple key's settings, or undefined (logged once per isolate) when SIWA_KEY_ID
 * or SIWA_PRIVATE_KEY isn't set: sign-in still works, but deletion can't revoke Apple's token.
 */
export function siwaConfig(env: Env): SiwaConfig | undefined {
  const config = {
    teamId: env.APNS_TEAM_ID?.trim() ?? "",
    keyId: env.SIWA_KEY_ID?.trim() ?? "",
    privateKey: env.SIWA_PRIVATE_KEY ?? "",
    clientId: env.APNS_BUNDLE_ID?.trim() ?? "",
  };
  if (config.keyId && config.privateKey.trim() && config.teamId && config.clientId) return config;
  if (!warnedUnconfigured) {
    warnedUnconfigured = true;
    const missing = [
      config.keyId ? undefined : "SIWA_KEY_ID",
      config.privateKey.trim() ? undefined : "SIWA_PRIVATE_KEY",
      config.teamId ? undefined : "APNS_TEAM_ID",
      config.clientId ? undefined : "APNS_BUNDLE_ID",
    ].filter((name) => name !== undefined);
    console.warn(`apple: ${missing.join(", ")} not set, so Apple tokens aren't exchanged or revoked (server/README.md)`);
  }
  return undefined;
}

/** The client secret Apple's token and revoke endpoints take: an ES256 JWT, valid 5 minutes. */
export async function clientSecret(config: SiwaConfig, now: number): Promise<string> {
  const issuedAt = Math.floor(now);
  return signES256(
    { kid: config.keyId, typ: "JWT" },
    { iss: config.teamId, iat: issuedAt, exp: issuedAt + 300, aud: APPLE_ISSUER, sub: config.clientId },
    await importP8(config.privateKey),
  );
}

/** Apple refused or couldn't be reached. The message has a status and Apple's error code only. */
export class AppleRequestError extends Error {
  override name = "AppleRequestError";
}

async function postForm(url: string, form: Record<string, string>, dependencies: AppleDependencies): Promise<Response> {
  const fetcher = dependencies.fetch ?? fetch;
  let response: Response;
  try {
    response = await fetcher(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: new URLSearchParams(form).toString(),
    });
  } catch (error) {
    throw new AppleRequestError(`couldn't reach Apple (${error instanceof Error ? error.name : "unknown error"})`);
  }
  if (response.ok) return response;
  let reason = "";
  try {
    const body = (await response.json()) as { error?: unknown };
    // Apple's error is a fixed code like "invalid_grant"; anything else isn't repeated.
    if (typeof body.error === "string" && /^[a-z_]{1,40}$/.test(body.error)) reason = ` ${body.error}`;
  } catch {
    // No JSON: the status will do.
  }
  throw new AppleRequestError(`Apple said ${response.status}${reason}`);
}

export interface ExchangeResult {
  refreshToken: string;
  /** The `sub` in the id_token Apple returned with it, when there was one. */
  sub?: string;
}

/** Swaps the app's one-time authorisation code for a refresh token. */
export async function exchangeAuthorizationCode(config: SiwaConfig, code: string, dependencies: AppleDependencies = {}): Promise<ExchangeResult> {
  const now = (dependencies.now ?? (() => Date.now() / 1000))();
  const response = await postForm(
    APPLE_TOKEN_URL,
    { client_id: config.clientId, client_secret: await clientSecret(config, now), code, grant_type: "authorization_code" },
    dependencies,
  );
  let body: { refresh_token?: unknown; id_token?: unknown };
  try {
    body = (await response.json()) as typeof body;
  } catch {
    throw new AppleRequestError("Apple's answer isn't JSON");
  }
  if (typeof body.refresh_token !== "string" || body.refresh_token.length === 0) throw new AppleRequestError("Apple sent no refresh token");
  const result: ExchangeResult = { refreshToken: body.refresh_token };
  // Straight from Apple over TLS, so its claims can be read without checking the signature.
  if (typeof body.id_token === "string") {
    try {
      const sub = decodePart(body.id_token.split(".")[1] ?? "", "claims").sub;
      if (typeof sub === "string") result.sub = sub;
    } catch {
      // No sub to compare: the caller keeps the token.
    }
  }
  return result;
}

/** Revokes a refresh token, which ends the app's authorisation for that Apple ID. */
export async function revokeRefreshToken(config: SiwaConfig, refreshToken: string, dependencies: AppleDependencies = {}): Promise<void> {
  const now = (dependencies.now ?? (() => Date.now() / 1000))();
  await postForm(
    APPLE_REVOKE_URL,
    { client_id: config.clientId, client_secret: await clientSecret(config, now), token: refreshToken, token_type_hint: "refresh_token" },
    dependencies,
  );
}
