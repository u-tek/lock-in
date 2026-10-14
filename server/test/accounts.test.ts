// Accounts routes through the whole Worker: a real (in-memory) D1 and a fake Apple.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { APPLE_KEYS_URL, APPLE_REVOKE_URL, APPLE_TOKEN_URL } from "../src/appleAuth.ts";
import { TOUCH_INTERVAL_SECONDS, hashToken } from "../src/auth.ts";
import { Database } from "../src/db.ts";
import { DEVICE_TOKEN } from "./helpers.ts";
import { FakeApple, T0, type TestApp, read, testApp } from "./app.ts";

let app: TestApp;
let logs: string[];

beforeEach(async () => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  app = await testApp();
});

afterEach(() => {
  vi.restoreAllMocks();
  // Logs say what happened, never who.
  for (const line of logs) {
    expect(line).not.toMatch(/sub\.|refresh\.|code\.|Bearer|PRIVATE KEY/);
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toContain(DEVICE_TOKEN);
    for (const handle of ["ava", "noor", "Ava", "Noor"]) expect(line).not.toMatch(new RegExp(`\\b${handle}\\b`));
  }
});

const signInBody = async (sub: string, extra: Record<string, unknown> = {}) => ({ identityToken: await app.identityToken(sub), ...extra });

