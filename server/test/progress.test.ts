// M5 through the whole Worker: coins and XP credited when timers stop (exactly once), the egg
// hatching, stages, moods, streak days in the squad's time zone, and the weekly leaderboard. Real
// SQL on an in-memory D1, the rooms on the fake Durable Objects runtime, a clock the tests move.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { startOfDay } from "../src/days.ts";
import { COALESCE_SECONDS, D1_RETRY_SECONDS } from "../src/room.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";
import { JWT_IN_LOG } from "./helpers.ts";
import { laToken } from "./rooms.ts";

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
  // Room ids and counts only: never who, never a token.
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toMatch(/\b(ava|noor|kai|mila|Ava|Noor|Kai|Mila|Library Goblins)\b/);
    expect(line).not.toMatch(JWT_IN_LOG);
  }
});

const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));
const plus = (who: SignedIn) => app.sqlite.prepare("UPDATE users SET plus_until = ? WHERE id = ?").run(T0 + 365 * DAY, who.user.id);
const coins = (who: SignedIn) => app.value("SELECT coins FROM users WHERE id = ?", who.user.id);
const column = (squadId: string, name: string) => app.value(`SELECT ${name} FROM squads WHERE id = ?`, squadId);

/** A squad owned by `owner` with `members` joined by code, in that order. */
async function squad(owner: SignedIn, members: SignedIn[] = [], extra: Record<string, unknown> = {}, name = "Library Goblins"): Promise<string> {
  const created = await call(owner, "POST", "/squads", { name, ...extra });
  expect(created.status, JSON.stringify(created.body)).toBe(200);
  const id = created.body.squad.id as string;
  const code = (await call(owner, "POST", `/squads/${id}/invite`)).body.code as string;
  for (const member of members) expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
  return id;
}

async function start(who: SignedIn, body: Record<string, unknown>): Promise<string> {
  const response = await call(who, "POST", "/sessions", body);
  expect(response.status, JSON.stringify(response.body)).toBe(200);
  return response.body.session.id as string;
}

async function upload(who: SignedIn, sid: string, seed: number) {
  expect((await call(who, "POST", `/sessions/${sid}/la-token`, { token: laToken(seed), env: "production" })).status).toBe(204);
}

/** A solo session of `minutes`, run to the end. */
async function solo(who: SignedIn, minutes: number): Promise<string> {
  const sid = await start(who, { minutes });
  await app.advance(minutes * MINUTE);
  return sid;
}

async function mySquad(who: SignedIn, squadId: string) {
  const { body } = await call(who, "GET", "/squads");
  return body.squads.find((each: { id: string }) => each.id === squadId);
}

const stateOf = async (who: SignedIn, sid: string) => (await call(who, "GET", `/sessions/${sid}`)).body.contentState;

/** Makes D1's next `count` batches fail as if the network dropped, before or after they ran. */
function breakD1(count: number, when: "before" | "after" = "before") {
  const batch = app.d1.batch.bind(app.d1);
  let left = count;
  app.d1.batch = async (statements) => {
    if (left <= 0) return batch(statements);
    left -= 1;
    if (when === "after") await batch(statements);
    throw new Error("D1_ERROR: Network connection lost.");
  };
}

