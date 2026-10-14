// The Worker wired to a real (in-memory) D1, a fake Apple and a clock the test controls, for route
// tests: `const app = await testApp(); const { token } = await app.signIn("sub.ava");`.

import type { DatabaseSync } from "node:sqlite";
import { APPLE_ISSUER, APPLE_KEYS_URL, APPLE_REVOKE_URL, APPLE_TOKEN_URL } from "../src/appleAuth.ts";
import type { Dependencies } from "../src/context.ts";
import type { Env } from "../src/env.ts";
import { handle } from "../src/index.ts";
import { base64url } from "../src/jwt.ts";
import { TestD1 } from "./d1.ts";
import { type RecordedRequest, makeKey } from "./helpers.ts";

export const BUNDLE_ID = "com.example.lockin";
export const TEAM_ID = "TEAM123456";
export const SIWA_KEY_ID = "SIWAKEY123";
/** 2026-10-14, give or take. */
export const T0 = 1_792_000_000;

export interface RSAKey {
  kid: string;
  privateKey: CryptoKey;
  jwk: JsonWebKey & { kid: string };
}

export async function makeRSAKey(kid: string): Promise<RSAKey> {
  const pair = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const exported = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  // What https://appleid.apple.com/auth/keys publishes per key.
  const jwk = { kty: "RSA", kid, use: "sig", alg: "RS256", n: exported.n, e: exported.e };
  return { kid, privateKey: pair.privateKey, jwk };
}