describe("POST /auth/apple", () => {
  test("creates an account on the first sign-in", async () => {
    const { status, body } = await read(await app.request("POST", "/auth/apple", { body: await signInBody("sub.ava") }));
    expect(status).toBe(200);
    expect(body.isNew).toBe(true);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.user).toEqual({
      id: expect.stringMatching(/^[0-9A-Za-z]{10}$/),
      handle: null,
      displayName: null,
      avatarCode: "b0.c0.e0.h0",
      coins: 0,
      plusUntil: null,
      createdAt: T0,
    });
    expect(Object.keys(body).sort()).toEqual(["isNew", "token", "user"]);

    // Only the token's SHA-256 is stored.
    expect(app.value("SELECT token_hash FROM auth_tokens")).toBe(await hashToken(body.token));
    expect(app.count("SELECT count(*) FROM auth_tokens WHERE token_hash = ?", body.token)).toBe(0);
    expect(app.value("SELECT apple_sub FROM users")).toBe("sub.ava");
    expect(logs).toContain("auth/apple: new account");
  });

  test("signs the same Apple ID into the same account, with a new token each time", async () => {
    const first = await app.signIn("sub.ava");
    const second = await app.signIn("sub.ava");
    expect(second.isNew).toBe(false);
    expect(second.user.id).toBe(first.user.id);
    expect(second.token).not.toBe(first.token);
    expect(app.count("SELECT count(*) FROM users")).toBe(1);
    for (const token of [first.token, second.token]) expect((await app.request("GET", "/me", { token })).status).toBe(200);
  });

  test("takes the display name Apple shared, if it's allowed", async () => {
    expect((await app.signIn("sub.ava", { displayName: "  Ava " })).user.displayName).toBe("Ava");
    expect((await app.signIn("sub.noor", { displayName: "Hitler" })).user.displayName).toBeNull();
    expect((await app.signIn("sub.kai", { displayName: "Kaileywithaverylongname" })).user.displayName).toBeNull();
    expect((await app.signIn("sub.mila", { displayName: 42 as unknown as string })).user.displayName).toBeNull();
  });

  test("fills in a missing display name on a later sign-in, never replaces one", async () => {
    await app.signIn("sub.ava");
    expect((await app.signIn("sub.ava", { displayName: "Ava" })).user.displayName).toBe("Ava");
    expect((await app.signIn("sub.ava", { displayName: "Someone" })).user.displayName).toBe("Ava");
  });

  test("keeps Apple's refresh token for deletion, and never returns it", async () => {
    const response = await app.request("POST", "/auth/apple", { body: await signInBody("sub.ava", { authorizationCode: FakeApple.codeFor("sub.ava") }) });
    const text = await response.text();
    expect(response.status).toBe(200);
    expect(text).not.toContain("refresh.");
    expect(app.value("SELECT apple_refresh_token FROM users")).toBe("refresh.sub.ava.1");
    expect(app.apple.requestsTo(APPLE_TOKEN_URL)).toHaveLength(1);
  });

  test("signs in anyway when the code exchange fails, and logs why", async () => {
    const { status } = await read(await app.request("POST", "/auth/apple", { body: await signInBody("sub.ava", { authorizationCode: "expired" }) }));
    expect(status).toBe(200);
    expect(app.value("SELECT apple_refresh_token FROM users")).toBeNull();
    expect(logs).toContain("auth/apple: token exchange failed (Apple said 400 invalid_grant)");
  });

  test("doesn't keep a refresh token for another Apple ID", async () => {
    const { status } = await read(await app.request("POST", "/auth/apple", { body: await signInBody("sub.ava", { authorizationCode: FakeApple.codeFor("sub.noor") }) }));
    expect(status).toBe(200);
    expect(app.value("SELECT apple_refresh_token FROM users")).toBeNull();
  });

  test("without the Sign in with Apple key, skips the exchange", async () => {
    app = await testApp({ SIWA_KEY_ID: undefined, SIWA_PRIVATE_KEY: undefined });
    const { status } = await read(await app.request("POST", "/auth/apple", { body: await signInBody("sub.ava", { authorizationCode: FakeApple.codeFor("sub.ava") }) }));
    expect(status).toBe(200);
    expect(app.apple.requestsTo(APPLE_TOKEN_URL)).toHaveLength(0);
    expect(app.value("SELECT apple_refresh_token FROM users")).toBeNull();
  });

  test("401 apple_token_invalid for a token Apple didn't issue for this app", async () => {
    const bodies = [
      {},
      { identityToken: 42 },
      { identityToken: "" },
      { identityToken: "not.a.jwt" },
      { identityToken: await app.identityToken("sub.ava", { aud: "com.example.other" }) },
      { identityToken: await app.identityToken("sub.ava", { iss: "https://example.com" }) },
      { identityToken: await app.identityToken("sub.ava", { exp: T0 - 3600 }) },
      { identityToken: await app.identityToken("sub.ava", {}, app.keys.stranger) },
    ];
    for (const body of bodies) {
      const { status, body: answer } = await read(await app.request("POST", "/auth/apple", { body }));
      expect(status, JSON.stringify(body).slice(0, 80)).toBe(401);
      expect(answer).toEqual({ error: expect.any(String), code: "apple_token_invalid" });
    }
    expect(app.count("SELECT count(*) FROM users")).toBe(0);
  });

  test("502 apple_unavailable when Apple's keys can't be fetched", async () => {
    app.apple.keysResponse = "unreachable";
    const { status, body } = await read(await app.request("POST", "/auth/apple", { body: await signInBody("sub.ava") }));
    expect(status).toBe(502);
    expect(body.code).toBe("apple_unavailable");
    expect(app.apple.requestsTo(APPLE_KEYS_URL)).toHaveLength(1);
  });

  test("400 for a body that isn't a JSON object, 413 for one over 16 KB", async () => {
    for (const body of ["nope", "[]", ""]) {
      const { status, body: answer } = await read(await app.request("POST", "/auth/apple", { body }));
      expect(status).toBe(400);
      expect(answer.code).toBe("bad_request");
    }
    const huge = await read(await app.request("POST", "/auth/apple", { body: { identityToken: "x".repeat(17 * 1024) } }));
    expect(huge).toEqual({ status: 413, body: { error: expect.any(String), code: "too_large" } });
  });
});

describe("the bearer token", () => {
  test("401 unauthorised without a valid one", async () => {
    const { token } = await app.signIn("sub.ava");
    const headers = [undefined, "", "Basic abc", `Bearer ${token.slice(1)}`, `Bearer ${token}x`, `Bearer ${"A".repeat(43)}`, token];
    for (const authorization of headers) {
      const response = await app.request("GET", "/me", authorization === undefined ? {} : { headers: { authorization } });
      expect(await read(response), String(authorization)).toEqual({ status: 401, body: { error: expect.any(String), code: "unauthorised" } });
    }
    expect((await app.request("GET", "/me", { headers: { authorization: `bearer  ${token}` } })).status).toBe(200);
  });

  test("records when it was last used, at most hourly", async () => {
    const { token } = await app.signIn("sub.ava");
    const lastUsed = () => app.value("SELECT last_used_at FROM auth_tokens");
    expect(lastUsed()).toBe(T0);

    app.clock.now = T0 + TOUCH_INTERVAL_SECONDS - 1;
    await app.request("GET", "/me", { token });
    expect(lastUsed()).toBe(T0);
    app.clock.now = T0 + TOUCH_INTERVAL_SECONDS;
    await app.request("GET", "/me", { token });
    expect(lastUsed()).toBe(T0 + TOUCH_INTERVAL_SECONDS);
    expect(app.d1.statements.filter((sql) => sql.startsWith("UPDATE auth_tokens"))).toHaveLength(1);
  });
});

