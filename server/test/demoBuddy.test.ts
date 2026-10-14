// Demo Buddy, the App Review bot (docs/launch/app-review-notes.md §3), through the whole Worker: the
// review code and its Review Squads, the bot's script in the rooms on the fake clock, "Ask Demo
// Buddy to lock in", and everything it must never do.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  DEMO_BUDDY_AVATAR,
  DEMO_BUDDY_HANDLE,
  DEMO_BUDDY_ID,
  DEMO_BUDDY_NAME,
  REVIEW_REDEMPTIONS_PER_WINDOW,
  REVIEW_REDEMPTION_WINDOW_SECONDS,
  REVIEW_SQUAD_NAME,
} from "../src/demoBuddy.ts";
import { MemberState } from "../src/liveActivity.ts";
import { moderate } from "../src/moderation.ts";
import { CHEER_SHOWN_SECONDS, COALESCE_SECONDS } from "../src/room.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";
import { JWT_IN_LOG } from "./helpers.ts";
import { type APNsRequest, laToken } from "./rooms.ts";

/** A review code as the owner would set it: 8 characters of the friend-code alphabet. */
const CODE = "RVW2PASS";
const ON = { DEMO_BUDDY_CODE: CODE, DEMO_BUDDY_ENABLED: "true" };

let app: TestApp;
let ava: SignedIn;
let noor: SignedIn;
let logs: string[];

async function setUp(env: Record<string, string> = ON) {
  app = await testApp(env);
  ava = await app.user("ava", "Ava");
  noor = await app.user("noor", "Noor");
}

beforeEach(async () => {
  logs = [];
  const capture = (...args: unknown[]) => logs.push(args.map(String).join(" "));
  vi.spyOn(console, "log").mockImplementation(capture);
  vi.spyOn(console, "warn").mockImplementation(capture);
  vi.spyOn(console, "error").mockImplementation(capture);
  await setUp();
});

afterEach(async () => {
  await app.settle();
  vi.restoreAllMocks();
  // Room ids, counts and the bot's own name only: never a person, a token or the review code.
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    expect(line).not.toMatch(/\b(ava|noor|kai|Ava|Noor|Kai|Library Goblins)\b/);
    expect(line).not.toContain(CODE);
    expect(line).not.toMatch(JWT_IN_LOG);
  }
});

const MINUTE = 60;
const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));

/** Redeems the review code: the new Review Squad's id. */
async function redeem(who: SignedIn, code = CODE): Promise<string> {
  const response = await call(who, "POST", `/squads/join/${code}`);
  expect(response.status, JSON.stringify(response.body)).toBe(200);
  return response.body.squad.id as string;
}

async function lockIn(who: SignedIn, squadId: string, minutes = 25): Promise<string> {
  const response = await call(who, "POST", "/sessions", { squadId, minutes });
  expect(response.status, JSON.stringify(response.body)).toBe(200);
  return response.body.session.id as string;
}

async function upload(who: SignedIn, sid: string, seed: number) {
  expect((await call(who, "POST", `/sessions/${sid}/la-token`, { token: laToken(seed), env: "production" })).status).toBe(204);
}

/** A phone for `who`, in UTC; quiet hours 17:00–19:00 (T0 is 17:46) unless told otherwise. */
async function register(who: SignedIn, seed: number, quietHours: unknown = { start: 17 * 60, end: 19 * 60 }) {
  const body = { apnsToken: laToken(0xa0 + seed), env: "production", laEnabled: true, frequentPushes: false, tz: "UTC", quietHours };
  expect((await call(who, "POST", "/devices", body)).status).toBe(204);
}

const stateOf = async (who: SignedIn, sid: string) => (await call(who, "GET", `/sessions/${sid}`)).body.contentState;
const bot = (state: { m: Array<{ i: string }> }) => state.m.find((member) => member.i === DEMO_BUDDY_ID);
const alerts = (): APNsRequest[] => app.apns.requests.filter((request) => request.headers["apns-push-type"] === "alert");
const livePushes = () => app.apns.requests.filter((request) => request.headers["apns-push-type"] === "liveactivity");

