// "X is locking in" (M4) through the whole Worker: real SQL on an in-memory D1, the rooms on the fake
// Durable Objects runtime, the provider token from ApnsAuth, and a fake APNs. The alerts go out
// after the response, through `waitUntil`: `app.settle()` waits for them.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  ALERT_EXPIRY_SECONDS,
  ALERT_LOG_KEPT_SECONDS,
  DAILY_ALERT_WINDOW_SECONDS,
  REOPEN_SILENCE_SECONDS,
  SQUAD_ALERT_INTERVAL_SECONDS,
  deviceIsQuiet,
  inQuietHours,
  isQuietHours,
  localMinute,
  lockinAlertPayload,
} from "../src/alerts.ts";
import { APNS_KEY_ID, BUNDLE_ID, type SignedIn, T0, TEAM_ID, type TestApp, read, testApp } from "./app.ts";
import { JWT_IN_LOG, decodeJWT } from "./helpers.ts";
import { type APNsRequest, laToken } from "./rooms.ts";

let app: TestApp;
let ava: SignedIn;
let noor: SignedIn;
let kai: SignedIn;
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
  kai = await app.user("kai", "Kai");
});

afterEach(async () => {
  await app.settle();
  vi.restoreAllMocks();
  // Session ids and counts only: never who, never a token.
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    for (let seed = 0; seed < 16; seed++) expect(line).not.toContain(phone(seed));
    expect(line).not.toMatch(/\b(ava|noor|kai|mila|zed|lea|Ava|Noor|Kai|Mila|Zed|Lea|Library Goblins|Night Owls)\b/);
    expect(line).not.toMatch(JWT_IN_LOG);
  }
});

/** A phone's APNs device token: 64 hex characters, distinct from the Live Activity tokens. */
const phone = (seed: number) => laToken(0xa0 + seed);

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));

/** Registers a phone for `who`: LA time (10:46 at T0, outside the default quiet hours) unless told otherwise. */
async function register(who: SignedIn, seed: number, extra: Record<string, unknown> = {}) {
  const body = { apnsToken: phone(seed), env: "production", laEnabled: true, frequentPushes: false, tz: "America/Los_Angeles", ...extra };
  const response = await call(who, "POST", "/devices", body);
  expect(response.status, JSON.stringify(response.body)).toBe(204);
}

async function squad(owner: SignedIn, name: string, ...members: SignedIn[]): Promise<string> {
  const created = await call(owner, "POST", "/squads", { name });
  expect(created.status, JSON.stringify(created.body)).toBe(200);
  const id = created.body.squad.id as string;
  const code = (await call(owner, "POST", `/squads/${id}/invite`)).body.code as string;
  for (const member of members) expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
  return id;
}

/** `who` locks in with the squad (opening its room, if it has none) and the alerts go out. */
async function lockIn(who: SignedIn, squadId: string): Promise<string> {
  const response = await call(who, "POST", "/sessions", { squadId, minutes: 25 });
  expect(response.status, JSON.stringify(response.body)).toBe(200);
  await app.settle();
  return response.body.session.id as string;
}

/** Opens the squad's room, lets the alerts go, and ends it again: the next open is a new room. */
async function openAndEnd(who: SignedIn, squadId: string): Promise<string> {
  const sid = await lockIn(who, squadId);
  expect((await call(who, "POST", `/sessions/${sid}/end`)).status).toBe(200);
  return sid;
}

/** The alerts APNs got (not the rooms' Live Activity pushes). */
const alerts = (): APNsRequest[] => app.apns.requests.filter((request) => request.headers["apns-push-type"] === "alert");
/** The phones alerted, in seed order: phones go out together, in no particular order. */
const alertedPhones = () => alerts().map((request) => request.token).sort();
/** The `alerts` log, oldest first, then by recipient. */
const alertRows = () => app.sqlite.prepare("SELECT * FROM alerts ORDER BY sent_at, recipient_id").all().map((row) => ({ ...row }));
const plus = () => app.sqlite.prepare("UPDATE users SET plus_until = ?").run(T0 + 30 * 86_400);
/** Unix seconds for a UTC time on 2026-10-15, e.g. at("10:59"). */
const at = (time: string) => Date.parse(`2026-10-15T${time}:00Z`) / 1000;