describe("GET /me", () => {
  test("returns the account", async () => {
    const ava = await app.user("ava", "Ava");
    expect(await read(await app.request("GET", "/me", { token: ava.token }))).toEqual({ status: 200, body: { user: ava.user } });
    expect(ava.user).toMatchObject({ handle: "ava", displayName: "Ava" });
  });
});

describe("PATCH /me", () => {
  let token: string;

  beforeEach(async () => {
    ({ token } = await app.signIn("sub.ava"));
  });

  const patch = async (body: unknown) => read(await app.request("PATCH", "/me", { token, body }));

  test("sets the handle (lowercased), the name (trimmed) and the avatar", async () => {
    // The parts are hers (M5): three bought, and Plus for the purple.
    const id = app.value("SELECT id FROM users") as string;
    for (const item of ["body.3", "eyes.2", "hat.4"]) app.sqlite.prepare("INSERT INTO cosmetics (user_id, item_id, acquired_at) VALUES (?, ?, 1)").run(id, item);
    app.sqlite.prepare("UPDATE users SET plus_until = ?").run(app.clock.now + 86_400);
    const { status, body } = await patch({ handle: "Ava_Smith", displayName: "  Ava  ", avatarCode: "b3.c7.e2.h4" });
    expect(status).toBe(200);
    expect(body.user).toMatchObject({ handle: "ava_smith", displayName: "Ava", avatarCode: "b3.c7.e2.h4" });
    expect(app.value("SELECT handle FROM users")).toBe("ava_smith");

    // Each on its own leaves the others alone; an empty patch changes nothing.
    expect((await patch({ displayName: "Avery" })).body.user).toMatchObject({ handle: "ava_smith", displayName: "Avery", avatarCode: "b3.c7.e2.h4" });
    expect((await patch({})).body.user).toMatchObject({ handle: "ava_smith", displayName: "Avery" });
    // Saving your own handle again, in any case, is fine.
    expect((await patch({ handle: "AVA_SMITH" })).status).toBe(200);
  });

  test.each([
    [{ handle: "ab" }, 422, "handle_invalid"],
    [{ handle: "1ava" }, 422, "handle_invalid"],
    [{ handle: "ava smith" }, 422, "handle_invalid"],
    [{ handle: 42 }, 422, "handle_invalid"],
    [{ handle: null }, 422, "handle_invalid"],
    [{ handle: "admin" }, 422, "handle_not_allowed"],
    [{ handle: "sh1t_happens" }, 422, "handle_not_allowed"],
    [{ displayName: "" }, 422, "name_invalid"],
    [{ displayName: "   " }, 422, "name_invalid"],
    [{ displayName: "Abcdefghijklm" }, 422, "name_invalid"],
    [{ displayName: "Nina\u0007" }, 422, "name_invalid"],
    [{ displayName: 7 }, 422, "name_invalid"],
    [{ displayName: "Sh!t" }, 422, "name_not_allowed"],
    [{ displayName: "Big Ass" }, 422, "name_not_allowed"],
    [{ avatarCode: "b1.c2" }, 422, "avatar_invalid"],
    [{ avatarCode: "B3.C7.E2.H4" }, 422, "avatar_invalid"],
    [{ avatarCode: "b100.c0.e0.h0" }, 422, "avatar_invalid"],
    [{ avatarCode: 3 }, 422, "avatar_invalid"],
    ["[]", 400, "bad_request"],
  ])("%j is %i %s", async (body, status, code) => {
    expect(await patch(body)).toEqual({ status, body: { error: expect.any(String), code } });
  });

  test("an invalid field means nothing is saved", async () => {
    expect((await patch({ handle: "ava", displayName: "Ava", avatarCode: "nope" })).body.code).toBe("avatar_invalid");
    expect(app.value("SELECT handle FROM users")).toBeNull();
  });

  test("409 handle_taken when someone else has it, ignoring case", async () => {
    await app.user("noor");
    expect(await patch({ handle: "NOOR" })).toEqual({ status: 409, body: { error: expect.any(String), code: "handle_taken" } });
  });

  test("409 handle_taken when someone takes it between the check and the save", async () => {
    await app.user("noor");
    vi.spyOn(Database.prototype, "handleOwner").mockResolvedValue(null);
    expect((await patch({ handle: "noor" })).body.code).toBe("handle_taken");
  });
});