describe("coins", () => {
  test("a finished session earns a coin a minute and 5 for finishing, solo too", async () => {
    const sid = await solo(ava, 25);
    expect(coins(ava)).toBe(30);
    expect((await call(ava, "GET", "/me")).body.user.coins).toBe(30);
    expect({ ...(app.sqlite.prepare("SELECT * FROM focus_log").get() as object) }).toEqual({
      session_id: sid,
      user_id: ava.user.id,
      started_at: T0,
      ended_at: T0 + 25 * MINUTE,
      squad_id: null,
      focused_sec: 1500,
      completed: 1,
      coins: 30,
      xp: 0,
    });
    // The room going on (its end push, its clean-up a day later) credits nothing more.
    await app.advance(2 * DAY);
    expect(coins(ava)).toBe(30);
  });

  test("leaving early earns the whole minutes so far, without the bonus; a slip too; paused time doesn't count", async () => {
    let sid = await start(ava, { minutes: 25 });
    await app.advance(10 * MINUTE + 59);
    await call(ava, "POST", `/sessions/${sid}/end`);
    expect(coins(ava)).toBe(10);

    sid = await start(ava, { minutes: 25 });
    await app.advance(5 * MINUTE);
    await call(ava, "POST", `/sessions/${sid}/slip`);
    expect(coins(ava)).toBe(15);

    sid = await start(ava, { minutes: 25 });
    await app.advance(5 * MINUTE);
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await app.advance(10 * MINUTE);
    await call(ava, "POST", `/sessions/${sid}/resume`);
    await app.advance(20 * MINUTE);
    expect(coins(ava)).toBe(15 + 25 + 5);
    expect(app.count("SELECT count(*) FROM focus_log WHERE user_id = ?", ava.user.id)).toBe(3);
  });

  test("credited once when D1 fails and the room writes again", async () => {
    const squadId = await squad(ava, [noor]);
    const sid = await start(ava, { squadId, minutes: 25 });
    // Noor keeps the room open: an ended room writes again at once.
    await start(noor, { squadId, minutes: 50 });
    breakD1(1);
    await app.advance(25 * MINUTE);
    expect(logs).toContain(`room ${sid}: D1 write failed (Error), trying again in ${D1_RETRY_SECONDS} s`);
    expect(coins(ava)).toBe(0);
    await app.advance(D1_RETRY_SECONDS);
    expect(coins(ava)).toBe(30);
    expect(column(squadId, "pet_xp")).toBe(25);
    await app.advance(DAY);
    expect(coins(ava)).toBe(30);
  });

  test("credited once when a write went through but the room didn't hear, however often it tries", async () => {
    const squadId = await squad(ava, [noor]);
    const sid = await start(ava, { squadId, minutes: 25 });
    await start(noor, { squadId, minutes: 25 });
    breakD1(3, "after");
    await app.advance(25 * MINUTE);
    await app.advance(5 * D1_RETRY_SECONDS);
    expect(logs.filter((line) => line.startsWith(`room ${sid}: D1 write failed`)).length).toBeGreaterThanOrEqual(3);
    expect(coins(ava)).toBe(30);
    expect(coins(noor)).toBe(30);
    expect(column(squadId, "pet_xp")).toBe(50);
    expect(app.count("SELECT count(*) FROM focus_log")).toBe(2);
    expect(app.count("SELECT count(*) FROM participants WHERE ended_at IS NULL")).toBe(0);
  });

  test("survives the room being evicted between the stop and the write", async () => {
    const sid = await start(ava, { minutes: 25 });
    breakD1(1);
    await app.advance(25 * MINUTE);
    app.rooms.evict(sid);
    await app.advance(D1_RETRY_SECONDS);
    expect(coins(ava)).toBe(30);
  });

  test("joining a room again after finishing earns again, each timer once", async () => {
    const squadId = await squad(ava, [noor]);
    const sid = await start(ava, { squadId, minutes: 25 });
    await start(noor, { squadId, minutes: 60 });
    await app.advance(25 * MINUTE);
    expect(coins(ava)).toBe(30);
    expect(await start(ava, { squadId, minutes: 25 })).toBe(sid);
    await app.advance(3 * MINUTE + 30);
    await call(ava, "POST", `/sessions/${sid}/end`);
    expect(coins(ava)).toBe(33);
    expect(app.count("SELECT count(*) FROM focus_log WHERE session_id = ? AND user_id = ?", sid, ava.user.id)).toBe(2);
  });

  test("a member whose account is deleted before the room could write leaves nothing behind", async () => {
    const squadId = await squad(ava, [noor, kai]);
    const sid = await start(ava, { squadId, minutes: 25 });
    await start(noor, { squadId, minutes: 25 });
    await start(kai, { squadId, minutes: 90 });
    breakD1(1);
    await app.advance(25 * MINUTE);
    expect((await app.request("DELETE", "/me", { token: noor.token })).status).toBe(204);
    await app.advance(D1_RETRY_SECONDS);
    expect(coins(ava)).toBe(30);
    expect(column(squadId, "pet_xp")).toBe(25);
    expect(app.count("SELECT count(*) FROM focus_log WHERE session_id = ?", sid)).toBe(1);
  });
});

