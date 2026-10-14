// M7, Lockin Plus on the server (docs/milestones/M7.md), through the whole Worker: RevenueCat's
// webhook, POST /me/plus/refresh against a fake RevenueCat, Squad Boost and the pet's accessories
// (in GET /squads and in the room's `p.k`), and streak freezes across months and time zones.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { startOfDay } from "../src/days.ts";
import { LIFETIME_PLUS_UNTIL } from "../src/db.ts";
import { REVENUECAT_API, plusUntilFromSubscriber } from "../src/plus.ts";
import { COALESCE_SECONDS } from "../src/room.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";
import { JWT_IN_LOG } from "./helpers.ts";
import { laToken } from "./rooms.ts";

const AUTH = "Bearer whsec-test-0123456789";
const SECRET_KEY = "sk_test_revenuecat_0123456789";

let app: TestApp;
let ava: SignedIn;
let noor: SignedIn;
let logs: string[];
/** What the fake RevenueCat REST API was asked, and what it answers next. */
let revenueCat: { requests: Array<{ url: string; authorization: string | null }>; answer: () => Response };

beforeEach(async () => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  app = await testApp({ REVENUECAT_WEBHOOK_AUTH: AUTH, REVENUECAT_SECRET_KEY: SECRET_KEY });
  ava = await app.user("ava", "Ava");
  noor = await app.user("noor", "Noor");
  revenueCat = { requests: [], answer: () => Response.json({ subscriber: { entitlements: {} } }) };
  const others = app.deps.fetch as typeof fetch;
  app.deps.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    if (!request.url.startsWith(REVENUECAT_API)) return others(input, init);
    revenueCat.requests.push({ url: request.url, authorization: request.headers.get("authorization") });
    return revenueCat.answer();
  }) as typeof fetch;
});

afterEach(async () => {
  await app.settle();
  vi.restoreAllMocks();
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toContain(SECRET_KEY);
    expect(line).not.toContain("whsec");
    expect(line).not.toMatch(/\b(ava|noor|Ava|Noor|Library Goblins)\b/);
    expect(line).not.toMatch(JWT_IN_LOG);
  }
});

const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const MONTH = 30 * DAY;

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));
const plusUntil = (who: SignedIn) => app.value("SELECT plus_until FROM users WHERE id = ?", who.user.id);
const setPlus = (who: SignedIn, until: number | null) => app.sqlite.prepare("UPDATE users SET plus_until = ? WHERE id = ?").run(until, who.user.id);

let eventSeq = 0;
/** A RevenueCat event for `who`, as its webhook sends it (the fields we read, and a few we don't). */
function rcEvent(type: string, who: SignedIn | null, extra: Record<string, unknown> = {}): Record<string, unknown> {
  eventSeq += 1;
  return {
    id: `CD489E0E-0000-4000-8000-${String(eventSeq).padStart(12, "0")}`,
    type,
    app_id: "app1234",
    app_user_id: who?.user.id ?? "$RCAnonymousID:2f1e7f40b2b64c6b9b3f5c8e2a1d0e9f",
    original_app_user_id: who?.user.id ?? "$RCAnonymousID:2f1e7f40b2b64c6b9b3f5c8e2a1d0e9f",
    aliases: who === null ? [] : [who.user.id],
    event_timestamp_ms: app.clock.now * 1000,
    purchased_at_ms: app.clock.now * 1000,
    expiration_at_ms: (app.clock.now + MONTH) * 1000,
    product_id: "com.example.lockin.plus.monthly",
    entitlement_ids: ["plus"],
    period_type: "NORMAL",
    environment: "SANDBOX",
    store: "APP_STORE",
    ...extra,
  };
}

/** Posts `event` to the webhook; `authorization` null sends no header. */
async function hook(event: Record<string, unknown>, authorization: string | null = AUTH) {
  const headers: Record<string, string> = authorization === null ? {} : { authorization };
  return read(await app.request("POST", "/webhooks/revenuecat", { body: { api_version: "1.0", event }, headers }));
}