/** Signs `claims` as RS256 with `key` (header kid = key.kid unless overridden). */
export async function signRS256(key: RSAKey, claims: Record<string, unknown>, header: Record<string, unknown> = {}): Promise<string> {
  const input = `${base64url(JSON.stringify({ kid: key.kid, alg: "RS256", ...header }))}.${base64url(JSON.stringify(claims))}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(input));
  return `${input}.${base64url(signature)}`;
}

// Key generation is slow-ish (RSA 2048); each test file makes its keys once.
let keysPromise: Promise<{ current: RSAKey; next: RSAKey; stranger: RSAKey; siwa: { pem: string; publicKey: CryptoKey } }> | undefined;

export function testKeys() {
  keysPromise ??= (async () => ({
    current: await makeRSAKey("apple-key-1"),
    next: await makeRSAKey("apple-key-2"),
    // Never published: a token signed with it must fail.
    stranger: await makeRSAKey("apple-key-1"),
    siwa: await makeKey(),
  }))();
  return keysPromise;
}

export interface FakeResponseSpec {
  status: number;
  body?: unknown;
}

/** Apple's keys, token and revoke endpoints. Records every request. */
export class FakeApple {
  readonly requests: RecordedRequest[] = [];
  /** The keys /auth/keys publishes. */
  published: RSAKey[];
  /** Overrides for the next answers, by endpoint. */
  keysResponse: FakeResponseSpec | "unreachable" | undefined;
  tokenResponse: FakeResponseSpec | undefined;
  revokeResponse: FakeResponseSpec | undefined;
  private refreshCount = 0;

  constructor(published: RSAKey[]) {
    this.published = published;
  }

  requestsTo(url: string): RecordedRequest[] {
    return this.requests.filter((request) => request.url === url);
  }

  /** An authorisation code the fake token endpoint swaps for a refresh token for `sub`. */
  static codeFor(sub: string): string {
    return `code.${sub}`;
  }

  readonly fetch = (async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = new Request(input, init);
    const headers: Record<string, string> = {};
    request.headers.forEach((value, key) => {
      headers[key] = value;
    });
    const body = await request.text();
    this.requests.push({ url: request.url, method: request.method, headers, body });
    const reply = (spec: FakeResponseSpec) =>
      new Response(spec.body === undefined ? null : JSON.stringify(spec.body), { status: spec.status, headers: { "content-type": "application/json" } });

    if (request.url === APPLE_KEYS_URL && request.method === "GET") {
      if (this.keysResponse === "unreachable") throw new TypeError("fetch failed");
      return reply(this.keysResponse ?? { status: 200, body: { keys: this.published.map((key) => key.jwk) } });
    }
    if (request.url === APPLE_TOKEN_URL && request.method === "POST") {
      if (this.tokenResponse !== undefined) return reply(this.tokenResponse);
      const form = new URLSearchParams(body);
      const code = form.get("code") ?? "";
      if (!code.startsWith("code.")) return reply({ status: 400, body: { error: "invalid_grant" } });
      const sub = code.slice("code.".length);
      this.refreshCount += 1;
      // Apple's id_token here is signed too, but the server only reads its sub.
      const idToken = `${base64url(JSON.stringify({ alg: "RS256", kid: "apple-key-1" }))}.${base64url(JSON.stringify({ iss: APPLE_ISSUER, sub }))}.sig`;
      return reply({
        status: 200,
        body: { access_token: "access", token_type: "Bearer", expires_in: 3600, refresh_token: `refresh.${sub}.${this.refreshCount}`, id_token: idToken },
      });
    }
    if (request.url === APPLE_REVOKE_URL && request.method === "POST") {
      return reply(this.revokeResponse ?? { status: 200 });
    }
    return new Response("not found", { status: 404 });
  }) as typeof fetch;
}

export interface RequestOptions {
  token?: string;
  body?: unknown;
  headers?: Record<string, string>;
}

export interface SignedIn {
  token: string;
  user: { id: string; handle: string | null; displayName: string | null; avatarCode: string; [key: string]: unknown };
  isNew: boolean;
}

export interface TestApp {
  env: Env;
  d1: TestD1;
  sqlite: DatabaseSync;
  apple: FakeApple;
  keys: Awaited<ReturnType<typeof testKeys>>;
  clock: { now: number };
  deps: Dependencies;
  request(method: string, path: string, options?: RequestOptions): Promise<Response>;
  /** An identity token for `sub`, signed with Apple's current key; claims can be overridden. */
  identityToken(sub: string, claims?: Record<string, unknown>, key?: RSAKey): Promise<string>;
  /** POST /auth/apple for `sub`; fails the test unless it's a 200. */
  signIn(sub: string, extra?: { displayName?: string; authorizationCode?: string }): Promise<SignedIn>;
  /** A signed-in user with a handle (and a display name, unless null). */
  user(handle: string, displayName?: string | null): Promise<SignedIn>;
  /** Every user id and session token handed out, so tests can check none reached a log. */
  issued: Set<string>;
  /** One value from D1. */
  value(sql: string, ...params: Array<string | number | null>): unknown;
  count(sql: string, ...params: Array<string | number | null>): number;
}

export async function testApp(overrides: Partial<Env> = {}): Promise<TestApp> {
  const keys = await testKeys();
  const d1 = new TestD1();
  const apple = new FakeApple([keys.current]);
  const clock = { now: T0 };
  const deps: Dependencies = { fetch: apple.fetch, now: () => clock.now };
  const env: Env = {
    DB: d1.binding,
    ROOMS: {} as DurableObjectNamespace,
    APNS_BUNDLE_ID: BUNDLE_ID,
    ENVIRONMENT: "development",
    APNS_TEAM_ID: TEAM_ID,
    SIWA_KEY_ID,
    SIWA_PRIVATE_KEY: keys.siwa.pem,
    ...overrides,
  };

  const issued = new Set<string>();
  const app: TestApp = {
    issued,
    env,
    d1,
    sqlite: d1.sqlite,
    apple,
    keys,
    clock,
    deps,
    request(method, path, options = {}) {
      const headers: Record<string, string> = { ...options.headers };
      if (options.token !== undefined) headers.authorization = `Bearer ${options.token}`;
      let body: string | undefined;
      if (options.body !== undefined) {
        headers["content-type"] ??= "application/json";
        body = typeof options.body === "string" ? options.body : JSON.stringify(options.body);
      }
      return handle(new Request(`https://lockin-api.example.workers.dev${path}`, { method, headers, body }), env, deps);
    },
    identityToken(sub, claims = {}, key = keys.current) {
      return signRS256(key, {
        iss: APPLE_ISSUER,
        aud: BUNDLE_ID,
        exp: clock.now + 600,
        iat: clock.now,
        sub,
        c_hash: "abc",
        email: "someone@privaterelay.appleid.com",
        email_verified: true,
        is_private_email: true,
        auth_time: clock.now,
        nonce_supported: true,
        ...claims,
      });
    },
    async signIn(sub, extra = {}) {
      const response = await app.request("POST", "/auth/apple", { body: { identityToken: await app.identityToken(sub), ...extra } });
      if (response.status !== 200) throw new Error(`sign-in answered ${response.status}: ${await response.text()}`);
      const signedIn = (await response.json()) as SignedIn;
      issued.add(signedIn.user.id).add(signedIn.token);
      return signedIn;
    },
    async user(handle, displayName = handle.charAt(0).toUpperCase() + handle.slice(1)) {
      const signedIn = await app.signIn(`sub.${handle}`);
      const body: Record<string, string> = { handle };
      if (displayName !== null) body.displayName = displayName;
      const response = await app.request("PATCH", "/me", { token: signedIn.token, body });
      if (response.status !== 200) throw new Error(`PATCH /me answered ${response.status}: ${await response.text()}`);
      return { ...signedIn, user: ((await response.json()) as { user: SignedIn["user"] }).user };
    },
    value(sql, ...params) {
      const row = d1.sqlite.prepare(sql).get(...params) as Record<string, unknown> | undefined;
      return row === undefined ? undefined : Object.values(row)[0];
    },
    count(sql, ...params) {
      return Number(app.value(sql, ...params));
    },
  };
  return app;
}

/** The JSON body and status, for one-line assertions. */
export async function read(response: Response): Promise<{ status: number; body: any }> {
  const text = await response.text();
  return { status: response.status, body: text.length > 0 ? JSON.parse(text) : undefined };
}
