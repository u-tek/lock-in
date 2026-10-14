// One APNs provider token for every isolate (docs/decisions/0004): the ApnsAuth Durable Object signs
// it and hands it out, and each room keeps a copy until 5 minutes before ApnsAuth replaces it.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { ApnsConfigError, PROVIDER_TOKEN_REFRESH_SECONDS } from "../src/apns.ts";
import { APNS_AUTH_NAME, ApnsAuth, SHARED_TOKEN_REUSE_SECONDS, SharedProviderToken } from "../src/apnsAuth.ts";
import type { Env } from "../src/env.ts";
import { APNS_KEY_ID, type SignedIn, T0, TEAM_ID, type TestApp, read, testApp } from "./app.ts";
import { decodeJWT, makeKey, verifyES256 } from "./helpers.ts";
import { FakeNamespace, laToken } from "./rooms.ts";

let logs: string[];

beforeEach(() => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
});

afterEach(() => {
  vi.restoreAllMocks();
  // The provider token (a JWT starts "eyJ") and the key never reach a log.
  for (const line of logs) expect(line).not.toMatch(/eyJ|PRIVATE KEY/);
});

async function setup(overrides: Partial<Env> = {}) {
  const key = await makeKey();
  const clock = { now: T0 };
  const env = { APNS_TEAM_ID: TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY: key.pem, ...overrides } as Env;
  const auth = new FakeNamespace<ApnsAuth>((state) => new ApnsAuth(state, env, { now: () => clock.now }));
  const stub = () => auth.get(auth.idFromName(APNS_AUTH_NAME));
  const get = async () => read(await stub().fetch("https://apns-auth/token"));
  const expire = async (token: string) =>
    read(await stub().fetch("https://apns-auth/token", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ expired: token }) }));
  return { key, clock, env, auth, get, expire };
}

describe("ApnsAuth", () => {
  test("hands out one ES256 provider token for 40 minutes, then signs a new one", async () => {
    const { key, clock, get } = await setup();
    const first = await get();
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ token: expect.any(String), issuedAt: T0 });
    const jwt = decodeJWT(first.body.token);
    expect(jwt.header).toEqual({ alg: "ES256", kid: APNS_KEY_ID });
    expect(jwt.claims).toEqual({ iss: TEAM_ID, iat: T0 });
    expect(await verifyES256(jwt, key.publicKey)).toBe(true);

    clock.now = T0 + PROVIDER_TOKEN_REFRESH_SECONDS - 1;
    expect((await get()).body).toEqual(first.body);
    clock.now = T0 + PROVIDER_TOKEN_REFRESH_SECONDS;
    const second = (await get()).body;
    expect(second.token).not.toBe(first.body.token);
    expect(second.issuedAt).toBe(T0 + PROVIDER_TOKEN_REFRESH_SECONDS);
    expect(logs.filter((line) => line === "apns-auth: signed a new provider token")).toHaveLength(2);
  });

  test("keeps the token across restarts instead of signing early", async () => {
    const { clock, auth, get } = await setup();
    const first = (await get()).body;
    auth.evict(APNS_AUTH_NAME);
    clock.now = T0 + 600;
    expect((await get()).body).toEqual(first);
    expect(logs.filter((line) => line.includes("signed a new provider token"))).toHaveLength(1);
  });

  test("a new key means a new token, whatever's stored", async () => {
    const { auth, env, get } = await setup();
    const first = (await get()).body;
    env.APNS_KEY_ID = "NEWKEY9999";
    env.APNS_PRIVATE_KEY = (await makeKey()).pem;
    auth.evict(APNS_AUTH_NAME);
    const second = (await get()).body;
    expect(second.token).not.toBe(first.token);
    expect(decodeJWT(second.token).header.kid).toBe("NEWKEY9999");
  });

  test("an expiry reported for the current token replaces it; for an older one it doesn't", async () => {
    const { clock, get, expire } = await setup();
    const first = (await get()).body;
    clock.now = T0 + 5;
    const second = await expire(first.token);
    expect(second.status).toBe(200);
    expect(second.body.token).not.toBe(first.token);
    expect(second.body.issuedAt).toBe(T0 + 5);
    // A room still holding the first token reports it too: it just gets the current one.
    expect((await expire(first.token)).body).toEqual(second.body);
    expect((await get()).body).toEqual(second.body);
  });

  test("500 apns_not_configured without the key, naming what's missing", async () => {
    const { get } = await setup({ APNS_KEY_ID: undefined, APNS_PRIVATE_KEY: " " });
    expect(await get()).toEqual({
      status: 500,
      body: { error: "APNs isn't set up: APNS_KEY_ID, APNS_PRIVATE_KEY missing (server/README.md)", code: "apns_not_configured" },
    });
  });

  test("anything else is refused", async () => {
    const { auth } = await setup();
    const stub = auth.get(auth.idFromName(APNS_AUTH_NAME));
    expect((await stub.fetch("https://apns-auth/other")).status).toBe(404);
    expect((await stub.fetch("https://apns-auth/token", { method: "POST", body: "{}" })).status).toBe(400);
  });
});