describe("who's told", () => {
  test("opening a squad's room alerts every other member on every phone, after the response", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(ava, 0);
    await register(noor, 1);
    await register(noor, 2, { env: "sandbox", tz: "Europe/London" });
    await register(kai, 3);

    const response = await call(ava, "POST", "/sessions", { squadId, minutes: 25 });
    expect(response.status).toBe(200);
    const sid = response.body.session.id;
    // Handed to waitUntil, not awaited by the route.
    expect(app.background).toHaveLength(1);
    await app.settle();

    // Each phone at its own APNs host; not Ava's.
    expect(alerts().map((request) => request.url).sort((a, b) => a.slice(-64).localeCompare(b.slice(-64)))).toEqual([
      `https://api.push.apple.com/3/device/${phone(1)}`,
      `https://api.sandbox.push.apple.com/3/device/${phone(2)}`,
      `https://api.push.apple.com/3/device/${phone(3)}`,
    ]);
    // One row per person told, however many phones.
    const row = (recipient: SignedIn) => ({ recipient_id: recipient.user.id, squad_id: squadId, sender_id: ava.user.id, session_id: sid, sent_at: T0 });
    expect(alertRows()).toEqual([row(noor), row(kai)].sort((a, b) => (a.recipient_id < b.recipient_id ? -1 : 1)));
    expect(logs).toContain(`alerts ${sid}: 2 alerted, 0 in quiet hours, 0 over a limit; 3 pushes accepted, 0 refused, 0 failed, 0 devices removed`);
  });

  test("the headers and the body, exactly", async () => {
    const squadId = await squad(ava, "Library Goblins", noor);
    await register(noor, 1);
    const sid = await lockIn(ava, squadId);

    const [request] = alerts();
    expect(request?.headers).toEqual({
      authorization: expect.stringMatching(/^bearer /),
      "apns-push-type": "alert",
      "apns-topic": BUNDLE_ID,
      "apns-priority": "10",
      "apns-collapse-id": `lk-${sid}`,
      "apns-expiration": String(T0 + ALERT_EXPIRY_SECONDS),
      "content-type": "application/json",
    });
    expect(JSON.parse(request?.body ?? "")).toEqual({
      aps: {
        alert: { title: "Library Goblins", body: "Ava is locking in 🔒" },
        sound: "default",
        category: "LK_LOCKIN",
        "thread-id": `squad-${squadId}`,
        "interruption-level": "active",
      },
      lk: { type: "lockin", sid, sq: squadId },
    });
    // UTF-8 as is, not escaped.
    expect(request?.body).toContain("🔒");
    // The provider token every room presents, from ApnsAuth (docs/decisions/0004).
    const jwt = decodeJWT(request?.jwt ?? "");
    expect(jwt.header).toEqual({ alg: "ES256", kid: APNS_KEY_ID });
    expect(jwt.claims).toEqual({ iss: TEAM_ID, iat: T0 });
    expect(app.apnsAuth.calls).toEqual([{ name: "global", path: "/token" }]);
  });

  test("the name is the opener's Live Activity name: display name, else handle, else Lockling", async () => {
    const handled = await app.user("verylonghandle123", null);
    const nameless = await app.signIn("sub.nameless");
    plus();
    const squadId = await squad(ava, "Library Goblins", noor, handled, nameless);
    await register(ava, 0);
    await openAndEnd(handled, squadId);
    app.clock.now += SQUAD_ALERT_INTERVAL_SECONDS;
    await openAndEnd(nameless, squadId);
    expect(alerts().map((request) => JSON.parse(request.body).aps.alert.body)).toEqual(["verylonghand is locking in 🔒", "Lockling is locking in 🔒"]);
    expect(lockinAlertPayload({ squadId, squadName: "🔒".repeat(20), sessionId: "r7Kq2xP9aL", openerId: ava.user.id, openerName: "🦊".repeat(12) }).aps.alert).toEqual({
      title: "🔒".repeat(20),
      body: `${"🦊".repeat(12)} is locking in 🔒`,
    });
  });

  test("joining an open room alerts nobody, and neither does a solo session", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(ava, 0);
    await register(noor, 1);
    await register(kai, 2);
    const sid = await lockIn(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1), phone(2)]);
    app.apns.clear();

    expect((await call(noor, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id).toBe(sid);
    expect((await call(kai, "POST", `/sessions/${sid}/join`, { minutes: 50 })).status).toBe(200);
    expect(app.background).toHaveLength(0);
    await app.settle();
    expect(alerts()).toHaveLength(0);

    await call(ava, "POST", `/sessions/${sid}/end`);
    await call(noor, "POST", `/sessions/${sid}/end`);
    await call(kai, "POST", `/sessions/${sid}/end`);
    app.clock.now += SQUAD_ALERT_INTERVAL_SECONDS;
    expect((await call(ava, "POST", "/sessions", { minutes: 25 })).status).toBe(200);
    expect(app.background).toHaveLength(0);
    expect(alerts()).toHaveLength(0);
  });

  test("not muted members, nobody blocked either way, nobody already in a session", async () => {
    const mila = await app.user("mila", "Mila");
    const zed = await app.user("zed", "Zed");
    const lea = await app.user("lea", "Lea");
    plus();
    const squadId = await squad(ava, "Library Goblins", noor, kai, mila, zed, lea);
    for (const [index, who] of [noor, kai, mila, zed, lea].entries()) await register(who, index + 1);

    expect((await call(noor, "PATCH", `/squads/${squadId}/members/me`, { muted: true })).status).toBe(200);
    expect((await call(kai, "POST", "/blocks", { userId: ava.user.id })).status).toBe(204);
    expect((await call(ava, "POST", "/blocks", { userId: mila.user.id })).status).toBe(204);
    const solo = (await call(zed, "POST", "/sessions", { minutes: 25 })).body.session.id;

    const sid = await lockIn(ava, squadId);
    expect(alertedPhones()).toEqual([phone(5)]);
    expect(alertRows().map((row) => row.recipient_id)).toEqual([lea.user.id]);
    expect(logs).toContain(`alerts ${sid}: 1 alerted, 0 in quiet hours, 0 over a limit; 1 pushes accepted, 0 refused, 0 failed, 0 devices removed`);

    // Zed's session over, mute off and the block lifted: the next room tells them.
    await call(zed, "POST", `/sessions/${solo}/end`);
    await call(noor, "PATCH", `/squads/${squadId}/members/me`, { muted: false });
    await call(kai, "DELETE", `/blocks/${ava.user.id}`);
    await call(ava, "POST", `/sessions/${sid}/end`);
    app.apns.clear();
    app.clock.now += SQUAD_ALERT_INTERVAL_SECONDS;
    await lockIn(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1), phone(2), phone(4), phone(5)]);
  });
});

