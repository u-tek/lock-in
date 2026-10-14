// Friends, friend codes, blocks and reports through the whole Worker, on a real (in-memory) D1.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { FRIEND_CODE_ALPHABET, newFriendCode } from "../src/context.ts";
import { EXPIRED_CODE_RETENTION_SECONDS, FRIEND_CODE_LIFETIME_SECONDS } from "../src/friends.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";

let app: TestApp;
let ava: SignedIn;
let noor: SignedIn;
let logs: string[];

beforeEach(async () => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  app = await testApp();
  ava = await app.user("ava", "Ava");
  noor = await app.user("noor", "Noor");
});

afterEach(() => {
  vi.restoreAllMocks();
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toMatch(/\b(ava|noor|Ava|Noor)\b/);
  }
});

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));
const codeOf = async (who: SignedIn) => (await call(who, "POST", "/friends/code")).body.code as string;
/** A random source that hands out these bytes, in order, then real randomness. */
const scripted = (...chunks: number[][]) => (length: number) => {
  const next = chunks.shift();
  return next === undefined ? crypto.getRandomValues(new Uint8Array(length)) : Uint8Array.from(next.slice(0, length));
};

describe("POST /friends/code", () => {
  test("makes a week-long code with its link", async () => {
    const { status, body } = await call(ava, "POST", "/friends/code");
    expect(status).toBe(200);
    expect(body).toEqual({
      code: expect.stringMatching(new RegExp(`^[${FRIEND_CODE_ALPHABET}]{8}$`)),
      url: `https://lockin-api.example.workers.dev/j/${body.code}`,
      expiresAt: T0 + FRIEND_CODE_LIFETIME_SECONDS,
    });
    expect(FRIEND_CODE_LIFETIME_SECONDS).toBe(7 * 24 * 60 * 60);
    expect(app.sqlite.prepare("SELECT * FROM invite_codes").get()).toEqual({
      code: body.code,
      kind: "friend",
      target_id: ava.user.id,
      created_by: ava.user.id,
      expires_at: T0 + FRIEND_CODE_LIFETIME_SECONDS,
    });
  });

  test("uses only the 32-letter alphabet, every letter of it, without bias", async () => {
    const codes = [0, 8, 16, 24].map((start) => newFriendCode(() => Uint8Array.from({ length: 8 }, (_, i) => start + i)));
    expect(codes).toEqual(["ABCDEFGH", "JKLMNPQR", "STUVWXYZ", "23456789"]);
    for (const forbidden of "01OI") expect(FRIEND_CODE_ALPHABET).not.toContain(forbidden);
    // Each byte's low 5 bits pick the letter: all 256 byte values, exactly 8 per letter.
    const counts = new Map<string, number>();
    for (let byte = 0; byte < 256; byte++) {
      const letter = newFriendCode(() => new Uint8Array(8).fill(byte)).charAt(0);
      counts.set(letter, (counts.get(letter) ?? 0) + 1);
    }
    expect([...counts.keys()].sort().join("")).toBe([...FRIEND_CODE_ALPHABET].sort().join(""));
    for (const count of counts.values()) expect(count).toBe(8);
    // And through the route, with real randomness.
    for (let i = 0; i < 10; i++) {
      const user = await app.user(`user${i}`);
      expect(await codeOf(user)).toMatch(new RegExp(`^[${FRIEND_CODE_ALPHABET}]{8}$`));
    }
  });

  test("hands back the current code until it expires, then a new one", async () => {
    const first = (await call(ava, "POST", "/friends/code")).body;
    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS - 1;
    expect((await call(ava, "POST", "/friends/code")).body).toEqual(first);

    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS;
    const second = (await call(ava, "POST", "/friends/code")).body;
    expect(second.code).not.toBe(first.code);
    expect(second.expiresAt).toBe(app.clock.now + FRIEND_CODE_LIFETIME_SECONDS);
    // The expired one is kept for a while so its link can say so.
    expect(app.count("SELECT count(*) FROM invite_codes")).toBe(2);

    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS + EXPIRED_CODE_RETENTION_SECONDS + 1;
    await call(ava, "POST", "/friends/code");
    expect(app.count("SELECT count(*) FROM invite_codes WHERE code = ?", first.code)).toBe(0);
    expect(app.count("SELECT count(*) FROM invite_codes")).toBe(2);
  });

  test("tries again when a new code is already taken", async () => {
    app.deps.random = scripted([0, 1, 2, 3, 4, 5, 6, 7]);
    expect(await codeOf(ava)).toBe("ABCDEFGH");
    app.deps.random = scripted([0, 1, 2, 3, 4, 5, 6, 7], [8, 9, 10, 11, 12, 13, 14, 15]);
    expect(await codeOf(noor)).toBe("JKLMNPQR");

    const kai = await app.user("kai");
    app.deps.random = () => Uint8Array.from([0, 1, 2, 3, 4, 5, 6, 7]);
    expect(await call(kai, "POST", "/friends/code")).toEqual({ status: 500, body: { error: expect.any(String), code: "internal" } });
  });

  test("links use INVITE_HOST when it's set", async () => {
    for (const host of ["lockin.app", "https://lockin.app/", " lockin.app\n"]) {
      app.env.INVITE_HOST = host;
      const { body } = await call(ava, "POST", "/friends/code");
      expect(body.url).toBe(`https://lockin.app/j/${body.code}`);
    }
  });
});