describe("the pet", () => {
  test("is an egg of its species from the start; XP adds up; two finishing in one room hatch it", async () => {
    const squadId = await squad(ava, [noor, kai]);
    const species = column(squadId, "pet_species") as string;
    const sid = await start(ava, { squadId, minutes: 25 });
    await upload(ava, sid, 1);
    expect((await stateOf(ava, sid)).p).toEqual({ k: `${species}.0`, md: 1, x: 0 });
    app.clock.now = T0 + MINUTE;
    await start(noor, { squadId, minutes: 50 });
    await start(kai, { squadId, minutes: 90 });

    // Ava finishes: 25 XP, still an egg; today's mood is content (one of the two needed).
    await app.advance(24 * MINUTE + COALESCE_SECONDS);
    expect(column(squadId, "pet_xp")).toBe(25);
    expect(column(squadId, "hatched_at")).toBeNull();
    expect((await stateOf(ava, sid)).p).toEqual({ k: `${species}.0`, md: 2, x: 0 });
    expect((await mySquad(ava, squadId)).pet).toEqual({ species: expect.any(String), stage: 0, xp: 25, mood: 2, progress: 0 });

    // Noor finishes: two have, so it hatches, and today counts.
    app.apns.clear();
    await app.advance(26 * MINUTE);
    const hatchedAt = T0 + MINUTE + 50 * MINUTE;
    expect(column(squadId, "hatched_at")).toBe(hatchedAt);
    expect(column(squadId, "pet_xp")).toBe(75);
    expect(column(squadId, "pet_stage")).toBe(1);
    expect((await stateOf(ava, sid)).p).toEqual({ k: `${species}.1`, md: 3, x: 0.13 });
    expect((await mySquad(noor, squadId)).pet).toEqual({ species, stage: 1, xp: 75, mood: 3, progress: 0.125 });
    const [push] = app.apns.requests;
    expect(push?.priority).toBe(10);
    expect(push?.aps["content-state"].p).toEqual({ k: `${species}.1`, md: 3, x: 0.13 });
  });

  test("a hatch the room only hears of later (D1 was down) is pushed at priority 10", async () => {
    const squadId = await squad(ava, [noor, kai]);
    const species = column(squadId, "pet_species") as string;
    const sid = await start(kai, { squadId, minutes: 90 });
    await upload(kai, sid, 3);
    await start(ava, { squadId, minutes: 25 });
    await start(noor, { squadId, minutes: 30 });
    await app.advance(26 * MINUTE);
    breakD1(1);
    await app.advance(4 * MINUTE + COALESCE_SECONDS);
    expect(column(squadId, "hatched_at")).toBeNull();
    app.apns.clear();
    await app.advance(D1_RETRY_SECONDS + COALESCE_SECONDS);
    expect(column(squadId, "hatched_at")).toBe(T0 + 30 * MINUTE);
    expect(app.apns.requests.map((request) => [request.priority, request.aps["content-state"].p.k])).toEqual([[10, `${species}.1`]]);
  });

  test("doesn't hatch from finishes in different rooms, or one member finishing twice", async () => {
    const squadId = await squad(ava, [noor]);
    await solo(ava, 25);
    await solo(noor, 25);
    expect(column(squadId, "hatched_at")).toBeNull();
    // Solo sessions are no squad's: no XP.
    expect(column(squadId, "pet_xp")).toBe(0);

    const sid = await start(ava, { squadId, minutes: 25 });
    await start(noor, { squadId, minutes: 90 });
    await app.advance(25 * MINUTE);
    await start(ava, { squadId, minutes: 25 });
    await app.advance(25 * MINUTE);
    await call(noor, "POST", `/sessions/${sid}/end`);
    expect(column(squadId, "hatched_at")).toBeNull();
    expect(column(squadId, "pet_xp")).toBe(50 + 50);
    expect((await mySquad(ava, squadId)).pet).toMatchObject({ species: expect.any(String), stage: 0, xp: 100 });
  });

  test("grows with XP: the stage is the highest whose XP it has", async () => {
    const squadId = await squad(ava, [noor]);
    app.sqlite.prepare("UPDATE squads SET pet_xp = 590, pet_stage = 1, hatched_at = ? WHERE id = ?").run(T0 - DAY, squadId);
    const species = column(squadId, "pet_species");
    const sid = await start(ava, { squadId, minutes: 25 });
    await start(noor, { squadId, minutes: 25 });
    expect((await stateOf(ava, sid)).p).toEqual({ k: `${species}.1`, md: 1, x: 0.98 });
    await app.advance(25 * MINUTE);
    // 640: a teen, 40 of the 2,400 to adult.
    expect(column(squadId, "pet_xp")).toBe(640);
    expect(column(squadId, "pet_stage")).toBe(2);
    expect((await stateOf(ava, sid)).p).toEqual({ k: `${species}.2`, md: 3, x: 0.02 });
    expect((await mySquad(ava, squadId)).pet).toEqual({ species, stage: 2, xp: 640, mood: 3, progress: 40 / 2400 });
  });

  test("an early leave or a slip makes it sad for 30 minutes; then the mood comes back by itself, at priority 5", async () => {
    const squadId = await squad(ava, [noor, kai]);
    const sid = await start(ava, { squadId, minutes: 90 });
    await upload(ava, sid, 1);
    await start(noor, { squadId, minutes: 25 });
    await app.advance(5 * MINUTE);
    await call(noor, "POST", `/sessions/${sid}/end`);
    expect(column(squadId, "last_sad_at")).toBe(T0 + 5 * MINUTE);
    expect((await stateOf(ava, sid)).p.md).toBe(0);
    expect((await mySquad(ava, squadId)).pet.mood).toBe(0);
    await app.advance(COALESCE_SECONDS);

    app.apns.clear();
    await app.advance(30 * MINUTE);
    expect(app.apns.requests.map((request) => [request.priority, request.aps["content-state"].p.md])).toEqual([[5, 1]]);
    expect((await mySquad(ava, squadId)).pet.mood).toBe(1);

    // A slip does it too, from the slip.
    await start(kai, { squadId, minutes: 25 });
    await app.advance(MINUTE);
    await call(kai, "POST", `/sessions/${sid}/slip`);
    expect(column(squadId, "last_sad_at")).toBe(app.clock.now);
    expect((await stateOf(ava, sid)).p.md).toBe(0);
  });

  test("sad is about the squad's own rooms: a solo early leave doesn't count", async () => {
    const squadId = await squad(ava, [noor]);
    const sid = await start(ava, { minutes: 25 });
    await app.advance(5 * MINUTE);
    await call(ava, "POST", `/sessions/${sid}/end`);
    expect(column(squadId, "last_sad_at")).toBeNull();
    expect((await mySquad(ava, squadId)).pet.mood).toBe(1);
  });

  test("today's mood: hungry, content once someone finished, happy once half the squad has; other rooms hear at once", async () => {
    const squadId = await squad(ava, [noor, kai]);
    const sid = await start(kai, { squadId, minutes: 120 });
    await upload(kai, sid, 3);
    expect((await stateOf(kai, sid)).p.md).toBe(1);

    // Ava finishes alone: content, in the squad's room too, pushed at 5.
    app.apns.clear();
    await solo(ava, 25);
    await app.advance(COALESCE_SECONDS);
    expect((await stateOf(kai, sid)).p.md).toBe(2);
    expect(app.apns.to(laToken(3)).map((request) => [request.priority, request.aps["content-state"].p.md])).toEqual([[5, 2]]);
    expect((await mySquad(kai, squadId)).streak).toEqual({ count: 0, countedToday: false, doneToday: 1, needed: 2 });

    // Noor too: two of three, so today counts.
    await solo(noor, 20);
    await app.advance(COALESCE_SECONDS);
    expect((await stateOf(kai, sid)).p.md).toBe(3);
    expect((await mySquad(kai, squadId)).streak).toEqual({ count: 1, countedToday: true, doneToday: 2, needed: 2 });
  });

  test("a session under 20 minutes feeds it but doesn't count for the streak", async () => {
    const squadId = await squad(ava, [noor]);
    await solo(ava, 19);
    expect(await mySquad(ava, squadId)).toMatchObject({
      pet: { mood: 2 },
      streak: { count: 0, countedToday: false, doneToday: 0, needed: 1 },
    });
  });

  test("a squad from before M5 gets its species on first read, egg included", async () => {
    const squadId = await squad(ava, [noor]);
    app.sqlite.prepare("UPDATE squads SET pet_species = NULL WHERE id = ?").run(squadId);
    const read = (await mySquad(ava, squadId)).pet;
    const species = column(squadId, "pet_species");
    expect(["puff", "sprout", "ember", "pebble"]).toContain(species);
    expect(read).toMatchObject({ species, stage: 0 });
    await mySquad(noor, squadId);
    expect(column(squadId, "pet_species")).toBe(species);

    app.sqlite.prepare("UPDATE squads SET pet_species = NULL WHERE id = ?").run(squadId);
    const sid = await start(ava, { squadId, minutes: 25 });
    expect((await stateOf(ava, sid)).p.k).toBe(`${column(squadId, "pet_species")}.0`);
  });
});