describe("quiet hours", () => {
  test("22:00–07:00 by default, in each phone's own time zone", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(noor, 1, { tz: "Australia/Sydney" });
    await register(kai, 2, { tz: "America/Los_Angeles" });

    // T0 is 04:46 in Sydney and 10:46 in Los Angeles.
    const first = await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(2)]);
    expect(logs).toContain(`alerts ${first}: 1 alerted, 1 in quiet hours, 0 over a limit; 1 pushes accepted, 0 refused, 0 failed, 0 devices removed`);

    // 21:59 in Sydney, 03:59 in Los Angeles.
    app.apns.clear();
    app.clock.now = at("10:59");
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1)]);

    // 22:30 in Sydney, 04:30 in Los Angeles (and 30 minutes on, so no limit is in the way): both asleep.
    app.apns.clear();
    app.clock.now = at("11:00") + SQUAD_ALERT_INTERVAL_SECONDS;
    const asleep = await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([]);
    expect(logs).toContain(`alerts ${asleep}: 0 alerted, 2 in quiet hours, 0 over a limit; 0 pushes accepted, 0 refused, 0 failed, 0 devices removed`);

    // 07:00 in Sydney, 13:00 in Los Angeles: both awake.
    app.clock.now = at("20:00");
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1), phone(2)]);
  });

  test("a phone's own quiet hours, or none at all", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    // 09:00–17:00 in Los Angeles (10:46 at T0): quiet. None in Sydney (04:46): told.
    await register(noor, 1, { quietHours: { start: 9 * 60, end: 17 * 60 } });
    await register(kai, 2, { tz: "Australia/Sydney", quietHours: null });
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(2)]);
  });

  test("only the phones that are awake; a recipient with none awake isn't charged against the limits", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(noor, 1, { tz: "Australia/Sydney" });
    await register(noor, 2, { tz: "America/Los_Angeles" });
    await register(kai, 3, { tz: "Australia/Sydney" });
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(2)]);
    expect(alertRows().map((row) => row.recipient_id)).toEqual([noor.user.id]);

    // Kai's phone turns quiet hours off. Well inside 30 minutes, Kai can still be told: the alert
    // they slept through didn't count.
    app.apns.clear();
    app.clock.now += 5 * 60;
    await register(kai, 3, { tz: "Australia/Sydney", quietHours: null });
    const sid = await openAndEnd(noor, squadId);
    expect(alertedPhones()).toEqual([phone(3)]);
    expect(logs).toContain(`alerts ${sid}: 1 alerted, 0 in quiet hours, 0 over a limit; 1 pushes accepted, 0 refused, 0 failed, 0 devices removed`);
  });

  test("local time, across midnight, in any zone", () => {
    expect(localMinute("Australia/Sydney", T0)).toBe(4 * 60 + 46);
    expect(localMinute("America/Los_Angeles", T0)).toBe(10 * 60 + 46);
    expect(localMinute("UTC", T0)).toBe(17 * 60 + 46);
    expect(localMinute("Asia/Kolkata", T0)).toBe(23 * 60 + 16);
    expect(localMinute("Australia/Sydney", at("13:00"))).toBe(0);
    // Sydney moved its clocks on 4 October: 11:00 UTC was 21:00 the day before, 22:00 after.
    expect(localMinute("Australia/Sydney", Date.parse("2026-10-03T11:00:00Z") / 1000)).toBe(21 * 60);
    expect(localMinute("Australia/Sydney", at("11:00"))).toBe(22 * 60);
    // A zone the runtime doesn't know (POST /devices only checks the shape) counts as UTC.
    expect(localMinute("Mars/Olympus_Mons", T0)).toBe(17 * 60 + 46);

    const sydney = { tz: "Australia/Sydney", quiet_start: 1320, quiet_end: 420 };
    const losAngeles = { tz: "America/Los_Angeles", quiet_start: 1320, quiet_end: 420 };
    const cases: Array<[string, boolean, boolean]> = [
      ["10:59", false, true], // 21:59 Sydney, 03:59 LA
      ["11:00", true, true], // 22:00, 04:00
      ["13:59", true, true], // 00:59, 06:59
      ["14:00", true, false], // 01:00, 07:00
      ["19:59", true, false], // 06:59, 12:59
      ["20:00", false, false], // 07:00, 13:00
      ["04:59", false, false], // 15:59, 21:59
      ["05:00", false, true], // 16:00, 22:00
    ];
    for (const [time, quietInSydney, quietInLosAngeles] of cases) {
      expect(deviceIsQuiet(sydney, at(time)), `${time} Sydney`).toBe(quietInSydney);
      expect(deviceIsQuiet(losAngeles, at(time)), `${time} LA`).toBe(quietInLosAngeles);
    }
    expect(deviceIsQuiet({ tz: "Australia/Sydney", quiet_start: null, quiet_end: null }, at("13:00"))).toBe(false);

    // Same day: from start up to, not including, end.
    expect([539, 540, 1019, 1020].map((minute) => inQuietHours({ start: 540, end: 1020 }, minute))).toEqual([false, true, true, false]);
    expect([0, 1438, 1439].map((minute) => inQuietHours({ start: 1439, end: 0 }, minute))).toEqual([false, false, true]);
    expect([isQuietHours({ start: 0, end: 1439 }), isQuietHours({ start: 5, end: 5 }), isQuietHours({ start: 0, end: 1440 })]).toEqual([true, false, false]);
  });
});