async function squad(owner: SignedIn, members: SignedIn[] = [], extra: Record<string, unknown> = {}, name = "Library Goblins"): Promise<string> {
  const created = await call(owner, "POST", "/squads", { name, ...extra });
  expect(created.status, JSON.stringify(created.body)).toBe(200);
  const id = created.body.squad.id as string;
  const code = (await call(owner, "POST", `/squads/${id}/invite`)).body.code as string;
  for (const member of members) expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
  return id;
}

async function mySquad(who: SignedIn, squadId: string) {
  return (await call(who, "GET", "/squads")).body.squads.find((each: { id: string }) => each.id === squadId);
}

describe("POST /webhooks/revenuecat", () => {
  test("only with the exact Authorization value: 401 otherwise, 503 not_configured without the secret", async () => {
    const event = rcEvent("INITIAL_PURCHASE", ava);
    expect(await hook(event, null)).toEqual({ status: 401, body: { error: expect.any(String), code: "unauthorised" } });
    expect((await hook(event, "")).status).toBe(401);
    expect((await hook(event, "Bearer whsec-test-012345678")).status).toBe(401);
    expect((await hook(event, AUTH.toLowerCase())).status).toBe(401);
    expect(plusUntil(ava)).toBeNull();
    expect(await hook(event)).toEqual({ status: 200, body: { ok: true, result: "applied" } });

    Object.assign(app.env, { REVENUECAT_WEBHOOK_AUTH: undefined });
    expect(await hook(rcEvent("RENEWAL", ava))).toEqual({ status: 503, body: { error: expect.any(String), code: "not_configured" } });
  });

  test("TEST answers 200; a body that isn't an event is 400", async () => {
    expect(await hook({ id: "test-1", type: "TEST" })).toEqual({ status: 200, body: { ok: true, result: "test" } });
    expect((await hook({ type: "RENEWAL" })).status).toBe(400);
    expect((await read(await app.request("POST", "/webhooks/revenuecat", { body: { nope: 1 }, headers: { authorization: AUTH } }))).status).toBe(400);
  });

  test("purchases, renewals, product changes and un-cancellations set plus_until from expiration_at_ms", async () => {
    await hook(rcEvent("INITIAL_PURCHASE", ava, { expiration_at_ms: (T0 + 7 * DAY) * 1000 + 999 }));
    expect(plusUntil(ava)).toBe(T0 + 7 * DAY);
    expect((await call(ava, "GET", "/me")).body.user.plusUntil).toBe(T0 + 7 * DAY);
    for (const [type, until] of [
      ["RENEWAL", T0 + 37 * DAY],
      ["PRODUCT_CHANGE", T0 + 365 * DAY],
      ["UNCANCELLATION", T0 + 366 * DAY],
    ] as const) {
      app.clock.now += MINUTE;
      expect((await hook(rcEvent(type, ava, { expiration_at_ms: until * 1000 }))).body.result).toBe("applied");
      expect(plusUntil(ava), type).toBe(until);
    }
    expect(plusUntil(noor)).toBeNull();
  });

  test("the same event twice counts once", async () => {
    const renewal = rcEvent("RENEWAL", ava, { expiration_at_ms: (T0 + MONTH) * 1000 });
    await hook(renewal);
    app.clock.now += DAY;
    await hook(rcEvent("EXPIRATION", ava, { expiration_at_ms: app.clock.now * 1000 }));
    expect(plusUntil(ava)).toBe(T0 + DAY);
    expect(await hook(renewal)).toEqual({ status: 200, body: { ok: true, result: "duplicate" } });
    expect(plusUntil(ava)).toBe(T0 + DAY);
    expect(app.count("SELECT count(*) FROM revenuecat_events")).toBe(2);
  });

  test("an event older than the last one applied changes nothing: an old EXPIRATION can't undo a RENEWAL", async () => {
    const lateExpiry = rcEvent("EXPIRATION", ava, { event_timestamp_ms: T0 * 1000, expiration_at_ms: T0 * 1000 });
    app.clock.now += HOUR;
    await hook(rcEvent("RENEWAL", ava, { expiration_at_ms: (T0 + MONTH) * 1000 }));
    expect(await hook(lateExpiry)).toEqual({ status: 200, body: { ok: true, result: expect.stringMatching(/^unchanged/) } });
    expect(plusUntil(ava)).toBe(T0 + MONTH);
  });

  test("EXPIRATION ends it; a CANCELLATION only when it's a refund (CUSTOMER_SUPPORT)", async () => {
    await hook(rcEvent("INITIAL_PURCHASE", ava));
    app.clock.now += DAY;
    // Turning off renewal: Plus lasts to the end of the period.
    expect((await hook(rcEvent("CANCELLATION", ava, { cancel_reason: "UNSUBSCRIBE" }))).body.result).toMatch(/^ignored/);
    expect(plusUntil(ava)).toBe(T0 + MONTH);
    // A refund: now.
    await hook(rcEvent("CANCELLATION", ava, { cancel_reason: "CUSTOMER_SUPPORT" }));
    expect(plusUntil(ava)).toBe(T0 + DAY);

    await hook(rcEvent("INITIAL_PURCHASE", noor));
    app.clock.now = T0 + MONTH + MINUTE;
    await hook(rcEvent("EXPIRATION", noor, { expiration_at_ms: (T0 + MONTH) * 1000 }));
    expect(plusUntil(noor)).toBe(T0 + MONTH);
  });

  test("a one-time purchase is Plus for life (year 9999), which subscription events don't take away; its refund does", async () => {
    await hook(rcEvent("NON_RENEWING_PURCHASE", ava, { expiration_at_ms: null, product_id: "com.example.lockin.plus.lifetime" }));
    expect(plusUntil(ava)).toBe(LIFETIME_PLUS_UNTIL);
    expect(new Date(LIFETIME_PLUS_UNTIL * 1000).toISOString()).toBe("9999-12-31T23:59:59.000Z");
    app.clock.now += MINUTE;
    await hook(rcEvent("EXPIRATION", ava, { expiration_at_ms: app.clock.now * 1000 }));
    await hook(rcEvent("RENEWAL", ava));
    await hook(rcEvent("CANCELLATION", ava, { cancel_reason: "CUSTOMER_SUPPORT" }));
    expect(plusUntil(ava)).toBe(LIFETIME_PLUS_UNTIL);
    // Refunding the lifetime purchase itself (no expiration) ends it.
    await hook(rcEvent("CANCELLATION", ava, { cancel_reason: "CUSTOMER_SUPPORT", expiration_at_ms: null, product_id: "com.example.lockin.plus.lifetime" }));
    expect(plusUntil(ava)).toBe(app.clock.now);
  });

  test("finds our user among app_user_id, original_app_user_id and aliases; anonymous and unknown ids are ignored", async () => {
    const anonymous = "$RCAnonymousID:2f1e7f40b2b64c6b9b3f5c8e2a1d0e9f";
    expect((await hook(rcEvent("INITIAL_PURCHASE", null))).body.result).toBe("ignored (nobody of ours)");
    expect((await hook(rcEvent("INITIAL_PURCHASE", null, { app_user_id: "Zz00000000", aliases: ["Zz00000000"] }))).body.result).toMatch(/^ignored/);
    // Bought anonymously, then logged in: the alias is ours.
    await hook(rcEvent("INITIAL_PURCHASE", null, { app_user_id: anonymous, original_app_user_id: anonymous, aliases: [anonymous, noor.user.id] }));
    expect(plusUntil(noor)).toBe(T0 + MONTH);
    // Demo Buddy never has Plus.
    expect((await hook(rcEvent("INITIAL_PURCHASE", null, { app_user_id: "DemoBuddy0" }))).body.result).toMatch(/^ignored/);
    expect(app.value("SELECT plus_until FROM users WHERE id = 'DemoBuddy0'")).toBeNull();
    // Another entitlement, or an event that isn't about Plus: recorded and left alone.
    expect((await hook(rcEvent("INITIAL_PURCHASE", ava, { entitlement_ids: ["coins"] }))).body.result).toBe("ignored (another entitlement)");
    expect((await hook(rcEvent("BILLING_ISSUE", ava))).body.result).toBe("ignored (not a Plus change)");
    expect(plusUntil(ava)).toBeNull();
    expect(app.count("SELECT count(*) FROM revenuecat_events")).toBe(6);
  });

  test("TRANSFER moves Plus from one of our users to another", async () => {
    await hook(rcEvent("INITIAL_PURCHASE", ava));
    app.clock.now += MINUTE;
    const transfer = rcEvent("TRANSFER", null, { transferred_from: [ava.user.id], transferred_to: [noor.user.id], app_user_id: undefined, expiration_at_ms: undefined });
    expect((await hook(transfer)).body.result).toBe("applied");
    expect([plusUntil(ava), plusUntil(noor)]).toEqual([null, T0 + MONTH]);
    // From an anonymous customer to us: nothing of ours to move (the app refreshes).
    app.clock.now += MINUTE;
    expect((await hook(rcEvent("TRANSFER", null, { transferred_from: ["$RCAnonymousID:abc"], transferred_to: [ava.user.id] }))).body.result).toMatch(/^ignored/);
    expect(plusUntil(ava)).toBeNull();
  });
});