describe("streaks", () => {
  /** Puts the clock at `hour` o'clock UTC on `day`. */
  const at = (day: string, hour: number) => {
    app.clock.now = startOfDay("UTC", day) + hour * HOUR;
  };

  test("a day counts once; each counted day after yesterday's adds one; a missed day breaks it", async () => {
    const squadId = await squad(ava, [noor]);
    const streak = async () => (await mySquad(ava, squadId)).streak;

    await solo(ava, 20);
    expect(await streak()).toEqual({ count: 1, countedToday: true, doneToday: 1, needed: 1 });
    expect([column(squadId, "streak_count"), column(squadId, "streak_last_day")]).toEqual([1, "2026-10-14"]);
    await solo(noor, 25);
    expect(await streak()).toMatchObject({ count: 1, doneToday: 2 });

    at("2026-10-15", 9);
    await solo(noor, 20);
    expect(await streak()).toMatchObject({ count: 2, countedToday: true });

    // The next day it's still alive, just not counted yet.
    at("2026-10-16", 23);
    expect(await streak()).toEqual({ count: 2, countedToday: false, doneToday: 0, needed: 1 });
    expect((await mySquad(ava, squadId)).pet.mood).toBe(1);

    // The 16th went by without one: broken.
    at("2026-10-17", 8);
    expect(await streak()).toMatchObject({ count: 0, countedToday: false });
    await solo(ava, 30);
    expect(await streak()).toMatchObject({ count: 1, countedToday: true });
    expect(column(squadId, "streak_last_day")).toBe("2026-10-17");
  });

  test("solo and squad sessions both count, by half the squad rounded up", async () => {
    const squadId = await squad(ava, [noor, kai]);
    await solo(ava, 25);
    expect((await mySquad(ava, squadId)).streak).toMatchObject({ count: 0, doneToday: 1, needed: 2 });
    const sid = await start(noor, { squadId, minutes: 20 });
    await app.advance(20 * MINUTE);
    expect((await mySquad(ava, squadId)).streak).toMatchObject({ count: 1, countedToday: true, doneToday: 2 });
    expect(app.value("SELECT squad_id FROM focus_log WHERE session_id = ?", sid)).toBe(squadId);
  });

  test("days are the squad's own: Sydney and Los Angeles count the same finishes on different days", async () => {
    plus(ava);
    const sydney = await squad(ava, [], { tz: "Australia/Sydney" }, "Sydney");
    const angeles = await squad(ava, [], { tz: "America/Los_Angeles" }, "Angeles");

    // Ends at 05:06 on Thursday the 15th in Sydney, 11:06 on Wednesday the 14th in Los Angeles.
    await solo(ava, 20);
    expect([column(sydney, "streak_last_day"), column(angeles, "streak_last_day")]).toEqual(["2026-10-15", "2026-10-14"]);

    // Fourteen hours later: 19:26 the same Thursday in Sydney, but 01:26 the next day in Los Angeles.
    app.clock.now = T0 + 14 * HOUR;
    await solo(ava, 20);
    expect((await mySquad(ava, sydney)).streak).toMatchObject({ count: 1, countedToday: true });
    expect((await mySquad(ava, angeles)).streak).toMatchObject({ count: 2, countedToday: true });
    expect([column(sydney, "streak_last_day"), column(angeles, "streak_last_day")]).toEqual(["2026-10-15", "2026-10-15"]);

    // Saturday morning in Sydney is still Friday in Los Angeles: Sydney's streak is broken, LA's alive.
    app.clock.now = startOfDay("Australia/Sydney", "2026-10-17") + 6 * HOUR;
    expect((await mySquad(ava, sydney)).streak.count).toBe(0);
    expect((await mySquad(ava, angeles)).streak.count).toBe(2);
  });

  test("a finish written after midnight (D1 was down) counts for the day it happened", async () => {
    const squadId = await squad(ava, [noor]);
    at("2026-10-15", 9);
    await solo(ava, 20);
    at("2026-10-16", 23);
    const sid = await start(ava, { minutes: 20 });
    breakD1(1);
    await app.advance(20 * MINUTE);
    expect(logs).toContain(`room ${sid}: D1 write failed (Error), trying again in ${D1_RETRY_SECONDS} s`);
    // 23:20 on the 16th; written at 23:20:30... and still the 16th's. Then the 17th is a new day.
    await app.advance(D1_RETRY_SECONDS);
    expect([column(squadId, "streak_count"), column(squadId, "streak_last_day")]).toEqual([2, "2026-10-16"]);
  });
});

