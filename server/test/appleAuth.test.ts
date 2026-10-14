// Sign in with Apple against a fake Apple: identity tokens signed with generated RSA keys, a fake
// JWKS endpoint, and fake token and revoke endpoints.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  APPLE_ISSUER,
  APPLE_KEYS_URL,
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  AppleKeys,
  AppleRequestError,
  AppleTokenError,
  AppleUnavailableError,
  CLOCK_SKEW_SECONDS,
  KEYS_CACHE_SECONDS,
  type SiwaConfig,
  clientSecret,
  exchangeAuthorizationCode,
  revokeRefreshToken,
  siwaConfig,
  verifyIdentityToken,
} from "../src/appleAuth.ts";
import type { Env } from "../src/env.ts";
import { base64url } from "../src/jwt.ts";
import { BUNDLE_ID, FakeApple, SIWA_KEY_ID, T0, TEAM_ID, signRS256, testKeys } from "./app.ts";
import { decodeJWT, verifyES256 } from "./helpers.ts";

let keys: Awaited<ReturnType<typeof testKeys>>;
let apple: FakeApple;
let clock: { now: number };
let appleKeys: AppleKeys;
let logs: string[];

beforeEach(async () => {
  keys = await testKeys();
  apple = new FakeApple([keys.current]);
  clock = { now: T0 };
  appleKeys = new AppleKeys({ fetch: apple.fetch, now: () => clock.now });
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
});

afterEach(() => {
  vi.restoreAllMocks();
  for (const line of logs) {
    expect(line).not.toContain("sub.");
    expect(line).not.toContain("refresh.");
    expect(line).not.toContain("PRIVATE KEY");
  }
});

const claims = (overrides: Record<string, unknown> = {}) => ({
  iss: APPLE_ISSUER,
  aud: BUNDLE_ID,
  exp: clock.now + 600,
  iat: clock.now,
  sub: "sub.ava",
  email: "ava@privaterelay.appleid.com",
  ...overrides,
});

const verify = (token: string) => verifyIdentityToken(token, { audience: BUNDLE_ID, keys: appleKeys, now: clock.now });