describe("POST /friends/redeem/:code", () => {
  test("makes both people friends, in both directions", async () => {
    const code = await codeOf(ava);
    app.clock.now = T0 + 100;
    const { status, body } = await call(noor, "POST", `/friends/redeem/${code}`);
    expect(status).toBe(200);
    expect(body).toEqual({ friend: { id: ava.user.id, handle: "ava", displayName: "Ava", avatarCode: "b0.c0.e0.h0", since: T0 + 100 } });

    expect(app.sqlite.prepare("SELECT user_id, friend_id, created_at FROM friendships ORDER BY user_id = ?").all(noor.user.id).map((row) => ({ ...row }))).toEqual([
      { user_id: ava.user.id, friend_id: noor.user.id, created_at: T0 + 100 },
      { user_id: noor.user.id, friend_id: ava.user.id, created_at: T0 + 100 },
    ]);
    expect((await call(ava, "GET", "/friends")).body).toEqual({
      friends: [{ id: noor.user.id, handle: "noor", displayName: "Noor", avatarCode: "b0.c0.e0.h0", since: T0 + 100 }],
    });
    expect((await call(noor, "GET", "/friends")).body.friends.map((friend: { id: string }) => friend.id)).toEqual([ava.user.id]);
  });

  test("ignores case, spaces and dashes, and the code works for more than one friend", async () => {
    const code = await codeOf(ava);
    expect((await call(noor, "POST", `/friends/redeem/${code.toLowerCase()}`)).status).toBe(200);
    await call(noor, "DELETE", `/friends/${ava.user.id}`);
    expect((await call(noor, "POST", `/friends/redeem/${code.slice(0, 4)}-${code.slice(4)}`)).status).toBe(200);
    await call(noor, "DELETE", `/friends/${ava.user.id}`);
    expect((await call(noor, "POST", `/friends/redeem/%20${code.slice(0, 4)}%E2%80%93${code.slice(4)}%20`)).status).toBe(200);
    const kai = await app.user("kai");
    expect((await call(kai, "POST", `/friends/redeem/${code}`)).status).toBe(200);
    expect((await call(ava, "GET", "/friends")).body.friends).toHaveLength(2);
  });

  test("404 code_not_found for a code that doesn't exist or can't", async () => {
    await codeOf(ava);
    app.sqlite.prepare("INSERT INTO invite_codes (code, kind, target_id, created_by, expires_at) VALUES ('SQUADABC', 'squad', 'Sq00000001', ?, NULL)").run(ava.user.id);
    for (const code of ["ZZZZZZZZ", "abc", "AAAAAAA0", "AAAAAAAI", "AAAAAAAAA", "SQUADABC", "%E0%A4%A"]) {
      expect(await call(noor, "POST", `/friends/redeem/${code}`), code).toEqual({ status: 404, body: { error: expect.any(String), code: "code_not_found" } });
    }
    expect(app.count("SELECT count(*) FROM friendships")).toBe(0);
  });

  test("410 code_expired after a week", async () => {
    const code = await codeOf(ava);
    app.clock.now = T0 + FRIEND_CODE_LIFETIME_SECONDS;
    expect(await call(noor, "POST", `/friends/redeem/${code}`)).toEqual({ status: 410, body: { error: expect.any(String), code: "code_expired" } });
  });

  test("422 own_code", async () => {
    const code = await codeOf(ava);
    expect(await call(ava, "POST", `/friends/redeem/${code}`)).toEqual({ status: 422, body: { error: expect.any(String), code: "own_code" } });
  });

  test("409 already_friends", async () => {
    const code = await codeOf(ava);
    await call(noor, "POST", `/friends/redeem/${code}`);
    expect(await call(noor, "POST", `/friends/redeem/${code}`)).toEqual({ status: 409, body: { error: expect.any(String), code: "already_friends" } });
    // Either side's code says the same.
    expect((await call(ava, "POST", `/friends/redeem/${await codeOf(noor)}`)).body.code).toBe("already_friends");
  });

  test("403 blocked, whoever blocked whom", async () => {
    const code = await codeOf(ava);
    await call(ava, "POST", "/blocks", { userId: noor.user.id });
    expect(await call(noor, "POST", `/friends/redeem/${code}`)).toEqual({ status: 403, body: { error: expect.any(String), code: "blocked" } });
    await call(ava, "DELETE", `/blocks/${noor.user.id}`);
    await call(noor, "POST", "/blocks", { userId: ava.user.id });
    expect((await call(noor, "POST", `/friends/redeem/${code}`)).body.code).toBe("blocked");
    expect(app.count("SELECT count(*) FROM friendships")).toBe(0);
  });

  test("a deleted account's code is gone", async () => {
    const code = await codeOf(ava);
    await call(ava, "DELETE", "/me");
    expect((await call(noor, "POST", `/friends/redeem/${code}`)).body.code).toBe("code_not_found");
  });
});