describe("GET /handles/:handle", () => {
  test("says whether a handle is free, and why not", async () => {
    const ava = await app.user("ava");
    await app.user("noor");
    const check = async (handle: string) => (await read(await app.request("GET", `/handles/${handle}`, { token: ava.token }))).body;

    expect(await check("kai_99")).toEqual({ available: true });
    expect(await check("Kai.99")).toEqual({ available: true });
    expect(await check("noor")).toEqual({ available: false, reason: "taken" });
    expect(await check("NOOR")).toEqual({ available: false, reason: "taken" });
    expect(await check("ava")).toEqual({ available: true }); // your own
    expect(await check("ab")).toEqual({ available: false, reason: "invalid" });
    expect(await check("ava%20smith")).toEqual({ available: false, reason: "invalid" });
    expect(await check("%E0%A4%A")).toEqual({ available: false, reason: "invalid" });
    expect(await check("lockin_official")).toEqual({ available: false, reason: "not_allowed" });
  });
});

describe("DELETE /auth/session", () => {
  test("signs this token out and leaves the account's other sessions alone", async () => {
    const phone = await app.signIn("sub.ava");
    const ipad = await app.signIn("sub.ava");
    expect((await app.request("DELETE", "/auth/session", { token: phone.token })).status).toBe(204);
    expect((await app.request("GET", "/me", { token: phone.token })).status).toBe(401);
    expect((await app.request("DELETE", "/auth/session", { token: phone.token })).status).toBe(401);
    expect((await app.request("GET", "/me", { token: ipad.token })).status).toBe(200);
    expect(app.count("SELECT count(*) FROM auth_tokens")).toBe(1);
    expect(app.count("SELECT count(*) FROM users")).toBe(1);
    expect(logs).toContain("auth: signed out");
  });
});