describe("verifyIdentityToken", () => {
  test("accepts a good token and returns its sub, ignoring the email", async () => {
    expect(await verify(await signRS256(keys.current, claims()))).toEqual({ sub: "sub.ava" });
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(1);
  });

  test("accepts an audience list that includes the bundle ID", async () => {
    expect(await verify(await signRS256(keys.current, claims({ aud: ["other.app", BUNDLE_ID] })))).toEqual({ sub: "sub.ava" });
  });

  test.each([
    ["the wrong audience", { aud: "com.example.someoneelse" }, /another app/],
    ["the wrong issuer", { iss: "https://appleid.example.com" }, /isn't from Apple/],
    ["an expired token", { exp: T0 - CLOCK_SKEW_SECONDS - 1 }, /expired/],
    ["no expiry", { exp: undefined }, /expired/],
    ["an iat in the future", { iat: T0 + CLOCK_SKEW_SECONDS + 5 }, /future/],
    ["no sub", { sub: undefined }, /subject/],
    ["an empty sub", { sub: "" }, /subject/],
  ])("refuses %s", async (_name, overrides, message) => {
    await expect(verify(await signRS256(keys.current, claims(overrides)))).rejects.toThrow(message);
    await expect(verify(await signRS256(keys.current, claims(overrides)))).rejects.toBeInstanceOf(AppleTokenError);
  });

  test("tolerates a minute of clock skew", async () => {
    expect(await verify(await signRS256(keys.current, claims({ exp: T0 - 30, iat: T0 - 630 })))).toEqual({ sub: "sub.ava" });
  });

  test("refuses a bad signature", async () => {
    // Same kid as Apple's key, different key.
    await expect(verify(await signRS256(keys.stranger, claims()))).rejects.toThrow(/signature doesn't verify/);
    // A valid token with its claims swapped for others.
    const [header, , signature] = (await signRS256(keys.current, claims())).split(".");
    const forged = `${header}.${base64url(JSON.stringify(claims({ sub: "sub.mallory" })))}.${signature}`;
    await expect(verify(forged)).rejects.toThrow(/signature doesn't verify/);
  });

  test("refuses other algorithms and things that aren't JWTs", async () => {
    const none = `${base64url(JSON.stringify({ alg: "none", kid: "apple-key-1" }))}.${base64url(JSON.stringify(claims()))}.`;
    await expect(verify(none)).rejects.toThrow(/RS256/);
    await expect(verify(await signRS256(keys.current, claims(), { alg: "HS256" }))).rejects.toThrow(/RS256/);
    await expect(verify(await signRS256(keys.current, claims(), { kid: undefined }))).rejects.toThrow(/names no key/);
    for (const junk of ["", "a.b", "a.b.c.d", "!!!.###.$$$", "x".repeat(9000)]) {
      await expect(verify(junk)).rejects.toBeInstanceOf(AppleTokenError);
    }
  });

  test("fetches Apple's keys again for an unknown kid, once, and finds a new key", async () => {
    await verify(await signRS256(keys.current, claims()));
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(1);

    // Apple rotates in a new key an hour later.
    clock.now += 3600;
    apple.published = [keys.current, keys.next];
    expect(await verify(await signRS256(keys.next, claims()))).toEqual({ sub: "sub.ava" });
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(2);

    // A kid Apple doesn't publish fails without a refetch storm: at most one fetch a minute.
    const unknown = { ...keys.stranger, kid: "apple-key-9" };
    await expect(verify(await signRS256(unknown, claims()))).rejects.toThrow(/key Apple doesn't publish/);
    await expect(verify(await signRS256(unknown, claims()))).rejects.toThrow(/key Apple doesn't publish/);
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(2);
    clock.now += 61;
    await expect(verify(await signRS256(unknown, claims()))).rejects.toThrow(/key Apple doesn't publish/);
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(3);
  });

  test("caches Apple's keys for a day", async () => {
    await verify(await signRS256(keys.current, claims()));
    clock.now = T0 + KEYS_CACHE_SECONDS - 1;
    await verify(await signRS256(keys.current, claims()));
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(1);
    clock.now = T0 + KEYS_CACHE_SECONDS;
    await verify(await signRS256(keys.current, claims()));
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(2);
  });

  test("concurrent verifications share one fetch", async () => {
    const token = await signRS256(keys.current, claims());
    await Promise.all([verify(token), verify(token), verify(token)]);
    expect(apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(1);
  });

  test("without Apple's keys it's unavailable, not invalid; with stale keys it carries on", async () => {
    apple.keysResponse = "unreachable";
    const token = await signRS256(keys.current, claims());
    await expect(verify(token)).rejects.toBeInstanceOf(AppleUnavailableError);
    expect(logs.join("\n")).toContain("couldn't fetch Apple's keys");

    apple.keysResponse = undefined;
    clock.now += 61;
    await verify(await signRS256(keys.current, claims()));

    // A day later Apple is down (or answers garbage): the cached keys still work.
    clock.now += KEYS_CACHE_SECONDS;
    apple.keysResponse = { status: 503 };
    expect(await verify(await signRS256(keys.current, claims()))).toEqual({ sub: "sub.ava" });
    apple.keysResponse = { status: 200, body: { keys: [{ kty: "EC", kid: "x" }] } };
    clock.now += 61;
    expect(await verify(await signRS256(keys.current, claims()))).toEqual({ sub: "sub.ava" });
  });
});

describe("the Sign in with Apple key", () => {
  const config = (): SiwaConfig => ({ teamId: TEAM_ID, keyId: SIWA_KEY_ID, privateKey: keys.siwa.pem, clientId: BUNDLE_ID });

  test("the client secret is an ES256 JWT with the claims Apple documents", async () => {
    const jwt = decodeJWT(await clientSecret(config(), T0 + 0.7));
    expect(jwt.header).toEqual({ alg: "ES256", kid: SIWA_KEY_ID, typ: "JWT" });
    expect(jwt.claims).toEqual({ iss: TEAM_ID, iat: T0, exp: T0 + 300, aud: "https://appleid.apple.com", sub: BUNDLE_ID });
    expect(await verifyES256(jwt, keys.siwa.publicKey)).toBe(true);
  });

  test("swaps an authorisation code for a refresh token", async () => {
    const result = await exchangeAuthorizationCode(config(), FakeApple.codeFor("sub.ava"), { fetch: apple.fetch, now: () => clock.now });
    expect(result).toEqual({ refreshToken: "refresh.sub.ava.1", sub: "sub.ava" });

    const [request] = apple.requestsTo(APPLE_TOKEN_URL);
    expect(request?.method).toBe("POST");
    expect(request?.headers["content-type"]).toBe("application/x-www-form-urlencoded");
    const form = new URLSearchParams(request?.body);
    expect(form.get("client_id")).toBe(BUNDLE_ID);
    expect(form.get("grant_type")).toBe("authorization_code");
    expect(form.get("code")).toBe("code.sub.ava");
    expect(await verifyES256(decodeJWT(form.get("client_secret") ?? ""), keys.siwa.publicKey)).toBe(true);
  });

  test("says why Apple refused, without repeating what was sent", async () => {
    const deps = { fetch: apple.fetch, now: () => clock.now };
    const refused = exchangeAuthorizationCode(config(), "not-a-code", deps);
    await expect(refused).rejects.toBeInstanceOf(AppleRequestError);
    await expect(exchangeAuthorizationCode(config(), "not-a-code", deps)).rejects.toThrow(/^Apple said 400 invalid_grant$/);

    apple.tokenResponse = { status: 200, body: { access_token: "a" } };
    await expect(exchangeAuthorizationCode(config(), "code.sub.ava", deps)).rejects.toThrow(/no refresh token/);

    apple.tokenResponse = { status: 400, body: { error: "secret code.sub.ava leaked" } };
    await expect(exchangeAuthorizationCode(config(), "code.sub.ava", deps)).rejects.toThrow(/^Apple said 400$/);

    const unreachable = (async () => {
      throw new TypeError("connection reset by appleid.apple.com for code.sub.ava");
    }) as typeof fetch;
    await expect(exchangeAuthorizationCode(config(), "code.sub.ava", { fetch: unreachable })).rejects.toThrow(/^couldn't reach Apple \(TypeError\)$/);
  });

  test("revokes a refresh token", async () => {
    await revokeRefreshToken(config(), "refresh.sub.ava.1", { fetch: apple.fetch, now: () => clock.now });
    const [request] = apple.requestsTo(APPLE_REVOKE_URL);
    const form = new URLSearchParams(request?.body);
    expect(Object.fromEntries(form)).toMatchObject({ client_id: BUNDLE_ID, token: "refresh.sub.ava.1", token_type_hint: "refresh_token" });
    expect(await verifyES256(decodeJWT(form.get("client_secret") ?? ""), keys.siwa.publicKey)).toBe(true);

    apple.revokeResponse = { status: 400, body: { error: "invalid_client" } };
    await expect(revokeRefreshToken(config(), "refresh.sub.ava.1", { fetch: apple.fetch })).rejects.toThrow(/^Apple said 400 invalid_client$/);
  });

  test("is off without SIWA_KEY_ID and SIWA_PRIVATE_KEY, and says so once", () => {
    const env = { APNS_BUNDLE_ID: BUNDLE_ID, APNS_TEAM_ID: TEAM_ID } as Env;
    expect(siwaConfig(env)).toBeUndefined();
    expect(siwaConfig({ ...env, SIWA_KEY_ID: SIWA_KEY_ID, SIWA_PRIVATE_KEY: "  " })).toBeUndefined();
    expect(logs.filter((line) => line.includes("SIWA_KEY_ID, SIWA_PRIVATE_KEY not set"))).toHaveLength(1);
    expect(siwaConfig({ ...env, SIWA_KEY_ID: ` ${SIWA_KEY_ID}\n`, SIWA_PRIVATE_KEY: keys.siwa.pem })).toEqual(config());
  });
});