describe("GET /friends", () => {
  test("is empty to start with, newest first after, and shows friends who haven't picked a name yet", async () => {
    expect(await call(ava, "GET", "/friends")).toEqual({ status: 200, body: { friends: [] } });
    const code = await codeOf(ava);
    await call(noor, "POST", `/friends/redeem/${code}`);
    app.clock.now = T0 + 50;
    const newcomer = await app.signIn("sub.newcomer");
    await call(newcomer, "POST", `/friends/redeem/${code}`);

    const { friends } = (await call(ava, "GET", "/friends")).body;
    expect(friends).toEqual([
      { id: newcomer.user.id, handle: null, displayName: null, avatarCode: "b0.c0.e0.h0", since: T0 + 50 },
      { id: noor.user.id, handle: "noor", displayName: "Noor", avatarCode: "b0.c0.e0.h0", since: T0 },
    ]);
  });
});

describe("DELETE /friends/:id", () => {
  test("ends the friendship both ways, and is fine to repeat", async () => {
    await call(noor, "POST", `/friends/redeem/${await codeOf(ava)}`);
    expect((await call(ava, "DELETE", `/friends/${noor.user.id}`)).status).toBe(204);
    expect(app.count("SELECT count(*) FROM friendships")).toBe(0);
    expect((await call(noor, "GET", "/friends")).body.friends).toEqual([]);
    for (const id of [noor.user.id, "Nobody0000", "not-an-id"]) expect((await call(ava, "DELETE", `/friends/${id}`)).status).toBe(204);
  });
});