describe("limits", () => {
  test("one per squad per recipient every 30 minutes", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(ava, 0);
    await register(noor, 1);
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1)]);

    // Kai opens 29:59 later: Ava hears, Noor doesn't.
    app.apns.clear();
    app.clock.now = T0 + SQUAD_ALERT_INTERVAL_SECONDS - 1;
    const second = await openAndEnd(kai, squadId);
    expect(alertedPhones()).toEqual([phone(0)]);
    expect(logs).toContain(`alerts ${second}: 1 alerted, 0 in quiet hours, 1 over a limit; 1 pushes accepted, 0 refused, 0 failed, 0 devices removed`);

    // 30 minutes after hers, Noor can be told again.
    app.apns.clear();
    app.clock.now = T0 + SQUAD_ALERT_INTERVAL_SECONDS;
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1)]);
  });

  test("six a day per recipient across squads, in a rolling 24 hours", async () => {
    plus();
    const goblins = await squad(ava, "Library Goblins", noor);
    const owls = await squad(kai, "Night Owls", noor);
    await register(noor, 1);
    // Alternating squads every 16 minutes keeps each under its 30-minute limit.
    for (let index = 0; index < 6; index++) {
      app.clock.now = T0 + index * 16 * 60;
      await openAndEnd(index % 2 === 0 ? ava : kai, index % 2 === 0 ? goblins : owls);
    }
    expect(alerts()).toHaveLength(6);
    expect(new Set(alertRows().map((row) => row.squad_id))).toEqual(new Set([goblins, owls]));

    app.clock.now = T0 + 6 * 16 * 60;
    const seventh = await openAndEnd(ava, goblins);
    expect(alerts()).toHaveLength(6);
    expect(logs).toContain(`alerts ${seventh}: 0 alerted, 0 in quiet hours, 1 over a limit; 0 pushes accepted, 0 refused, 0 failed, 0 devices removed`);

    // A day after the first, it no longer counts.
    app.clock.now = T0 + DAILY_ALERT_WINDOW_SECONDS - 1;
    await openAndEnd(ava, goblins);
    expect(alerts()).toHaveLength(6);
    app.clock.now = T0 + DAILY_ALERT_WINDOW_SECONDS;
    await openAndEnd(kai, owls);
    expect(alerts()).toHaveLength(7);
  });

  test("an opener who opened another room in the squad in the last 10 minutes alerts nobody", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(ava, 0);
    await register(noor, 1);
    await register(kai, 2);
    // Noor's busy when Ava first opens, so only Kai hears.
    const solo = (await call(noor, "POST", "/sessions", { minutes: 25 })).body.session.id;
    await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(2)]);
    await call(noor, "POST", `/sessions/${solo}/end`);

    // Open, end, open again: nobody hears it twice, not even Noor, who hasn't heard it once.
    app.apns.clear();
    app.clock.now = T0 + 120;
    const again = await openAndEnd(ava, squadId);
    expect(alerts()).toHaveLength(0);
    expect(logs).toContain(`alerts ${again}: none sent (the opener opened another room in the last 10 minutes)`);

    // It's per opener: Kai opening tells Ava and Noor.
    app.clock.now = T0 + 240;
    await openAndEnd(kai, squadId);
    expect(alertedPhones()).toEqual([phone(0), phone(1)]);

    // Silenced until 10 minutes after Ava's last room; then the limits apply as usual (everyone has
    // been told within 30 minutes).
    const lastOpen = T0 + 120 + REOPEN_SILENCE_SECONDS - 1;
    app.clock.now = lastOpen;
    const silenced = await openAndEnd(ava, squadId);
    expect(logs).toContain(`alerts ${silenced}: none sent (the opener opened another room in the last 10 minutes)`);
    app.clock.now = lastOpen + REOPEN_SILENCE_SECONDS;
    const limited = await openAndEnd(ava, squadId);
    expect(logs).toContain(`alerts ${limited}: 0 alerted, 0 in quiet hours, 2 over a limit; 0 pushes accepted, 0 refused, 0 failed, 0 devices removed`);
  });

  test("the log keeps two days", async () => {
    const squadId = await squad(ava, "Library Goblins", noor);
    await register(noor, 1);
    const insert = app.sqlite.prepare("INSERT INTO alerts (recipient_id, squad_id, sender_id, session_id, sent_at) VALUES (?, ?, ?, 'old0000000', ?)");
    insert.run(noor.user.id, squadId, ava.user.id, T0 - ALERT_LOG_KEPT_SECONDS - 1);
    insert.run(noor.user.id, squadId, ava.user.id, T0 - ALERT_LOG_KEPT_SECONDS);
    await openAndEnd(ava, squadId);
    expect(alertRows().map((row) => row.sent_at)).toEqual([T0 - ALERT_LOG_KEPT_SECONDS, T0]);
  });
});