describe("Demo Buddy itself", () => {
  test("is a bot user made by the migration, named and drawn as src/demoBuddy.ts says, that nobody can copy", () => {
    const row = { ...(app.sqlite.prepare("SELECT * FROM users WHERE id = ?").get(DEMO_BUDDY_ID) as object) };
    expect(row).toMatchObject({
      id: DEMO_BUDDY_ID,
      apple_sub: null,
      handle: DEMO_BUDDY_HANDLE,
      display_name: DEMO_BUDDY_NAME,
      avatar_code: DEMO_BUDDY_AVATAR,
      coins: 0,
      plus_until: null,
      is_bot: 1,
    });
    // Within the Live Activity's 12 characters; the handle and both words are reserved.
    expect([...DEMO_BUDDY_NAME].length).toBeLessThanOrEqual(12);
    expect(moderate("handle", DEMO_BUDDY_HANDLE)).toBe("not_allowed");
    expect(moderate("name", DEMO_BUDDY_NAME)).toBe("not_allowed");
    expect(app.count("SELECT count(*) FROM auth_tokens WHERE user_id = ?", DEMO_BUDDY_ID)).toBe(0);
  });
});

describe("the review code", () => {
  test("makes a private Review Squad with the redeemer and Demo Buddy, labelled as a bot", async () => {
    const response = await call(ava, "POST", `/squads/join/${CODE.toLowerCase().slice(0, 4)}-${CODE.slice(4)}`);
    expect(response.status).toBe(200);
    expect(response.body.squad).toMatchObject({
      name: REVIEW_SQUAD_NAME,
      ownerId: ava.user.id,
      members: [
        { id: ava.user.id, handle: "ava", displayName: "Ava", isBot: false, joinedAt: T0 },
        { id: DEMO_BUDDY_ID, handle: DEMO_BUDDY_HANDLE, displayName: DEMO_BUDDY_NAME, avatarCode: DEMO_BUDDY_AVATAR, isBot: true, joinedAt: T0 },
      ],
      openSessionId: null,
      boosted: false,
      pet: { stage: 0 },
      // Half the squad's people: Ava alone.
      streak: { needed: 1 },
    });
    expect(app.value("SELECT review FROM squads WHERE id = ?", response.body.squad.id)).toBe(1);
    expect((await call(ava, "GET", "/squads")).body.squads[0].members.map((member: { isBot: boolean }) => member.isBot)).toEqual([false, true]);
    expect(logs).toContain("squads: review squad made");
  });

  test("makes a fresh squad every time, so reviewers never share one", async () => {
    const first = await redeem(ava);
    const second = await redeem(noor);
    app.clock.now += 1;
    const third = await redeem(ava);
    expect(new Set([first, second, third]).size).toBe(3);
    expect(app.count("SELECT count(*) FROM squad_members WHERE user_id = ?", DEMO_BUDDY_ID)).toBe(3);
    expect(app.count("SELECT count(*) FROM squad_members WHERE squad_id = ?", second)).toBe(2);
    expect((await call(ava, "GET", "/squads")).body.squads.map((squad: { id: string }) => squad.id)).toEqual([first, third]);
  });

  test("doesn't count against the squad limit: App Review never meets the paywall", async () => {
    // Already in a squad on the free plan, the code still works…
    expect((await call(noor, "POST", "/squads", { name: "Library Goblins" })).status).toBe(200);
    await redeem(noor);
    // …and a Review Squad doesn't use up the one free squad.
    await redeem(ava);
    expect((await call(ava, "POST", "/squads", { name: "Night Owls" })).status).toBe(200);
    expect((await call(ava, "POST", "/squads", { name: "Three" })).body).toMatchObject({ code: "plus_required", limit: "squads" });
    // Joining someone's Review Squad by its invite code doesn't count either.
    const review = await redeem(ava);
    const code = (await call(ava, "POST", `/squads/${review}/invite`)).body.code;
    expect((await call(noor, "POST", `/squads/join/${code}`)).status).toBe(200);
  });

  test("never expires, but works 10 times an hour for everyone together: 429 rate_limited with retryAfter", async () => {
    for (let n = 0; n < REVIEW_REDEMPTIONS_PER_WINDOW; n++) {
      app.clock.now = T0 + n * MINUTE;
      await redeem(n % 2 === 0 ? ava : noor);
    }
    app.clock.now = T0 + 30 * MINUTE;
    expect(await call(noor, "POST", `/squads/join/${CODE}`)).toEqual({
      status: 429,
      body: { error: expect.any(String), code: "rate_limited", retryAfter: REVIEW_REDEMPTION_WINDOW_SECONDS - 30 * MINUTE },
    });
    expect(app.count("SELECT count(*) FROM squads WHERE review = 1")).toBe(REVIEW_REDEMPTIONS_PER_WINDOW);
    // An hour after the first, one more goes through; a year on, it still works.
    app.clock.now = T0 + REVIEW_REDEMPTION_WINDOW_SECONDS + 1;
    await redeem(noor);
    expect((await call(noor, "POST", `/squads/join/${CODE}`)).status).toBe(429);
    app.clock.now = T0 + 365 * 86_400;
    await redeem(noor);
  });

  test("the kill switch: switched off, the code is unknown (404) and Demo Buddy stays out of rooms", async () => {
    const review = await redeem(ava);
    for (const off of [{ DEMO_BUDDY_CODE: CODE }, { DEMO_BUDDY_CODE: CODE, DEMO_BUDDY_ENABLED: "false" }]) {
      Object.assign(app.env, { DEMO_BUDDY_ENABLED: undefined }, off);
      expect(await call(noor, "POST", `/squads/join/${CODE}`)).toEqual({ status: 404, body: { error: expect.any(String), code: "code_not_found" } });
      expect(await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`)).toEqual({ status: 404, body: { error: expect.any(String), code: "not_found" } });
    }
    const sid = await lockIn(ava, review);
    await app.advance(5 * MINUTE);
    expect(bot(await stateOf(ava, sid))).toBeUndefined();
    // The review squad stays as it was, Demo Buddy listed.
    expect((await call(ava, "GET", "/squads")).body.squads[0].members).toHaveLength(2);
  });

  test("a code the app couldn't type switches it off, and says so once", async () => {
    Object.assign(app.env, { DEMO_BUDDY_CODE: "REVIEW-01" });
    expect((await call(ava, "POST", "/squads/join/REVIEW01")).status).toBe(404);
    expect((await call(ava, "POST", "/squads/join/REVIEW01")).status).toBe(404);
    expect(logs.filter((line) => line.includes("DEMO_BUDDY_CODE")).length).toBeLessThanOrEqual(1);
    expect(app.count("SELECT count(*) FROM squads")).toBe(0);
  });

  test("someone who blocked Demo Buddy can't make one: 403 blocked", async () => {
    expect((await call(ava, "POST", "/blocks", { userId: DEMO_BUDDY_ID })).status).toBe(204);
    expect((await call(ava, "POST", `/squads/join/${CODE}`)).body.code).toBe("blocked");
    expect(app.count("SELECT count(*) FROM squads")).toBe(0);
  });

  test("a Review Squad goes with its last person: Demo Buddy never keeps one, or takes one over", async () => {
    const review = await redeem(ava);
    expect((await call(ava, "DELETE", `/squads/${review}/members/me`)).status).toBe(204);
    expect(app.count("SELECT count(*) FROM squads")).toBe(0);
    expect(app.count("SELECT count(*) FROM squad_members WHERE user_id = ?", DEMO_BUDDY_ID)).toBe(0);

    // With a friend in it, the friend takes it over, not the bot.
    const second = await redeem(ava);
    const code = (await call(ava, "POST", `/squads/${second}/invite`)).body.code;
    await call(noor, "POST", `/squads/join/${code}`);
    await call(ava, "DELETE", `/squads/${second}/members/me`);
    expect(app.value("SELECT owner_id FROM squads WHERE id = ?", second)).toBe(noor.user.id);
    // Deleting the last person's account deletes it too.
    expect((await app.request("DELETE", "/me", { token: noor.token })).status).toBe(204);
    expect(app.count("SELECT count(*) FROM squads")).toBe(0);
    expect(app.value("SELECT is_bot FROM users WHERE id = ?", DEMO_BUDDY_ID)).toBe(1);
  });
});

describe("in a Review Squad's room", () => {
  test("joins 6 seconds after the reviewer locks in, with a 3-minute timer; cheers, pauses, resumes and finishes on time", async () => {
    const review = await redeem(ava);
    const sid = await lockIn(ava, review);
    await upload(ava, sid, 1);
    expect((await stateOf(ava, sid)).m).toHaveLength(1);

    const pushes: Array<[number, number | undefined, string | undefined, number]> = [];
    const take = () => {
      for (const request of livePushes()) {
        const state = request.aps["content-state"];
        pushes.push([request.priority, bot(state) === undefined ? undefined : (bot(state) as { s: number }).s, state.c?.f, request.aps.timestamp - T0]);
      }
      app.apns.clear();
    };

    // +6 s: Demo Buddy joins through the same path as a person, pushed at priority 10 after 2 s.
    await app.advance(6);
    expect(bot(await stateOf(ava, sid))).toEqual({ i: DEMO_BUDDY_ID, n: DEMO_BUDDY_NAME, a: DEMO_BUDDY_AVATAR, s: MemberState.focusing, b: T0 + 6, e: T0 + 6 + 180 });
    // +66 s: cheers Ava (priority 5); the room clears it 10 s later (priority 5).
    await app.advance(60);
    expect((await stateOf(ava, sid)).c).toEqual({ f: DEMO_BUDDY_ID, t: ava.user.id, k: 0, at: T0 + 66 });
    await app.advance(CHEER_SHOWN_SECONDS);
    expect((await stateOf(ava, sid)).c).toBeUndefined();
    // +96 s: pauses; +126 s: resumes, its end 30 s later.
    await app.advance(20);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.paused, q: T0 + 96 });
    await app.advance(30);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.focusing, e: T0 + 6 + 180 + 30 });
    // +216 s: its time runs out: done, priority 10.
    await app.advance(90 + COALESCE_SECONDS);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.done });
    take();
    expect(pushes).toEqual([
      [10, MemberState.focusing, undefined, 8],
      [5, MemberState.focusing, DEMO_BUDDY_ID, 68],
      [5, MemberState.focusing, undefined, 78],
      [5, MemberState.paused, undefined, 98],
      [5, MemberState.focusing, undefined, 128],
      [10, MemberState.done, undefined, 218],
    ]);
    // Every push went to Ava's activity: Demo Buddy has no token, and is counted like anyone.
    expect(new Set(pushes.map(() => laToken(1))).size).toBe(1);

    // Three focused minutes, no coins; no participants row and no events. They feed the pet.
    expect({ ...(app.sqlite.prepare("SELECT focused_sec, completed, coins, xp FROM focus_log WHERE user_id = ?").get(DEMO_BUDDY_ID) as object) }).toEqual({
      focused_sec: 180,
      completed: 1,
      coins: 0,
      xp: 3,
    });
    expect(app.value("SELECT coins FROM users WHERE id = ?", DEMO_BUDDY_ID)).toBe(0);
    expect(app.count("SELECT count(*) FROM participants WHERE user_id = ?", DEMO_BUDDY_ID)).toBe(0);
    expect(app.count("SELECT count(*) FROM events WHERE user_id = ?", DEMO_BUDDY_ID)).toBe(0);
    expect(app.value("SELECT pet_xp FROM squads WHERE id = ?", review)).toBe(3);

    // Ava finishes: with Demo Buddy's finish, the Review Squad's egg hatches. The room ends as usual.
    await app.advance(25 * MINUTE);
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");
    expect(app.value("SELECT hatched_at FROM squads WHERE id = ?", review)).toBe(T0 + 25 * MINUTE);
    expect(app.value("SELECT coins FROM users WHERE id = ?", ava.user.id)).toBe(30);
    const ended = logs.find((line) => line.startsWith(`room ${sid}: ended`));
    expect(ended).toContain("with 1 member and Demo Buddy");
    expect(app.value("SELECT meta_json FROM events WHERE session_id = ? AND type = 'room_end'", sid)).toContain('"members":1,"bots":1');
  });

  test("leaves when the reviewer stops (not sad), so the room ends; joins again when they lock in again", async () => {
    const review = await redeem(ava);
    let sid = await lockIn(ava, review, 1);
    await upload(ava, sid, 1);
    await app.advance(6 + COALESCE_SECONDS);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.focusing });
    // Ava's minute is up at +60: Demo Buddy leaves with her, and the room ends with one end push.
    app.apns.clear();
    await app.advance(52);
    const final = await stateOf(ava, sid);
    expect(bot(final)).toMatchObject({ s: MemberState.left });
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");
    expect(livePushes().map((request) => request.aps.event)).toEqual(["end"]);
    expect(app.value("SELECT last_sad_at FROM squads WHERE id = ?", review)).toBeNull();
    expect(app.value("SELECT focused_sec FROM focus_log WHERE user_id = ?", DEMO_BUDDY_ID)).toBe(54);

    // Ava locks in again: a new room, and Demo Buddy joins it too.
    app.clock.now += 5 * MINUTE;
    sid = await lockIn(ava, review);
    await app.advance(6);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.focusing, b: app.clock.now });

    // Ava ends inside 6 seconds of locking in again: Demo Buddy never comes, the room just ends.
    await call(ava, "POST", `/sessions/${sid}/end`);
    app.clock.now += MINUTE;
    sid = await lockIn(ava, review);
    await app.advance(3);
    await call(ava, "POST", `/sessions/${sid}/end`);
    await app.advance(MINUTE);
    expect((await stateOf(ava, sid)).m).toHaveLength(1);
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");
  });

  test("joins again in the same room when someone joins after it finished", async () => {
    const review = await redeem(ava);
    const code = (await call(ava, "POST", `/squads/${review}/invite`)).body.code;
    await call(noor, "POST", `/squads/join/${code}`);
    const sid = await lockIn(ava, review);
    await app.advance(6 + 210);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.done });
    // Joining while it's running doesn't bring a second Demo Buddy.
    app.clock.now += MINUTE;
    expect(await lockIn(noor, review)).toBe(sid);
    await app.advance(6);
    const state = await stateOf(noor, sid);
    expect(state.m.map((member: { i: string }) => member.i)).toEqual([ava.user.id, DEMO_BUDDY_ID, noor.user.id]);
    expect(bot(state)).toMatchObject({ s: MemberState.focusing, b: app.clock.now });
    await app.advance(60);
    // This time it cheers whoever brought it back.
    expect((await stateOf(noor, sid)).c).toMatchObject({ f: DEMO_BUDDY_ID, t: noor.user.id });
  });

  test("never in a real squad's room, or on any leaderboard, or counted for a streak", async () => {
    const created = await call(ava, "POST", "/squads", { name: "Library Goblins" });
    const real = created.body.squad.id;
    const realSid = await lockIn(ava, real);
    await app.advance(5 * MINUTE);
    expect((await stateOf(ava, realSid)).m.map((member: { i: string }) => member.i)).toEqual([ava.user.id]);

    const review = await redeem(noor);
    const reviewSid = await lockIn(noor, review, 20);
    await app.advance(20 * MINUTE);
    expect(app.value("SELECT status FROM sessions WHERE id = ?", reviewSid)).toBe("ended");
    const board = (await call(noor, "GET", `/squads/${review}/leaderboard`)).body.entries;
    expect(board.map((entry: { userId: string }) => entry.userId)).toEqual([noor.user.id]);
    expect((await call(ava, "GET", `/squads/${real}/leaderboard`)).body.entries.map((entry: { userId: string }) => entry.userId)).toEqual([ava.user.id]);
    // Noor's 20 minutes count for the Review Squad's day, by herself: the bot isn't half the squad.
    const streak = (await call(noor, "GET", "/squads")).body.squads[0].streak;
    expect(streak).toMatchObject({ count: 1, countedToday: true, doneToday: 1, needed: 1 });
    expect(app.count("SELECT count(*) FROM squad_members m JOIN squads s ON s.id = m.squad_id WHERE m.user_id = ? AND s.review = 0", DEMO_BUDDY_ID)).toBe(0);
  });

  test("is nobody's friend: a friend code naming it is refused", async () => {
    app.sqlite
      .prepare("INSERT INTO invite_codes (code, kind, target_id, created_by, expires_at) VALUES ('BUDDY234', 'friend', ?, ?, ?)")
      .run(DEMO_BUDDY_ID, DEMO_BUDDY_ID, T0 + 86_400);
    expect(await call(ava, "POST", "/friends/redeem/BUDDY234")).toEqual({ status: 404, body: { error: expect.any(String), code: "code_not_found" } });
    expect(app.count("SELECT count(*) FROM friendships")).toBe(0);
  });
});

describe("POST /squads/:id/demo-buddy/lock-in", () => {
  test("Demo Buddy opens a 3-minute session and the reviewer gets the alert, even in quiet hours", async () => {
    const review = await redeem(ava);
    await register(ava, 1);
    const response = await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`);
    expect(response).toEqual({
      status: 200,
      body: { session: { id: expect.any(String), squadId: review, hostId: DEMO_BUDDY_ID, status: "open", createdAt: T0 } },
    });
    const sid = response.body.session.id;
    await app.settle();
    const [alert, ...more] = alerts();
    expect(more).toHaveLength(0);
    expect(alert?.token).toBe(laToken(0xa1));
    expect(JSON.parse(alert?.body ?? "{}")).toMatchObject({
      aps: { alert: { title: REVIEW_SQUAD_NAME, body: "Demo Buddy is locking in 🔒" }, category: "LK_LOCKIN" },
      lk: { type: "lockin", sid, sq: review },
    });
    expect((await stateOf(ava, sid)).m).toEqual([{ i: DEMO_BUDDY_ID, n: DEMO_BUDDY_NAME, a: DEMO_BUDDY_AVATAR, s: MemberState.focusing, b: T0, e: T0 + 180 }]);
    expect(app.count("SELECT count(*) FROM participants WHERE session_id = ?", sid)).toBe(0);
    // Asking again while it's running changes nothing, and alerts nobody.
    expect((await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`)).body.session.id).toBe(sid);
    await app.settle();
    expect(alerts()).toHaveLength(1);

    // Join 25: Ava joins its room; at +60 from its start it cheers her.
    app.clock.now = T0 + 20;
    expect(await lockIn(ava, review)).toBe(sid);
    await app.advance(40);
    expect((await stateOf(ava, sid)).c).toMatchObject({ f: DEMO_BUDDY_ID, t: ava.user.id });
    // Its own timer: done at +210 (with its pause); Ava's keeps the room open.
    await app.advance(150);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.done, e: T0 + 210 });
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("open");
  });

  test("a room nobody joins ends when Demo Buddy's timer does; the alert respects mute and the limits", async () => {
    const review = await redeem(ava);
    await register(ava, 1, null);
    const sid = (await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`)).body.session.id;
    await app.settle();
    expect(alerts()).toHaveLength(1);
    await app.advance(210);
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");

    // Within 30 minutes of the last alert from this squad: a new room, but no second alert.
    app.clock.now += 5 * MINUTE;
    const again = (await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`)).body.session.id;
    expect(again).not.toBe(sid);
    await app.settle();
    expect(alerts()).toHaveLength(1);

    // Muted: never.
    await app.advance(210);
    await call(ava, "PATCH", `/squads/${review}/members/me`, { muted: true });
    app.clock.now += 60 * MINUTE;
    await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`);
    await app.settle();
    expect(alerts()).toHaveLength(1);
  });

  test("with the squad's room open, Demo Buddy joins it now (no alert)", async () => {
    const review = await redeem(ava);
    await register(ava, 1, null);
    const sid = await lockIn(ava, review);
    await app.advance(6 + 210);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.done });
    const response = await call(ava, "POST", `/squads/${review}/demo-buddy/lock-in`);
    expect(response.body.session.id).toBe(sid);
    expect(bot(await stateOf(ava, sid))).toMatchObject({ s: MemberState.focusing, b: app.clock.now });
    await app.settle();
    expect(alerts()).toHaveLength(0);
  });

  test("only squads with Demo Buddy (404), only members (403)", async () => {
    const created = await call(ava, "POST", "/squads", { name: "Library Goblins" });
    expect(await call(ava, "POST", `/squads/${created.body.squad.id}/demo-buddy/lock-in`)).toEqual({
      status: 404,
      body: { error: expect.any(String), code: "not_found" },
    });
    const review = await redeem(ava);
    expect((await call(noor, "POST", `/squads/${review}/demo-buddy/lock-in`)).body.code).toBe("not_member");
    expect((await call(noor, "POST", "/squads/nope/demo-buddy/lock-in")).body.code).toBe("not_member");
    expect(app.count("SELECT count(*) FROM sessions")).toBe(0);
  });

  test("a normal opener's alert still waits for quiet hours: only Demo Buddy's asked-for one skips them", async () => {
    const review = await redeem(ava);
    const code = (await call(ava, "POST", `/squads/${review}/invite`)).body.code;
    await call(noor, "POST", `/squads/join/${code}`);
    await register(ava, 1);
    const sid = await lockIn(noor, review);
    await app.settle();
    expect(alerts()).toHaveLength(0);
    expect(logs).toContain(`alerts ${sid}: 0 alerted, 1 in quiet hours, 0 over a limit; 0 pushes accepted, 0 refused, 0 failed, 0 devices removed`);
  });
});