describe("blocks", () => {
  test("POST /blocks blocks and ends the friendship; GET /blocks lists them", async () => {
    await call(noor, "POST", `/friends/redeem/${await codeOf(ava)}`);
    app.clock.now = T0 + 10;
    expect((await call(ava, "POST", "/blocks", { userId: noor.user.id })).status).toBe(204);
    expect(app.count("SELECT count(*) FROM friendships")).toBe(0);
    expect((await call(ava, "GET", "/friends")).body.friends).toEqual([]);
    expect((await call(noor, "GET", "/friends")).body.friends).toEqual([]);
    expect(await call(ava, "GET", "/blocks")).toEqual({
      status: 200,
      body: { blocked: [{ id: noor.user.id, handle: "noor", displayName: "Noor", avatarCode: "b0.c0.e0.h0", since: T0 + 10 }] },
    });
    // Noor's own list doesn't show who blocked them.
    expect((await call(noor, "GET", "/blocks")).body).toEqual({ blocked: [] });
    // Again is fine.
    expect((await call(ava, "POST", "/blocks", { userId: noor.user.id })).status).toBe(204);
    expect(app.count("SELECT count(*) FROM blocks")).toBe(1);
  });

  test("404 user_not_found for someone who isn't there", async () => {
    for (const body of [{ userId: "Nobody0000" }, { userId: "nope" }, { userId: 5 }, {}]) {
      expect(await call(ava, "POST", "/blocks", body)).toEqual({ status: 404, body: { error: expect.any(String), code: "user_not_found" } });
    }
    expect((await call(ava, "POST", "/blocks", { userId: ava.user.id })).status).toBe(400);
    expect(app.count("SELECT count(*) FROM blocks")).toBe(0);
  });

  test("DELETE /blocks/:userId unblocks, without bringing the friendship back", async () => {
    await call(noor, "POST", `/friends/redeem/${await codeOf(ava)}`);
    await call(ava, "POST", "/blocks", { userId: noor.user.id });
    expect((await call(ava, "DELETE", `/blocks/${noor.user.id}`)).status).toBe(204);
    expect((await call(ava, "GET", "/blocks")).body).toEqual({ blocked: [] });
    expect((await call(ava, "GET", "/friends")).body).toEqual({ friends: [] });
    expect((await call(ava, "DELETE", `/blocks/${noor.user.id}`)).status).toBe(204);
    // And a code works again.
    expect((await call(noor, "POST", `/friends/redeem/${await codeOf(ava)}`)).status).toBe(200);
  });
});

describe("POST /reports", () => {
  const reports = () => app.sqlite.prepare("SELECT * FROM reports").all().map((row) => ({ ...row }));

  test("files a report for moderators", async () => {
    expect((await call(ava, "POST", "/reports", { userId: noor.user.id, reason: "name", note: "  their name is rude  " })).status).toBe(204);
    expect((await call(ava, "POST", "/reports", { userId: noor.user.id, reason: "spam" })).status).toBe(204);
    expect((await call(ava, "POST", "/reports", { userId: noor.user.id, reason: "other", note: "   " })).status).toBe(204);
    expect((await call(ava, "POST", "/reports", { userId: noor.user.id, reason: "harassment", note: null })).status).toBe(204);
    expect(reports()).toEqual([
      { id: expect.stringMatching(/^[0-9A-Za-z]{10}$/), reporter_id: ava.user.id, target_user_id: noor.user.id, reason: "name", note: "their name is rude", created_at: T0 },
      expect.objectContaining({ reason: "spam", note: null }),
      expect.objectContaining({ reason: "other", note: null }),
      expect.objectContaining({ reason: "harassment", note: null }),
    ]);
    expect(logs).toContain("reports: new report (name)");
    expect(logs.join("\n")).not.toContain("rude");
  });

  test.each([
    { reason: "rude" },
    { reason: undefined },
    { userId: "Nobody0000" },
    { userId: "nope" },
    { userId: undefined },
    { self: true },
    { note: "x".repeat(501) },
    { note: 5 },
  ])("422 report_invalid for %j", async (change) => {
    const body = { userId: noor.user.id, reason: "harassment", ...change } as Record<string, unknown>;
    if (body.self) body.userId = ava.user.id;
    delete body.self;
    expect(await call(ava, "POST", "/reports", body)).toEqual({ status: 422, body: { error: expect.any(String), code: "report_invalid" } });
    expect(reports()).toHaveLength(0);
  });

  test("a 500-character note is fine", async () => {
    expect((await call(ava, "POST", "/reports", { userId: noor.user.id, reason: "other", note: "🦊".repeat(500) })).status).toBe(204);
  });
});