describe("the squad's time zone", () => {
  const device = (tz: string, seed: number) => ({ apnsToken: laToken(0xe0 + seed), env: "production", laEnabled: true, frequentPushes: false, tz });

  test("is sent with POST /squads, else the creator's phone's, else UTC; it follows the owner's phone", async () => {
    expect((await call(ava, "POST", "/devices", device("Australia/Sydney", 1))).status).toBe(204);
    const avas = await squad(ava);
    const noors = await squad(noor, [], { tz: "America/Los_Angeles" });
    const kais = await squad(kai);
    expect([column(avas, "tz"), column(noors, "tz"), column(kais, "tz")]).toEqual(["Australia/Sydney", "America/Los_Angeles", "UTC"]);
    expect((await mySquad(ava, avas)).tz).toBe("Australia/Sydney");

    // Kai joins Ava's squad and registers in London: only the owner's phone moves the squad.
    const code = (await call(ava, "POST", `/squads/${avas}/invite`)).body.code;
    plus(kai);
    await call(kai, "POST", `/squads/join/${code}`);
    await call(kai, "POST", "/devices", device("Europe/London", 2));
    expect(column(avas, "tz")).toBe("Australia/Sydney");
    expect(column(kais, "tz")).toBe("Europe/London");
    await call(ava, "POST", "/devices", device("Asia/Tokyo", 1));
    expect(column(avas, "tz")).toBe("Asia/Tokyo");
  });

  test("422 tz_invalid for something that isn't a zone name", async () => {
    for (const tz of ["Not a zone!", 42, "x".repeat(65)]) {
      expect(await call(ava, "POST", "/squads", { name: "Goblins", tz })).toEqual({ status: 422, body: { error: expect.any(String), code: "tz_invalid" } });
    }
    expect(app.count("SELECT count(*) FROM squads")).toBe(0);
  });
});