describe("DELETE /me", () => {
  async function everything() {
    const ava = await app.signIn("sub.ava", { authorizationCode: FakeApple.codeFor("sub.ava") });
    await app.request("PATCH", "/me", { token: ava.token, body: { handle: "ava" } });
    const noor = await app.user("noor");
    const kai = await app.user("kai");
    const mila = await app.user("mila");

    // Ava: friends with Noor (both directions), blocks Kai, is blocked by Mila, has a friend code,
    // a device, reported Kai, and was reported by Noor.
    const code = (await read(await app.request("POST", "/friends/code", { token: ava.token }))).body.code;
    await app.request("POST", `/friends/redeem/${code}`, { token: noor.token });
    await app.request("POST", "/blocks", { token: ava.token, body: { userId: kai.user.id } });
    await app.request("POST", "/blocks", { token: mila.token, body: { userId: ava.user.id } });
    await app.request("POST", "/devices", { token: ava.token, body: { apnsToken: DEVICE_TOKEN, env: "production", laEnabled: true, frequentPushes: false, tz: "UTC" } });
    await app.request("POST", "/reports", { token: ava.token, body: { userId: kai.user.id, reason: "spam" } });
    await app.request("POST", "/reports", { token: noor.token, body: { userId: ava.user.id, reason: "name" } });
    return { ava, noor, kai, mila };
  }

  test("deletes everything that's only theirs, anonymises their reports and revokes Apple's token", async () => {
    const { ava, noor, kai } = await everything();
    expect(app.count("SELECT count(*) FROM friendships")).toBe(2);
    expect(app.count("SELECT count(*) FROM reports")).toBe(2);

    expect((await app.request("DELETE", "/me", { token: ava.token })).status).toBe(204);

    const id = ava.user.id;
    expect(app.count("SELECT count(*) FROM users WHERE id = ?", id)).toBe(0);
    expect(app.count("SELECT count(*) FROM auth_tokens WHERE user_id = ?", id)).toBe(0);
    expect(app.count("SELECT count(*) FROM friendships WHERE user_id = ? OR friend_id = ?", id, id)).toBe(0);
    expect(app.count("SELECT count(*) FROM blocks WHERE user_id = ? OR blocked_id = ?", id, id)).toBe(0);
    expect(app.count("SELECT count(*) FROM invite_codes WHERE created_by = ? OR target_id = ?", id, id)).toBe(0);
    expect(app.count("SELECT count(*) FROM devices")).toBe(0);
    // Their report on Kai stays, without them; Noor's report about them goes with them.
    expect(app.sqlite.prepare("SELECT reporter_id, target_user_id, reason FROM reports").all().map((row) => ({ ...row }))).toEqual([
      { reporter_id: null, target_user_id: kai.user.id, reason: "spam" },
    ]);
    // Everyone else is untouched.
    expect(app.count("SELECT count(*) FROM users")).toBe(3);
    expect((await app.request("GET", "/me", { token: noor.token })).status).toBe(200);

    const [revoke] = app.apple.requestsTo(APPLE_REVOKE_URL);
    expect(new URLSearchParams(revoke?.body).get("token")).toBe("refresh.sub.ava.1");
    expect(logs).toContain("me: account deleted, Apple token revoked");

    // The token is gone with the account.
    expect((await read(await app.request("GET", "/me", { token: ava.token }))).body.code).toBe("unauthorised");
    expect((await app.request("DELETE", "/me", { token: ava.token })).status).toBe(401);

    // The same Apple ID can start again from nothing.
    const again = await app.signIn("sub.ava");
    expect(again.isNew).toBe(true);
    expect(again.user.id).not.toBe(id);
  });

  test("with no Apple token stored there's nothing to revoke", async () => {
    const { token } = await app.signIn("sub.ava");
    expect((await app.request("DELETE", "/me", { token })).status).toBe(204);
    expect(app.apple.requestsTo(APPLE_REVOKE_URL)).toHaveLength(0);
    expect(logs).toContain("me: account deleted, no Apple token to revoke");
  });

  test("deletes the account even when Apple refuses the revocation", async () => {
    const { token } = await app.signIn("sub.ava", { authorizationCode: FakeApple.codeFor("sub.ava") });
    app.apple.revokeResponse = { status: 400, body: { error: "invalid_request" } };
    expect((await app.request("DELETE", "/me", { token })).status).toBe(204);
    expect(app.count("SELECT count(*) FROM users")).toBe(0);
    expect(logs).toContain("me: account deleted, Apple token not revoked (Apple said 400 invalid_request)");
  });

  test("without the Sign in with Apple key, deletes and says the token wasn't revoked", async () => {
    const { token } = await app.signIn("sub.ava", { authorizationCode: FakeApple.codeFor("sub.ava") });
    app.env.SIWA_PRIVATE_KEY = undefined;
    expect((await app.request("DELETE", "/me", { token })).status).toBe(204);
    expect(app.apple.requestsTo(APPLE_REVOKE_URL)).toHaveLength(0);
    expect(logs).toContain("me: account deleted, Apple token not revoked: no Sign in with Apple key");
  });
});