describe("SharedProviderToken", () => {
  test("keeps ApnsAuth's token until 5 minutes before it's replaced, then asks again", async () => {
    const { clock, auth } = await setup();
    const shared = new SharedProviderToken(auth.binding, () => clock.now);
    const first = await shared.token();
    expect(auth.calls).toHaveLength(1);

    clock.now = T0 + SHARED_TOKEN_REUSE_SECONDS - 1;
    expect(await shared.token()).toBe(first);
    expect(auth.calls).toHaveLength(1);

    // 35 minutes: asks, and still gets the same token, which ApnsAuth keeps for 40.
    clock.now = T0 + SHARED_TOKEN_REUSE_SECONDS;
    expect(await shared.token()).toBe(first);
    expect(auth.calls).toHaveLength(2);
    clock.now = T0 + PROVIDER_TOKEN_REFRESH_SECONDS;
    expect(await shared.token()).not.toBe(first);
    expect(SHARED_TOKEN_REUSE_SECONDS).toBe(35 * 60);
  });

  test("requests that arrive together ask once", async () => {
    const { clock, auth } = await setup();
    const shared = new SharedProviderToken(auth.binding, () => clock.now);
    const tokens = await Promise.all([shared.token(), shared.token(), shared.token()]);
    expect(new Set(tokens).size).toBe(1);
    expect(auth.calls).toHaveLength(1);
  });

  test("an unconfigured ApnsAuth is a set-up error", async () => {
    const { clock, auth } = await setup({ APNS_TEAM_ID: undefined });
    await expect(new SharedProviderToken(auth.binding, () => clock.now).token()).rejects.toThrow(ApnsConfigError);
  });
});

describe("rooms share the provider token", () => {
  let app: TestApp;
  let ava: SignedIn;
  let noor: SignedIn;

  beforeEach(async () => {
    app = await testApp();
    ava = await app.user("ava", "Ava");
    noor = await app.user("noor", "Noor");
  });

  /** A solo session for each, with a token, paused so a push is waiting. */
  async function twoRooms() {
    const sids: string[] = [];
    for (const [index, who] of [ava, noor].entries()) {
      const sid = (await read(await app.request("POST", "/sessions", { token: who.token, body: { minutes: 90 } }))).body.session.id as string;
      await app.request("POST", `/sessions/${sid}/la-token`, { token: who.token, body: { token: laToken(index + 1), env: "production" } });
      sids.push(sid);
    }
    return sids;
  }

  const pause = async (who: SignedIn, sid: string, action = "pause") => {
    expect((await app.request("POST", `/sessions/${sid}/${action}`, { token: who.token })).status).toBe(200);
  };

  test("two rooms present the same JWT, signed once by ApnsAuth", async () => {
    const [a = "", b = ""] = await twoRooms();
    await pause(ava, a);
    await pause(noor, b);
    await app.advance(2);
    expect(app.apns.requests).toHaveLength(2);
    const [first, second] = app.apns.requests;
    expect(first?.jwt).toBe(second?.jwt);
    // Signed when the first push needed it.
    expect(decodeJWT(first?.jwt ?? "").claims).toEqual({ iss: TEAM_ID, iat: T0 + 2 });
    expect([...app.apnsAuth.objects.keys()]).toEqual([APNS_AUTH_NAME]);

    // 30 minutes on, still the same; 40 minutes on, a new one, for both.
    await app.advance(30 * 60);
    await pause(ava, a, "resume");
    await app.advance(2);
    expect(app.apns.requests[2]?.jwt).toBe(first?.jwt);
    await app.advance(10 * 60);
    await pause(ava, a);
    await pause(noor, b, "resume");
    await app.advance(2);
    const [third, fourth] = app.apns.requests.slice(3);
    expect(third?.jwt).not.toBe(first?.jwt);
    expect(third?.jwt).toBe(fourth?.jwt);
  });

  test("a 429 TooManyProviderTokenUpdates never signs a new token", async () => {
    const [a = ""] = await twoRooms();
    app.apns.answers.set(laToken(1), { status: 429, reason: "TooManyProviderTokenUpdates" });
    await pause(ava, a);
    await app.advance(2);
    app.apns.answers.delete(laToken(1));
    await pause(ava, a, "resume");
    await app.advance(2);
    expect(app.apns.requests.map((request) => request.jwt)).toEqual([app.apns.requests[0]?.jwt, app.apns.requests[0]?.jwt]);
    expect(logs.filter((line) => line.includes("signed a new provider token"))).toHaveLength(1);
  });

  test("403 ExpiredProviderToken: one new token, which every room then uses", async () => {
    const [a = "", b = ""] = await twoRooms();
    await pause(ava, a);
    await pause(noor, b);
    await app.advance(2);
    const old = app.apns.requests[0]?.jwt ?? "";
    expect(app.apns.requests[1]?.jwt).toBe(old);
    app.apns.answersForJWT.set(old, { status: 403, reason: "ExpiredProviderToken" });

    await pause(ava, a, "resume");
    await app.advance(2);
    // Refused, reported, and sent again with a new token.
    const fresh = app.apns.requests[3]?.jwt;
    expect(app.apns.requests.slice(2).map((request) => request.jwt)).toEqual([old, fresh]);
    expect(fresh).not.toBe(old);
    expect(app.apns.requests[3]?.token).toBe(laToken(1));

    // Noor's room still had the old one: it's refused too, and picks up the same new token.
    await pause(noor, b, "resume");
    await app.advance(2);
    expect(app.apns.requests.slice(4).map((request) => request.jwt)).toEqual([old, fresh]);
    expect(logs.filter((line) => line.includes("signed a new provider token"))).toHaveLength(2);
  });
});