describe("APNs answers", () => {
  test("410 or BadDeviceToken deletes that phone; nobody reached means nobody charged", async () => {
    const squadId = await squad(ava, "Library Goblins", noor, kai);
    await register(noor, 1);
    await register(noor, 2);
    await register(kai, 3);
    await register(kai, 4);
    app.apns.answers.set(phone(1), { status: 410, reason: "Unregistered" });
    app.apns.answers.set(phone(2), { status: 400, reason: "BadDeviceToken" });
    app.apns.answers.set(phone(3), { status: 410, reason: "Unregistered" });
    app.apns.answers.set(phone(4), { status: 429, reason: "TooManyRequests" });

    const sid = await openAndEnd(ava, squadId);
    expect(alertedPhones()).toEqual([phone(1), phone(2), phone(3), phone(4)]);
    expect(app.sqlite.prepare("SELECT apns_token FROM devices ORDER BY apns_token").all().map((row) => row.apns_token)).toEqual([phone(4)]);
    expect(alertRows()).toEqual([]);
    expect(logs).toContain(`alerts ${sid}: 0 alerted, 0 in quiet hours, 0 over a limit; 0 pushes accepted, 4 refused, 0 failed, 3 devices removed`);

    // One phone gone and one reached: reached, and charged.
    app.apns.clear();
    app.clock.now += 60;
    await register(kai, 5);
    const next = await openAndEnd(noor, squadId);
    expect(alertedPhones()).toEqual([phone(4), phone(5)]);
    expect(alertRows().map((row) => row.recipient_id)).toEqual([kai.user.id]);
    expect(logs).toContain(`alerts ${next}: 1 alerted, 0 in quiet hours, 0 over a limit; 1 pushes accepted, 1 refused, 0 failed, 0 devices removed`);
  });

  test("APNs out of reach: logged, nobody charged, and the room carries on", async () => {
    const squadId = await squad(ava, "Library Goblins", noor);
    await register(noor, 1);
    app.apns.unreachable = true;
    const sid = await lockIn(ava, squadId);
    expect(logs).toContain(`alerts ${sid}: 0 alerted, 0 in quiet hours, 0 over a limit; 0 pushes accepted, 0 refused, 1 failed, 0 devices removed`);
    expect(alertRows()).toEqual([]);
    expect(app.count("SELECT count(*) FROM devices")).toBe(1);
    expect((await call(ava, "POST", `/sessions/${sid}/pause`)).status).toBe(200);
  });

  test("D1 failing mid-way is logged, not thrown", async () => {
    const squadId = await squad(ava, "Library Goblins", noor);
    await register(noor, 1);
    app.sqlite.exec("DROP TABLE alerts");
    const sid = await lockIn(ava, squadId);
    expect(logs).toContain(`alerts ${sid}: failed (Error)`);
  });

  test("without the APNs secrets nothing is sent, the routes work, and the isolate says so once", async () => {
    // The only test in this file without them: the warning is once per isolate (per test file).
    const quiet = await testApp({ APNS_KEY_ID: undefined, APNS_PRIVATE_KEY: undefined });
    const [owner, member] = [await quiet.user("ava", "Ava"), await quiet.user("noor", "Noor")];
    const created = await read(await quiet.request("POST", "/squads", { token: owner.token, body: { name: "Library Goblins" } }));
    const squadId = created.body.squad.id;
    const code = (await read(await quiet.request("POST", `/squads/${squadId}/invite`, { token: owner.token }))).body.code;
    await quiet.request("POST", `/squads/join/${code}`, { token: member.token });
    const device = { apnsToken: phone(1), env: "production", laEnabled: true, frequentPushes: false, tz: "UTC", quietHours: null };
    expect((await quiet.request("POST", "/devices", { token: member.token, body: device })).status).toBe(204);

    for (let round = 0; round < 2; round++) {
      quiet.clock.now = T0 + round * SQUAD_ALERT_INTERVAL_SECONDS;
      const opened = await read(await quiet.request("POST", "/sessions", { token: owner.token, body: { squadId, minutes: 25 } }));
      expect(opened.status).toBe(200);
      await quiet.settle();
      expect((await quiet.request("POST", `/sessions/${opened.body.session.id}/end`, { token: owner.token })).status).toBe(200);
    }
    expect(quiet.apns.requests).toHaveLength(0);
    expect(quiet.count("SELECT count(*) FROM alerts")).toBe(0);
    expect(logs.filter((line) => line.startsWith("push: "))).toEqual([
      "push: APNs isn't set up (APNS_KEY_ID, APNS_PRIVATE_KEY missing), so squad alerts and push-to-start are off (server/README.md)",
    ]);
  });
});