describe("POST /me/plus/refresh", () => {
  const subscriber = (plus: Record<string, unknown> | undefined) =>
    Response.json({ request_date: "2026-10-14T17:46:40Z", subscriber: { original_app_user_id: ava.user.id, entitlements: plus === undefined ? {} : { plus } } });

  test("asks RevenueCat about the caller and sets plus_until from the plus entitlement", async () => {
    revenueCat.answer = () => subscriber({ expires_date: "2026-11-14T17:46:40Z", product_identifier: "com.example.lockin.plus.monthly" });
    const response = await call(ava, "POST", "/me/plus/refresh");
    expect(response).toEqual({ status: 200, body: { user: expect.objectContaining({ id: ava.user.id, plusUntil: Date.parse("2026-11-14T17:46:40Z") / 1000 }) } });
    expect(revenueCat.requests).toEqual([{ url: `${REVENUECAT_API}/v1/subscribers/${ava.user.id}`, authorization: `Bearer ${SECRET_KEY}` }]);
    expect(logs).toContain("plus: refreshed");

    // A lifetime purchase (expires_date null); no entitlement at all: no Plus.
    revenueCat.answer = () => subscriber({ expires_date: null });
    expect((await call(ava, "POST", "/me/plus/refresh")).body.user.plusUntil).toBe(LIFETIME_PLUS_UNTIL);
    revenueCat.answer = () => subscriber(undefined);
    expect((await call(ava, "POST", "/me/plus/refresh")).body.user.plusUntil).toBeNull();
  });

  test("a refresh is newer than any webhook event from before it", async () => {
    revenueCat.answer = () => subscriber({ expires_date: "2026-11-14T17:46:40Z" });
    await call(ava, "POST", "/me/plus/refresh");
    await hook(rcEvent("EXPIRATION", ava, { event_timestamp_ms: (T0 - 1) * 1000, expiration_at_ms: (T0 - 1) * 1000 }));
    expect(plusUntil(ava)).toBe(Date.parse("2026-11-14T17:46:40Z") / 1000);
  });

  test("503 try_again when RevenueCat fails or makes no sense; 503 not_configured without the key", async () => {
    setPlus(ava, T0 + DAY);
    for (const answer of [() => new Response("oops", { status: 500 }), () => Response.json({ nope: true }), () => new Response("not json")]) {
      revenueCat.answer = answer;
      expect(await call(ava, "POST", "/me/plus/refresh")).toEqual({ status: 503, body: { error: expect.any(String), code: "try_again" } });
    }
    revenueCat.answer = () => {
      throw new TypeError("fetch failed");
    };
    expect((await call(ava, "POST", "/me/plus/refresh")).body.code).toBe("try_again");
    expect(plusUntil(ava)).toBe(T0 + DAY);

    Object.assign(app.env, { REVENUECAT_SECRET_KEY: "" });
    expect(await call(ava, "POST", "/me/plus/refresh")).toEqual({ status: 503, body: { error: expect.any(String), code: "not_configured" } });
    expect((await app.request("POST", "/me/plus/refresh")).status).toBe(401);
  });

  test("reads RevenueCat's subscriber: the later of expiry and grace period", () => {
    expect(plusUntilFromSubscriber({ subscriber: { entitlements: { plus: { expires_date: "2026-11-01T00:00:00Z", grace_period_expires_date: "2026-11-17T00:00:00Z" } } } })).toBe(
      Date.UTC(2026, 10, 17) / 1000,
    );
    expect(plusUntilFromSubscriber({ subscriber: {} })).toBeNull();
    expect(plusUntilFromSubscriber({ subscriber: { entitlements: { plus: { expires_date: "soon" } } } })).toBeUndefined();
    expect(plusUntilFromSubscriber(null)).toBeUndefined();
  });
});