describe("POST /devices", () => {
  let token: string;
  const device = { apnsToken: DEVICE_TOKEN.toUpperCase(), env: "production", laEnabled: true, frequentPushes: false, tz: "Australia/Sydney" };
  const rows = () => app.sqlite.prepare("SELECT * FROM devices").all().map((row) => ({ ...row }));

  beforeEach(async () => {
    ({ token } = await app.signIn("sub.ava"));
  });

  test("registers the phone", async () => {
    expect((await app.request("POST", "/devices", { token, body: device })).status).toBe(204);
    const userId = app.value("SELECT id FROM users");
    expect(rows()).toEqual([
      {
        id: expect.stringMatching(/^[0-9A-Za-z]{10}$/),
        user_id: userId,
        apns_token: DEVICE_TOKEN,
        apns_env: "production",
        push_to_start_token: null,
        la_enabled: 1,
        frequent_pushes: 0,
        tz: "Australia/Sydney",
        // M4: quiet hours 22:00–07:00 unless the app says otherwise.
        quiet_start: 1320,
        quiet_end: 420,
        updated_at: T0,
      },
    ]);
  });

  test("updates the same token in place, and moves it to whoever signs in on that phone", async () => {
    await app.request("POST", "/devices", { token, body: device });
    app.clock.now = T0 + 60;
    const pushToStart = "ab".repeat(40);
    const update = { ...device, env: "sandbox", laEnabled: false, frequentPushes: true, tz: "Etc/GMT+10", pushToStartToken: pushToStart };
    expect((await app.request("POST", "/devices", { token, body: update })).status).toBe(204);
    expect(rows()).toEqual([
      expect.objectContaining({ apns_env: "sandbox", la_enabled: 0, frequent_pushes: 1, tz: "Etc/GMT+10", push_to_start_token: pushToStart, updated_at: T0 + 60 }),
    ]);

    const noor = await app.signIn("sub.noor");
    expect((await app.request("POST", "/devices", { token: noor.token, body: { ...device, pushToStartToken: null } })).status).toBe(204);
    expect(rows()).toEqual([expect.objectContaining({ user_id: noor.user.id, push_to_start_token: null })]);
  });

  test("quiet hours: 22:00–07:00 for a new phone, kept when left out, set, or turned off", async () => {
    const quiet = () => app.sqlite.prepare("SELECT quiet_start, quiet_end FROM devices").get() as Record<string, unknown>;
    await app.request("POST", "/devices", { token, body: device });
    expect({ ...quiet() }).toEqual({ quiet_start: 1320, quiet_end: 420 });

    expect((await app.request("POST", "/devices", { token, body: { ...device, quietHours: { start: 23 * 60 + 30, end: 6 * 60 } } })).status).toBe(204);
    expect({ ...quiet() }).toEqual({ quiet_start: 1410, quiet_end: 360 });
    // Left out: kept, while everything else updates.
    expect((await app.request("POST", "/devices", { token, body: { ...device, tz: "Europe/London" } })).status).toBe(204);
    expect(rows()).toEqual([expect.objectContaining({ tz: "Europe/London", quiet_start: 1410, quiet_end: 360 })]);
    // Same-day hours and the edges of the day are fine.
    expect((await app.request("POST", "/devices", { token, body: { ...device, quietHours: { start: 0, end: 1439 } } })).status).toBe(204);
    expect({ ...quiet() }).toEqual({ quiet_start: 0, quiet_end: 1439 });
    // null is off, and stays off when left out.
    expect((await app.request("POST", "/devices", { token, body: { ...device, quietHours: null } })).status).toBe(204);
    expect({ ...quiet() }).toEqual({ quiet_start: null, quiet_end: null });
    await app.request("POST", "/devices", { token, body: device });
    expect({ ...quiet() }).toEqual({ quiet_start: null, quiet_end: null });

    // A phone new to the server with them set gets what it sent.
    const noor = await app.signIn("sub.noor");
    const other = { ...device, apnsToken: "ab".repeat(32), quietHours: { start: 60, end: 120 } };
    expect((await app.request("POST", "/devices", { token: noor.token, body: other })).status).toBe(204);
    expect(app.sqlite.prepare("SELECT quiet_start, quiet_end FROM devices WHERE user_id = ?").get(noor.user.id)).toEqual({ quiet_start: 60, quiet_end: 120 });
  });

  test.each([
    { quietHours: { start: 1320 } },
    { quietHours: { start: 1320, end: 1320 } },
    { quietHours: { start: -1, end: 420 } },
    { quietHours: { start: 1320, end: 1440 } },
    { quietHours: { start: 1320.5, end: 420 } },
    { quietHours: { start: "1320", end: 420 } },
    { quietHours: [1320, 420] },
    { quietHours: "22:00-07:00" },
    { quietHours: false },
    { apnsToken: "not-hex" },
    { apnsToken: "abc" },
    { apnsToken: undefined },
    { env: "development" },
    { pushToStartToken: "zz" },
    { pushToStartToken: 5 },
    { laEnabled: "yes" },
    { frequentPushes: undefined },
    { tz: "x".repeat(65) },
    { tz: "Not a zone!" },
    { tz: "../etc/passwd" },
    { tz: "" },
    { tz: 10 },
  ])("422 device_invalid for %j", async (change) => {
    expect(await read(await app.request("POST", "/devices", { token, body: { ...device, ...change } }))).toEqual({
      status: 422,
      body: { error: expect.any(String), code: "device_invalid" },
    });
    expect(rows()).toHaveLength(0);
  });
});