describe("GET /squads/:id/leaderboard", () => {
  test("this week's minutes and finished sessions for every member, most minutes first, ties by name", async () => {
    const mila = await app.user("mila", "Mila");
    const squadId = await squad(ava, [noor, kai, mila]);
    await solo(ava, 25);
    let sid = await start(noor, { minutes: 25 });
    await app.advance(10 * MINUTE + 30);
    await call(noor, "POST", `/sessions/${sid}/end`);
    sid = await start(mila, { squadId, minutes: 10 });
    await app.advance(10 * MINUTE);

    const weekStart = "2026-10-12";
    const expected = {
      weekStart,
      startsAt: startOfDay("UTC", weekStart),
      endsAt: startOfDay("UTC", "2026-10-19"),
      entries: [
        { userId: ava.user.id, minutes: 25, sessions: 1 },
        { userId: mila.user.id, minutes: 10, sessions: 1 },
        { userId: noor.user.id, minutes: 10, sessions: 0 },
        { userId: kai.user.id, minutes: 0, sessions: 0 },
      ],
    };
    expect(await call(kai, "GET", `/squads/${squadId}/leaderboard`)).toEqual({ status: 200, body: expected });
    expect((await call(kai, "GET", `/squads/${squadId}/leaderboard?week=2026-10-18`)).body).toEqual(expected);
    // Last week: everyone, nothing.
    const last = (await call(kai, "GET", `/squads/${squadId}/leaderboard?week=2026-10-11`)).body;
    expect(last.weekStart).toBe("2026-10-05");
    expect(last.entries.map((entry: { minutes: number }) => entry.minutes)).toEqual([0, 0, 0, 0]);
  });

  test("weeks run Monday to Monday in the squad's zone: it resets for the whole squad at once", async () => {
    plus(ava);
    const sydney = await squad(ava, [], { tz: "Australia/Sydney" }, "Sydney");
    const angeles = await squad(ava, [], { tz: "America/Los_Angeles" }, "Angeles");
    const minutesIn = async (squadId: string, week: string) =>
      (await call(ava, "GET", `/squads/${squadId}/leaderboard?week=${week}`)).body.entries[0].minutes as number;

    // 23:00 on Sunday the 11th in Sydney (05:00 that Sunday in Los Angeles): 25 minutes.
    app.clock.now = startOfDay("Australia/Sydney", "2026-10-11") + 23 * HOUR;
    await solo(ava, 25);
    // 00:10 on Monday the 12th in Sydney (06:10 on Sunday in Los Angeles): 30 minutes.
    app.clock.now = startOfDay("Australia/Sydney", "2026-10-12") + 10 * MINUTE;
    await solo(ava, 30);

    expect(await minutesIn(sydney, "2026-10-11")).toBe(25);
    expect(await minutesIn(sydney, "2026-10-12")).toBe(30);
    expect(await minutesIn(angeles, "2026-10-11")).toBe(55);
    expect(await minutesIn(angeles, "2026-10-12")).toBe(0);
    // Without `week`, this week where the squad is: Monday already in Sydney, still Sunday in LA.
    expect((await call(ava, "GET", `/squads/${sydney}/leaderboard`)).body).toMatchObject({ weekStart: "2026-10-12", startsAt: startOfDay("Australia/Sydney", "2026-10-12") });
    expect((await call(ava, "GET", `/squads/${angeles}/leaderboard`)).body).toMatchObject({ weekStart: "2026-10-05", endsAt: startOfDay("America/Los_Angeles", "2026-10-12") });
  });

  test("422 week_invalid for anything but a real date; 403 not_member outside the squad", async () => {
    const squadId = await squad(ava, [noor]);
    for (const week of ["2026-02-30", "2026-10-1", "yesterday", "", "2026-10-14T00:00"]) {
      expect(await call(ava, "GET", `/squads/${squadId}/leaderboard?week=${encodeURIComponent(week)}`), week).toEqual({
        status: 422,
        body: { error: expect.any(String), code: "week_invalid" },
      });
    }
    expect((await call(kai, "GET", `/squads/${squadId}/leaderboard`)).body.code).toBe("not_member");
    expect((await call(kai, "GET", "/squads/Zz00000000/leaderboard")).body.code).toBe("not_member");
    expect((await call(kai, "GET", "/squads/nope/leaderboard")).status).toBe(403);
  });
});