describe("Squad Boost", () => {
  test("a squad with any Plus member is boosted, for everyone in it", async () => {
    const squadId = await squad(ava, [noor]);
    expect((await mySquad(ava, squadId)).boosted).toBe(false);
    await hook(rcEvent("INITIAL_PURCHASE", noor));
    expect((await mySquad(ava, squadId)).boosted).toBe(true);
    expect((await mySquad(noor, squadId)).boosted).toBe(true);
    app.clock.now = T0 + MONTH;
    expect((await mySquad(ava, squadId)).boosted).toBe(false);
  });

  test("PATCH /squads/:id/pet: any member of a boosted squad picks an accessory, the room shows it at once", async () => {
    const squadId = await squad(ava, [noor]);
    const species = app.value("SELECT pet_species FROM squads WHERE id = ?", squadId);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    expect((await call(ava, "POST", `/sessions/${sid}/la-token`, { token: laToken(1), env: "production" })).status).toBe(204);

    // Not boosted: 402, but taking it off is fine.
    expect(await call(ava, "PATCH", `/squads/${squadId}/pet`, { accessory: 2 })).toEqual({
      status: 402,
      body: { error: expect.any(String), code: "plus_required", limit: "boost" },
    });
    expect((await call(ava, "PATCH", `/squads/${squadId}/pet`, { accessory: null })).status).toBe(200);

    setPlus(noor, T0 + MONTH);
    // Ava has no Plus herself: Noor's boosts the whole squad.
    const picked = await call(ava, "PATCH", `/squads/${squadId}/pet`, { accessory: 2 });
    expect(picked.status).toBe(200);
    expect(picked.body.squad).toMatchObject({ boosted: true, pet: { accessory: 2 } });
    expect(app.value("SELECT pet_accessory FROM squads WHERE id = ?", squadId)).toBe(2);
    app.apns.clear();
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => [request.priority, request.aps["content-state"].p.k])).toEqual([[5, `${species}.0.a2`]]);
    expect(logs).toContain("squads: pet accessory changed");

    // Noor's Plus expires (the webhook tells the rooms): the accessory comes off, and is kept for later.
    app.apns.clear();
    await hook(rcEvent("EXPIRATION", noor, { expiration_at_ms: app.clock.now * 1000 }));
    await app.settle();
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => request.aps["content-state"].p.k)).toEqual([`${species}.0`]);
    expect((await mySquad(ava, squadId)).pet.accessory).toBeNull();
    // Plus back: on again.
    await hook(rcEvent("RENEWAL", noor, { event_timestamp_ms: (app.clock.now + 1) * 1000 }));
    await app.settle();
    expect((await mySquad(ava, squadId)).pet.accessory).toBe(2);
    expect((await call(ava, "GET", `/sessions/${sid}`)).body.contentState.p.k).toBe(`${species}.0.a2`);
  });

  test("422 accessory_invalid for anything but a catalogue accessory or null; 403 not_member", async () => {
    const squadId = await squad(ava, [noor]);
    setPlus(ava, T0 + MONTH);
    for (const accessory of [0, 7, 1.5, "1", true, undefined]) {
      expect(await call(ava, "PATCH", `/squads/${squadId}/pet`, { accessory }), String(accessory)).toEqual({
        status: 422,
        body: { error: expect.any(String), code: "accessory_invalid" },
      });
    }
    for (let n = 1; n <= 6; n++) expect((await call(noor, "PATCH", `/squads/${squadId}/pet`, { accessory: n })).status).toBe(200);
    const outsider = await app.user("kai", "Kai");
    expect((await call(outsider, "PATCH", `/squads/${squadId}/pet`, { accessory: 1 })).body.code).toBe("not_member");
    expect((await call(outsider, "PATCH", "/squads/nope/pet", { accessory: 1 })).body.code).toBe("not_member");
  });

  test("the accessories are the squad's, not a Lockling's: never owned, never bought", async () => {
    setPlus(ava, T0 + MONTH);
    expect((await call(ava, "GET", "/me/cosmetics")).body.owned.filter((id: string) => id.startsWith("pet."))).toEqual([]);
    expect((await call(noor, "POST", "/shop/buy", { itemId: "pet.1" })).body.code).toBe("plus_required");
    expect((await read(await app.request("GET", "/shop"))).body.items.filter((item: { part: string }) => item.part === "pet")).toHaveLength(6);
  });
});

describe("streak freezes", () => {
  /** Puts the clock at `hour` o'clock on `day` in `tz`. */
  const at = (day: string, hour: number, tz = "UTC") => {
    app.clock.now = startOfDay(tz, day) + hour * HOUR;
  };
  /** A finished 20-minute solo session: enough to count. */
  const solo = async (who: SignedIn) => {
    expect((await call(who, "POST", "/sessions", { minutes: 20 })).status).toBe(200);
    await app.advance(20 * MINUTE);
  };
  const freezeRows = () => app.sqlite.prepare("SELECT squad_id, day, user_id FROM streak_freezes ORDER BY day").all().map((row) => ({ ...row }));
  const setStreak = (squadId: string, count: number, lastDay: string) =>
    app.sqlite.prepare("UPDATE squads SET streak_count = ?, streak_last_day = ? WHERE id = ?").run(count, lastDay, squadId);

  test("a missed day is filled with a Plus member's freeze, two a month; then it breaks", async () => {
    const squadId = await squad(ava, [noor]);
    setPlus(ava, T0 + 365 * DAY);
    const streak = async (who = ava) => (await mySquad(who, squadId)).streak;

    await solo(noor);
    expect(await streak()).toMatchObject({ count: 1, frozenDays: [], freezes: 2 });

    // The 15th went by: on the 16th, Ava's freeze fills it. The count stays, the streak lives.
    at("2026-10-16", 9);
    expect(await streak()).toEqual({ count: 1, countedToday: false, doneToday: 0, needed: 1, frozenDays: ["2026-10-15"], freezes: 1 });
    expect(freezeRows()).toEqual([{ squad_id: squadId, day: "2026-10-15", user_id: ava.user.id }]);
    // Noor has no Plus: no freezes of her own, but she sees the frozen day.
    expect(await streak(noor)).toMatchObject({ frozenDays: ["2026-10-15"], freezes: 0 });
    await solo(noor);
    expect(await streak()).toMatchObject({ count: 2, countedToday: true });

    // The 17th too: the second freeze.
    at("2026-10-18", 9);
    expect(await streak()).toMatchObject({ count: 2, frozenDays: ["2026-10-15", "2026-10-17"], freezes: 0 });
    // The 19th: none left this month, so it breaks.
    at("2026-10-20", 9);
    expect(await streak()).toMatchObject({ count: 0, frozenDays: ["2026-10-15", "2026-10-17"], freezes: 0 });
    expect(app.count("SELECT count(*) FROM streak_freezes")).toBe(2);
  });

  test("one gap at most: two days missed breaks it, freezes or not; nobody with Plus, no freeze", async () => {
    const plusSquad = await squad(ava, [noor]);
    setPlus(ava, T0 + 365 * DAY);
    await solo(ava);
    at("2026-10-17", 9);
    expect((await mySquad(ava, plusSquad)).streak).toMatchObject({ count: 0, frozenDays: [], freezes: 2 });

    const kai = await app.user("kai", "Kai");
    const plain = await squad(kai, [], {}, "Night Owls");
    setStreak(plain, 3, "2026-10-15");
    expect((await mySquad(kai, plain)).streak).toMatchObject({ count: 0, frozenDays: [], freezes: 0 });
    expect(app.count("SELECT count(*) FROM streak_freezes")).toBe(0);
  });

  test("a finish written the day after a gap fills it first, so the day carries the streak on", async () => {
    const squadId = await squad(ava, [noor]);
    setPlus(noor, T0 + 365 * DAY);
    await solo(ava);
    // Nobody looks at the squad on the 16th; Ava just locks in.
    at("2026-10-16", 20);
    await solo(ava);
    expect([app.value("SELECT streak_count FROM squads WHERE id = ?", squadId), app.value("SELECT streak_last_day FROM squads WHERE id = ?", squadId)]).toEqual([
      2,
      "2026-10-16",
    ]);
    expect(freezeRows()).toEqual([{ squad_id: squadId, day: "2026-10-15", user_id: noor.user.id }]);
    expect((await mySquad(noor, squadId)).streak).toMatchObject({ count: 2, countedToday: true, frozenDays: ["2026-10-15"], freezes: 1 });
  });

  test("two a month per member, across squads, by the month of the missed day", async () => {
    setPlus(ava, T0 + 365 * DAY);
    const first = await squad(ava, [], {}, "One");
    const second = await squad(ava, [], {}, "Two");
    const third = await squad(ava, [], {}, "Three");
    // October: two used in the first squad already.
    app.sqlite.prepare("INSERT INTO streak_freezes (squad_id, day, user_id, used_at) VALUES (?, '2026-10-03', ?, 1), (?, '2026-10-09', ?, 1)").run(first, ava.user.id, first, ava.user.id);

    // 1 November: the 31st (October) was missed in the second squad: none left, it breaks.
    setStreak(second, 5, "2026-10-30");
    at("2026-11-01", 10);
    expect((await mySquad(ava, second)).streak).toMatchObject({ count: 0, frozenDays: [] });
    // 2 November: the 1st (November) was missed in the third: November's freezes are fresh.
    setStreak(third, 5, "2026-10-31");
    at("2026-11-02", 10);
    expect((await mySquad(ava, third)).streak).toMatchObject({ count: 5, frozenDays: ["2026-11-01"], freezes: 1 });
  });

  test("days and months are the squad's own: the same moment fills a gap in Sydney and breaks one in Los Angeles", async () => {
    setPlus(ava, T0 + 365 * DAY);
    const sydney = await squad(ava, [], { tz: "Australia/Sydney" }, "Sydney");
    const angeles = await squad(ava, [], { tz: "America/Los_Angeles" }, "Angeles");
    const other = await squad(ava, [], {}, "Other");
    app.sqlite.prepare("INSERT INTO streak_freezes (squad_id, day, user_id, used_at) VALUES (?, '2026-10-03', ?, 1), (?, '2026-10-09', ?, 1)").run(other, ava.user.id, other, ava.user.id);
    setStreak(sydney, 4, "2026-10-31");
    setStreak(angeles, 4, "2026-10-30");

    // 14:00 UTC on 1 November: 01:00 on the 2nd in Sydney (the 1st missed: November), 06:00 on the
    // 1st in Los Angeles (the 31st missed: October, used up).
    app.clock.now = Date.UTC(2026, 10, 1, 14) / 1000;
    expect((await mySquad(ava, sydney)).streak).toMatchObject({ count: 4, frozenDays: ["2026-11-01"] });
    expect((await mySquad(ava, angeles)).streak).toMatchObject({ count: 0, frozenDays: [] });
  });

  test("frozenDays covers the last 30 days", async () => {
    const squadId = await squad(ava);
    const insert = app.sqlite.prepare("INSERT INTO streak_freezes (squad_id, day, user_id, used_at) VALUES (?, ?, ?, 1)");
    for (const day of ["2026-09-14", "2026-09-15", "2026-10-13"]) insert.run(squadId, day, ava.user.id);
    expect((await mySquad(ava, squadId)).streak.frozenDays).toEqual(["2026-09-15", "2026-10-13"]);
  });
});
