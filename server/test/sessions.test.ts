// Sessions and their rooms through the whole Worker: real SQL on an in-memory D1, a `Room` Durable
// Object per session on a fake runtime (storage, alarms, WebSockets), and a fake APNs.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { APNS_BODY_LIMIT_BYTES } from "../src/apns.ts";
import {
  END_DISMISSAL_SECONDS,
  MemberState,
  PAYLOAD_BUDGET_BYTES,
  STALE_AFTER_END_SECONDS,
  parseContentState,
  payloadByteCount,
} from "../src/liveActivity.ts";
import { CHEER_SHOWN_SECONDS, COALESCE_SECONDS, ENDED_ROOM_KEPT_SECONDS, MEMBER_MAX_SECONDS, PET_MOOD_HAPPY, PET_MOOD_LOW } from "../src/room.ts";
import { type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";
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

afterEach(() => {
  vi.restoreAllMocks();
  // Logs say what happened, with room ids and counts: never who, and never a token.
  for (const line of logs) {
    for (const secret of app.issued) expect(line).not.toContain(secret);
    for (let seed = 1; seed < 10; seed++) expect(line).not.toContain(laToken(seed));
    expect(line).not.toMatch(/\b(ava|noor|kai|Ava|Noor|Kai|Library Goblins)\b/);
    expect(line).not.toMatch(/eyJ/);
  }
});

const call = async (who: SignedIn, method: string, path: string, body?: unknown, headers?: Record<string, string>) =>
  read(await app.request(method, path, { token: who.token, body, headers }));

/** A squad owned by `owner` with `members` joined by code, in that order. */
async function squad(owner: SignedIn, ...members: SignedIn[]): Promise<string> {
  const created = await call(owner, "POST", "/squads", { name: "Library Goblins" });
  expect(created.status).toBe(200);
  const id = created.body.squad.id as string;
  const code = (await call(owner, "POST", `/squads/${id}/invite`)).body.code as string;
  for (const member of members) expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
  return id;
}

async function start(who: SignedIn, body: Record<string, unknown>) {
  const response = await call(who, "POST", "/sessions", body);
  expect(response.status, JSON.stringify(response.body)).toBe(200);
  return response.body;
}

async function upload(who: SignedIn, sid: string, seed: number, env = "production") {
  const response = await call(who, "POST", `/sessions/${sid}/la-token`, { token: laToken(seed), env });
  expect(response.status, JSON.stringify(response.body)).toBe(204);
}

const participant = (sid: string, who: SignedIn) =>
  ({ ...(app.sqlite.prepare("SELECT * FROM participants WHERE session_id = ? AND user_id = ?").get(sid, who.user.id) as object) }) as Record<string, unknown>;
const stateOf = async (who: SignedIn, sid: string) => (await call(who, "GET", `/sessions/${sid}`)).body.contentState;

describe("POST /sessions, solo", () => {
  test("opens a room with just you, ready for ActivityKit", async () => {
    const joined = await start(ava, { minutes: 25 });
    const sid = joined.session.id;
    expect(sid).toMatch(/^[0-9A-Za-z]{10}$/);
    expect(joined).toEqual({
      session: { id: sid, squadId: null, hostId: ava.user.id, status: "open", createdAt: T0 },
      attributes: { sid, me: ava.user.id },
      contentState: { v: 1, m: [{ i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0, e: T0 + 25 * 60 }] },
    });
    // Exactly the wire format the phone decodes.
    expect(parseContentState(joined.contentState)).toEqual(joined.contentState);

    expect({ ...(app.sqlite.prepare("SELECT * FROM sessions").get() as object) }).toEqual({
      id: sid,
      squad_id: null,
      host_id: ava.user.id,
      status: "open",
      created_at: T0,
      ended_at: null,
    });
    expect(participant(sid, ava)).toMatchObject({ state: 0, planned_min: 25, started_at: T0, ends_at: T0 + 1500, ended_at: null, la_token: null, la_env: null });
    expect(app.value("SELECT type FROM events WHERE session_id = ?", sid)).toBe("join");
    // Nobody to push to yet, and nothing changed since the app got this state.
    expect(app.apns.requests).toHaveLength(0);
  });

  test("a name falls back to the handle, then to Lockling", async () => {
    const newcomer = await app.signIn("sub.newcomer");
    expect((await start(newcomer, { minutes: 5 })).contentState.m[0].n).toBe("Lockling");
    const handled = await app.user("verylonghandle123", null);
    expect((await start(handled, { minutes: 5 })).contentState.m[0].n).toBe("verylonghand");
  });

  test("minutes are whole, 1–240", async () => {
    for (const minutes of [0, 241, 2.5, "25", null, undefined]) {
      const response = await call(ava, "POST", "/sessions", { minutes });
      expect(response, String(minutes)).toEqual({ status: 422, body: { error: expect.any(String), code: "minutes_invalid" } });
    }
    expect((await call(ava, "POST", "/sessions", { minutes: 240 })).status).toBe(200);
    expect(app.count("SELECT count(*) FROM sessions")).toBe(1);
  });

  test("409 already_in_session while your timer is running, naming the session", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    expect(await call(ava, "POST", "/sessions", { minutes: 25 })).toEqual({
      status: 409,
      body: { error: expect.any(String), code: "already_in_session", sessionId: sid },
    });
    // Once it's over, a new one starts.
    await call(ava, "POST", `/sessions/${sid}/end`);
    expect((await call(ava, "POST", "/sessions", { minutes: 25 })).status).toBe(200);
  });
});

describe("POST /sessions, squad", () => {
  test("opens the squad's room, and the next member joins it", async () => {
    const squadId = await squad(ava, noor, kai);
    const opened = await start(ava, { squadId, minutes: 25 });
    const sid = opened.session.id;
    expect(opened.session).toEqual({ id: sid, squadId, hostId: ava.user.id, status: "open", createdAt: T0 });
    expect(opened.attributes).toEqual({ sid, me: ava.user.id, sq: "Library Goblins" });
    // No pet until the egg hatches (M5): `p` is left out, never null.
    expect(opened.contentState).toEqual({ v: 1, m: [{ i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0, e: T0 + 1500 }] });
    expect((await call(noor, "GET", "/squads")).body.squads[0].openSessionId).toBe(sid);

    app.clock.now = T0 + 60;
    const joined = await start(noor, { squadId, minutes: 50 });
    expect(joined.session.id).toBe(sid);
    expect(joined.attributes).toEqual({ sid, me: noor.user.id, sq: "Library Goblins" });
    // Host first, then in the order they joined; the same state for everyone.
    expect(joined.contentState).toEqual({
      v: 2,
      m: [
        { i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0, e: T0 + 1500 },
        { i: noor.user.id, n: "Noor", a: "b0.c0.e0.h0", s: 0, b: T0 + 60, e: T0 + 60 + 3000 },
      ],
    });
    expect(app.count("SELECT count(*) FROM sessions")).toBe(1);
    expect(app.count("SELECT count(*) FROM participants WHERE session_id = ?", sid)).toBe(2);
  });

  test("POST /sessions/:id/join joins by id, and asking again changes nothing", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    const first = await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25 });
    expect(first.status).toBe(200);
    const again = await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 90 });
    expect(again).toEqual(first);
  });

  test("the squad pet comes from D1, with today's mood", async () => {
    const squadId = await squad(ava, noor, kai);
    app.sqlite.prepare("UPDATE squads SET pet_species = 'fox', pet_stage = 2, pet_xp = 1350 WHERE id = ?").run(squadId);
    // One of three focused today: low.
    const opened = await start(ava, { squadId, minutes: 25 });
    expect(opened.contentState.p).toEqual({ k: "fox.2", md: PET_MOOD_LOW, x: 0.25 });
    // Two of three: happy.
    const joined = await start(noor, { squadId, minutes: 25 });
    expect(joined.contentState.p).toEqual({ k: "fox.2", md: PET_MOOD_HAPPY, x: 0.25 });
  });

  test("only members: 403 not_member", async () => {
    const squadId = await squad(ava, noor);
    expect((await call(kai, "POST", "/sessions", { squadId, minutes: 25 })).body.code).toBe("not_member");
    expect((await call(kai, "POST", "/sessions", { squadId: "nope", minutes: 25 })).body.code).toBe("not_member");
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    expect(await call(kai, "POST", `/sessions/${sid}/join`, { minutes: 25 })).toEqual({ status: 403, body: { error: expect.any(String), code: "not_member" } });
    // A solo session is only for whoever started it.
    const solo = (await start(kai, { minutes: 25 })).session.id;
    expect((await call(noor, "POST", `/sessions/${solo}/join`, { minutes: 25 })).body.code).toBe("not_member");
    expect((await call(noor, "GET", `/sessions/${solo}`)).body.code).toBe("not_member");
    expect((await call(noor, "POST", `/sessions/${solo}/pause`)).body.code).toBe("not_member");
    expect((await call(noor, "POST", "/sessions/Zz00000000/join", { minutes: 25 })).status).toBe(404);
  });

  test("409 already_in_session when you're in another session", async () => {
    const squadId = await squad(ava, noor);
    const solo = (await start(noor, { minutes: 25 })).session.id;
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    expect(await call(noor, "POST", "/sessions", { squadId, minutes: 25 })).toEqual({
      status: 409,
      body: { error: expect.any(String), code: "already_in_session", sessionId: solo },
    });
    expect((await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25 })).body).toMatchObject({ code: "already_in_session", sessionId: solo });
  });

  test("an ended room can't be joined: 410, and the next lock-in opens a new one", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await call(ava, "POST", `/sessions/${sid}/end`);
    expect(await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25 })).toEqual({ status: 410, body: { error: expect.any(String), code: "session_ended" } });
    const next = await start(noor, { squadId, minutes: 25 });
    expect(next.session.id).not.toBe(sid);
    expect(next.session.hostId).toBe(noor.user.id);
  });

  test("two members locking in at once end up in one room", async () => {
    const squadId = await squad(ava, noor, kai);
    const [a, b, c] = await Promise.all([
      call(ava, "POST", "/sessions", { squadId, minutes: 25 }),
      call(noor, "POST", "/sessions", { squadId, minutes: 25 }),
      call(kai, "POST", "/sessions", { squadId, minutes: 25 }),
    ]);
    expect([a.status, b.status, c.status]).toEqual([200, 200, 200]);
    expect(new Set([a.body.session.id, b.body.session.id, c.body.session.id]).size).toBe(1);
    expect(app.count("SELECT count(*) FROM sessions WHERE status = 'open'")).toBe(1);
  });

  test("joining again after finishing starts a new timer and keeps the focused time", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await start(noor, { squadId, minutes: 90 });
    await app.advance(25 * 60);
    expect(participant(sid, ava)).toMatchObject({ state: MemberState.done, focused_sec: 1500 });

    const again = await start(ava, { squadId, minutes: 10 });
    expect(again.session.id).toBe(sid);
    expect(again.contentState.m[0]).toEqual({ i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0 + 1500, e: T0 + 1500 + 600 });
    await app.advance(10 * 60);
    expect(participant(sid, ava)).toMatchObject({ state: MemberState.done, planned_min: 10, focused_sec: 2100, ended_at: T0 + 2100 });
  });
});

describe("POST /sessions/:id/la-token", () => {
  test("stores the token with its APNs environment", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    await upload(ava, sid, 1, "sandbox");
    expect(participant(sid, ava)).toMatchObject({ la_token: laToken(1), la_env: "sandbox" });
    // A new token replaces it (tokens can change); uppercase hex is stored lowercased.
    const response = await call(ava, "POST", `/sessions/${sid}/la-token`, { token: laToken(2).toUpperCase(), env: "production" });
    expect(response.status).toBe(204);
    expect(participant(sid, ava)).toMatchObject({ la_token: laToken(2), la_env: "production" });
    expect(app.apns.requests).toHaveLength(0);
  });

  test("422 token_invalid for anything that isn't a hex token and an environment", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    for (const body of [{ token: "nothex", env: "production" }, { token: laToken(1) }, { token: laToken(1), env: "development" }, { env: "sandbox" }]) {
      expect(await call(ava, "POST", `/sessions/${sid}/la-token`, body), JSON.stringify(body)).toEqual({
        status: 422,
        body: { error: expect.any(String), code: "token_invalid" },
      });
    }
    expect((await call(noor, "POST", `/sessions/${sid}/la-token`, { token: laToken(1), env: "sandbox" })).body.code).toBe("not_member");
  });

  test("pushes go to each token's own APNs host", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await upload(ava, sid, 1, "sandbox");
    await start(noor, { squadId, minutes: 25 });
    await upload(noor, sid, 2, "production");
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.to(laToken(1)).map((request) => request.url)).toEqual([`https://api.sandbox.push.apple.com/3/device/${laToken(1)}`]);
    expect(app.apns.to(laToken(2)).map((request) => request.url)).toEqual([`https://api.push.apple.com/3/device/${laToken(2)}`]);
    for (const request of app.apns.requests) {
      expect(request.headers).toMatchObject({ "apns-push-type": "liveactivity", "apns-topic": "com.example.lockin.push-type.liveactivity" });
    }
  });
});

describe("pause, resume, end and slip", () => {
  test("pausing stops the clock: resuming moves the end later by the pause", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    app.clock.now = T0 + 300;
    const paused = await call(ava, "POST", `/sessions/${sid}/pause`);
    expect(paused).toEqual({
      status: 200,
      body: { contentState: { v: 2, m: [{ i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: MemberState.paused, b: T0, e: T0 + 1500, q: T0 + 300 }] } },
    });
    expect(participant(sid, ava)).toMatchObject({ state: 2, paused_at: T0 + 300 });
    expect((await call(ava, "POST", `/sessions/${sid}/pause`)).body.code).toBe("bad_state");

    // The alarm at the old end must not finish a paused timer.
    await app.advance(1500);
    expect((await stateOf(ava, sid)).m[0].s).toBe(MemberState.paused);

    const resumed = await call(ava, "POST", `/sessions/${sid}/resume`);
    expect(resumed.body.contentState.m[0]).toEqual({ i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0, e: T0 + 1500 + 1500 });
    expect(participant(sid, ava)).toMatchObject({ state: 0, paused_at: null, ends_at: T0 + 3000 });
    expect((await call(ava, "POST", `/sessions/${sid}/resume`)).body.code).toBe("bad_state");

    // 20 minutes left: it finishes then, with 25 minutes focused.
    await app.advance(1200);
    expect(participant(sid, ava)).toMatchObject({ state: MemberState.done, focused_sec: 1500, ended_at: T0 + 3000 });
  });

  test("pausing after the time ran out is a finish", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await start(noor, { squadId, minutes: 50 });
    app.clock.now = T0 + 1500;
    const response = await call(ava, "POST", `/sessions/${sid}/pause`);
    expect(response.body.contentState.m[0].s).toBe(MemberState.done);
  });

  test("ending early leaves (4) with the time focused so far", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await start(noor, { squadId, minutes: 50 });
    app.clock.now = T0 + 600;
    const ended = await call(ava, "POST", `/sessions/${sid}/end`);
    expect(ended.body.contentState.m[0]).toMatchObject({ s: MemberState.left, b: T0, e: T0 + 1500 });
    expect(ended.body.contentState.m[0]).not.toHaveProperty("q");
    expect(participant(sid, ava)).toMatchObject({ state: 4, ended_at: T0 + 600, focused_sec: 600 });
    expect((await call(ava, "POST", `/sessions/${sid}/end`)).body.code).toBe("bad_state");
    expect((await call(ava, "POST", `/sessions/${sid}/pause`)).body.code).toBe("bad_state");
    // Noor's still going, so the room is too.
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("open");
  });

  test("ending while paused counts the time up to the pause", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    app.clock.now = T0 + 400;
    await call(ava, "POST", `/sessions/${sid}/pause`);
    app.clock.now = T0 + 1000;
    await call(ava, "POST", `/sessions/${sid}/end`);
    expect(participant(sid, ava)).toMatchObject({ state: 4, focused_sec: 400, paused_at: null });
  });

  test("a slip stops the timer (5) and counts", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await start(noor, { squadId, minutes: 25 });
    app.clock.now = T0 + 120;
    const slipped = await call(noor, "POST", `/sessions/${sid}/slip`);
    expect(slipped.body.contentState.m[1].s).toBe(MemberState.slipped);
    expect(participant(sid, noor)).toMatchObject({ state: 5, slips: 1, focused_sec: 120, ended_at: T0 + 120 });
    expect((await call(noor, "POST", `/sessions/${sid}/slip`)).body.code).toBe("bad_state");
    expect(app.value("SELECT type FROM events WHERE session_id = ? AND user_id = ? ORDER BY id DESC", sid, noor.user.id)).toBe("slip");
  });

  test("the last one ending ends the room", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    app.clock.now = T0 + 60;
    await call(ava, "POST", `/sessions/${sid}/slip`);
    expect({ ...(app.sqlite.prepare("SELECT status, ended_at FROM sessions").get() as object) }).toEqual({ status: "ended", ended_at: T0 + 60 });
    expect((await call(ava, "POST", `/sessions/${sid}/resume`)).body.code).toBe("session_ended");
    expect((await call(ava, "GET", `/sessions/${sid}`)).body.session.status).toBe("ended");
  });
});

describe("timers finish themselves", () => {
  test("an alarm at each end marks that member done; the last one ends the room with an end push", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await upload(ava, sid, 1);
    app.clock.now = T0 + 60;
    await start(noor, { squadId, minutes: 50 });
    await upload(noor, sid, 2);
    await app.advance(COALESCE_SECONDS);
    app.apns.clear();

    // Ava's 25 minutes: done, and pushed at priority 10 within the coalescing window.
    await app.advance(1500 - 62 + COALESCE_SECONDS);
    expect(participant(sid, ava)).toMatchObject({ state: 3, ended_at: T0 + 1500, focused_sec: 1500 });
    expect(app.apns.requests.map((request) => [request.token, request.priority, request.aps.event])).toEqual([
      [laToken(1), 10, "update"],
      [laToken(2), 10, "update"],
    ]);
    const update = app.apns.requests[0]?.aps ?? {};
    expect(update.timestamp).toBe(T0 + 1500 + COALESCE_SECONDS);
    expect(update["content-state"].m.map((member: { s: number }) => member.s)).toEqual([3, 0]);
    // Stale five minutes after the last running timer (Noor's) should end.
    expect(update["stale-date"]).toBe(T0 + 60 + 3000 + STALE_AFTER_END_SECONDS);
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("open");
    app.apns.clear();

    // Noor's 50: the room ends at once with an `end` and the final state, dismissed in 30 minutes.
    await app.advance(3060 - 1502);
    const end = T0 + 3060;
    expect(app.clock.now).toBe(end);
    expect(app.apns.requests.map((request) => [request.token, request.priority, request.aps.event])).toEqual([
      [laToken(1), 10, "end"],
      [laToken(2), 10, "end"],
    ]);
    const final = app.apns.requests[0]?.aps ?? {};
    expect(final).toMatchObject({ timestamp: end, event: "end", "dismissal-date": end + END_DISMISSAL_SECONDS });
    expect(final).not.toHaveProperty("stale-date");
    expect(final["content-state"].m.map((member: { s: number }) => member.s)).toEqual([3, 3]);

    expect({ ...(app.sqlite.prepare("SELECT status, ended_at FROM sessions WHERE id = ?").get(sid) as object) }).toEqual({ status: "ended", ended_at: end });
    expect(participant(sid, noor)).toMatchObject({ state: 3, ended_at: end, focused_sec: 3000, la_token: null, la_env: null });
    expect(participant(sid, ava)).toMatchObject({ la_token: null, la_env: null });
    const events = app.sqlite.prepare("SELECT type, meta_json FROM events WHERE session_id = ? ORDER BY id").all(sid).map((row) => ({ ...row }));
    expect(events.map((row) => row.type)).toEqual(["join", "join", "done", "done", "room_end"]);
    expect(JSON.parse(String(events[4]?.meta_json))).toEqual({ members: 2, batches: 3, p10: 6, p5: 0, refused: 0, failed: 0, cleared: 0 });
    // The push counts per room, in the log.
    expect(logs).toContain(`room ${sid}: ended after 51 min with 2 members; 6 pushes accepted (6 at priority 10, 0 at 5) in 3 batches, 0 refused, 0 failed, 0 tokens cleared`);

    // Nothing more goes out.
    app.apns.clear();
    await app.advance(3600);
    expect(app.apns.requests).toHaveLength(0);
  });

  test("an 8-hour pause ends as leaving: the activity is gone by then", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    app.clock.now = T0 + 60;
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await app.advance(MEMBER_MAX_SECONDS);
    expect(participant(sid, ava)).toMatchObject({ state: 4, focused_sec: 60, ended_at: T0 + MEMBER_MAX_SECONDS });
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");
    expect((await call(ava, "POST", "/sessions", { minutes: 25 })).status).toBe(200);
  });
});

describe("coalescing", () => {
  test("three changes inside 2 s are one push per token, with the latest v, at 10 when a join is among them", async () => {
    const squadId = await squad(ava, noor, kai);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await upload(ava, sid, 1);
    await start(noor, { squadId, minutes: 25 });
    await upload(noor, sid, 2);
    await app.advance(COALESCE_SECONDS);
    app.apns.clear();

    await call(ava, "POST", `/sessions/${sid}/pause`);
    // Alarms due in the meantime fire: nothing goes out before the window closes.
    await app.advance(1);
    expect(app.apns.requests).toHaveLength(0);
    await start(kai, { squadId, minutes: 25 });
    await upload(kai, sid, 3);
    await call(noor, "POST", `/sessions/${sid}/cheer`, { to: ava.user.id, kind: 2 });
    await app.advance(0.5);
    expect(app.apns.requests).toHaveLength(0);

    await app.advance(0.5);
    expect(app.apns.requests.map((request) => request.token).sort()).toEqual([laToken(1), laToken(2), laToken(3)]);
    const latest = (await stateOf(ava, sid)).v;
    expect(latest).toBe(5);
    for (const request of app.apns.requests) {
      expect(request.priority).toBe(10);
      expect(request.aps["content-state"].v).toBe(latest);
      expect(request.aps["content-state"].m).toHaveLength(3);
      expect(request.aps["content-state"].c).toMatchObject({ f: noor.user.id, t: ava.user.id, k: 2 });
    }
  });

  test("pauses and resumes alone go at priority 5", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    await upload(ava, sid, 1);
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await call(ava, "POST", `/sessions/${sid}/resume`);
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => [request.priority, request.aps["content-state"].v])).toEqual([[5, 4]]);
  });

  test("tokens are never pushed timer ticks: a quiet room sends nothing", async () => {
    const sid = (await start(ava, { minutes: 90 })).session.id;
    await upload(ava, sid, 1);
    await app.advance(89 * 60);
    expect(app.apns.requests).toHaveLength(0);
  });
});

describe("cheers", () => {
  test("show for about 10 seconds: one push with the cheer, one clearing it, both at 5", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await upload(ava, sid, 1);
    await start(noor, { squadId, minutes: 25 });
    await app.advance(COALESCE_SECONDS);
    app.apns.clear();

    const cheered = await call(noor, "POST", `/sessions/${sid}/cheer`, { to: ava.user.id, kind: 7 });
    expect(cheered.status).toBe(204);
    const now = app.clock.now;
    expect((await stateOf(ava, sid)).c).toEqual({ f: noor.user.id, t: ava.user.id, k: 7, at: now });

    await app.advance(CHEER_SHOWN_SECONDS + COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => [request.priority, request.aps["content-state"].c?.k ?? null])).toEqual([
      [5, 7],
      [5, null],
    ]);
    expect(app.apns.requests[1]?.aps["content-state"]).not.toHaveProperty("c");
    expect(await stateOf(ava, sid)).not.toHaveProperty("c");
  });

  test("one per sender every 10 seconds: 429 cheer_too_soon", async () => {
    const squadId = await squad(ava, noor, kai);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await start(noor, { squadId, minutes: 25 });
    await start(kai, { squadId, minutes: 25 });
    expect((await call(noor, "POST", `/sessions/${sid}/cheer`, { to: ava.user.id, kind: 1 })).status).toBe(204);
    app.clock.now += 4;
    expect(await call(noor, "POST", `/sessions/${sid}/cheer`, { to: kai.user.id, kind: 1 })).toEqual({
      status: 429,
      body: { error: expect.any(String), code: "cheer_too_soon", retryAfter: 6 },
    });
    // Someone else can.
    expect((await call(kai, "POST", `/sessions/${sid}/cheer`, { to: noor.user.id, kind: 0 })).status).toBe(204);
    app.clock.now += 6;
    expect((await call(noor, "POST", `/sessions/${sid}/cheer`, { to: kai.user.id, kind: 1 })).status).toBe(204);
  });

  test("422 cheer_invalid for yourself, strangers and unknown kinds", async () => {
    const squadId = await squad(ava, noor, kai);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await start(noor, { squadId, minutes: 25 });
    for (const body of [{ to: ava.user.id, kind: 0 }, { to: kai.user.id, kind: 0 }, { to: noor.user.id, kind: 8 }, { to: noor.user.id, kind: 1.5 }, { to: noor.user.id }]) {
      expect((await call(ava, "POST", `/sessions/${sid}/cheer`, body)).body.code, JSON.stringify(body)).toBe("cheer_invalid");
    }
    expect((await call(kai, "POST", `/sessions/${sid}/cheer`, { to: ava.user.id, kind: 0 })).body.code).toBe("not_member");
  });
});

describe("APNs answers", () => {
  async function room() {
    const squadId = await squad(ava, noor, kai);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await upload(ava, sid, 1);
    await start(noor, { squadId, minutes: 25 });
    await upload(noor, sid, 2);
    await app.advance(COALESCE_SECONDS);
    app.apns.clear();
    return { squadId, sid };
  }

  test("410 Unregistered or BadDeviceToken clears that member's token; other refusals don't", async () => {
    const { squadId, sid } = await room();
    app.apns.answers.set(laToken(1), { status: 410, reason: "Unregistered" });
    app.apns.answers.set(laToken(2), { status: 429, reason: "TooManyRequests" });
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await app.advance(COALESCE_SECONDS);
    expect(participant(sid, ava)).toMatchObject({ la_token: null, la_env: null });
    expect(participant(sid, noor)).toMatchObject({ la_token: laToken(2), la_env: "production" });

    app.apns.clear();
    app.apns.answers.set(laToken(2), { status: 400, reason: "BadDeviceToken" });
    await start(kai, { squadId, minutes: 25 });
    await app.advance(COALESCE_SECONDS);
    // Ava's token is gone, so nothing went to it.
    expect(app.apns.requests.map((request) => request.token)).toEqual([laToken(2)]);
    expect(participant(sid, noor)).toMatchObject({ la_token: null, la_env: null });
    expect(logs).toContain(`room ${sid}: APNs refused 1 push (410 Unregistered)`);
    expect(logs).toContain(`room ${sid}: APNs refused 1 push (400 BadDeviceToken)`);

    // A new token from the app starts the pushes again.
    app.apns.clear();
    await upload(ava, sid, 4);
    await call(ava, "POST", `/sessions/${sid}/resume`);
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => request.token)).toEqual([laToken(4)]);
  });

  test("APNs out of reach: counted and logged, and the room carries on", async () => {
    const { sid } = await room();
    app.apns.unreachable = true;
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await app.advance(COALESCE_SECONDS);
    expect(logs).toContain(`room ${sid}: push failed (TypeError)`);
    expect(participant(sid, ava)).toMatchObject({ la_token: laToken(1) });
    expect((await call(ava, "POST", `/sessions/${sid}/resume`)).status).toBe(200);
  });

  test("someone who left gets no more updates, but does get the end", async () => {
    const { sid } = await room();
    await call(noor, "POST", `/sessions/${sid}/end`);
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => request.token)).toEqual([laToken(1)]);
    app.apns.clear();
    await call(ava, "POST", `/sessions/${sid}/end`);
    await app.runAlarms();
    expect(app.apns.requests.map((request) => [request.token, request.aps.event])).toEqual([
      [laToken(1), "end"],
      [laToken(2), "end"],
    ]);
  });
});

describe("payload budget", () => {
  test("six members with the longest names fit in 3,584 bytes, and every APNs body in 4,096", async () => {
    const owner = await app.user("owner", "🦊".repeat(12));
    app.sqlite.prepare("UPDATE users SET plus_until = ?").run(T0 + 86_400);
    const created = await call(owner, "POST", "/squads", { name: "🔒".repeat(20) });
    const squadId = created.body.squad.id as string;
    app.sqlite.prepare("UPDATE squads SET pet_species = 'abcdefghij', pet_stage = 99, pet_xp = 599 WHERE id = ?").run(squadId);
    const code = (await call(owner, "POST", `/squads/${squadId}/invite`)).body.code;
    const others: SignedIn[] = [];
    for (let index = 0; index < 5; index++) {
      const member = await app.user(`member${index}`, "🐙".repeat(12));
      await app.request("PATCH", "/me", { token: member.token, body: { avatarCode: "b99.c99.e99.h99" } });
      expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
      others.push(member);
    }

    const sid = (await start(owner, { squadId, minutes: 240 })).session.id;
    await upload(owner, sid, 1);
    for (const [index, member] of others.entries()) {
      app.clock.now += 0.123456789;
      const joined = await start(member, { squadId, minutes: 240 });
      expect(payloadByteCount(joined.attributes, joined.contentState)).toBeLessThanOrEqual(PAYLOAD_BUDGET_BYTES);
      await upload(member, sid, index + 2);
    }
    await call(others[0] as SignedIn, "POST", `/sessions/${sid}/pause`);
    await call(others[1] as SignedIn, "POST", `/sessions/${sid}/cheer`, { to: owner.user.id, kind: 7 });
    await app.advance(COALESCE_SECONDS);

    expect(app.apns.requests).toHaveLength(6);
    for (const request of app.apns.requests) {
      const state = request.aps["content-state"];
      expect(state.m).toHaveLength(6);
      expect(state.p).toEqual({ k: "abcdefghij.99", md: PET_MOOD_HAPPY, x: 1 });
      expect(new TextEncoder().encode(request.body).length).toBeLessThanOrEqual(APNS_BODY_LIMIT_BYTES);
      const bytes = payloadByteCount({ sid, me: owner.user.id, sq: "🔒".repeat(20) }, state);
      expect(bytes).toBeLessThanOrEqual(PAYLOAD_BUDGET_BYTES);
    }
  });
});

describe("GET /sessions/:id", () => {
  test("the session and its state, for members of the session or its squad", async () => {
    const squadId = await squad(ava, noor, kai);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    const mine = await call(ava, "GET", `/sessions/${sid}`);
    expect(mine).toEqual({
      status: 200,
      body: {
        session: { id: sid, squadId, hostId: ava.user.id, status: "open", createdAt: T0 },
        contentState: { v: 1, m: [{ i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0, e: T0 + 1500 }] },
      },
    });
    // Kai hasn't joined, but is in the squad: may look.
    expect(await call(kai, "GET", `/sessions/${sid}`)).toEqual(mine);
    const stranger = await app.user("mila");
    expect((await call(stranger, "GET", `/sessions/${sid}`)).body.code).toBe("not_member");
    expect((await call(ava, "GET", "/sessions/Zz00000000")).body.code).toBe("session_not_found");
    expect((await call(ava, "GET", "/sessions/bad")).status).toBe(404);
  });

  test("a day after the room ends, its state is gone; the session still says ended", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    await call(ava, "POST", `/sessions/${sid}/end`);
    await app.runAlarms();
    expect((await call(ava, "GET", `/sessions/${sid}`)).body.contentState.m[0].s).toBe(MemberState.left);
    await app.advance(ENDED_ROOM_KEPT_SECONDS);
    expect(app.rooms.entry(sid).state.storage.data.size).toBe(0);
    expect(app.rooms.entry(sid).state.storage.alarm).toBeNull();
    expect((await call(ava, "GET", `/sessions/${sid}`)).body).toEqual({
      session: { id: sid, squadId: null, hostId: ava.user.id, status: "ended", createdAt: T0 },
      contentState: null,
    });
  });
});

describe("GET /sessions/:id/live", () => {
  test("sends the state on connect and after every change, and closes when the room ends", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    expect(await call(ava, "GET", `/sessions/${sid}/live`)).toEqual({ status: 426, body: { error: expect.any(String), code: "upgrade_required" } });

    const response = await app.request("GET", `/sessions/${sid}/live`, { token: ava.token, headers: { upgrade: "websocket" } });
    expect(response.headers.get("x-test-upgrade")).toBe("websocket");
    const socket = app.socket(sid);
    expect(socket.messages).toEqual([{ type: "state", status: "open", contentState: await stateOf(ava, sid) }]);

    // Straight away, not after the coalescing window.
    await start(noor, { squadId, minutes: 25 });
    expect(socket.messages).toHaveLength(2);
    expect(socket.messages[1].contentState.v).toBe(2);
    await call(noor, "POST", `/sessions/${sid}/cheer`, { to: ava.user.id, kind: 3 });
    expect(socket.messages[2].contentState.c.k).toBe(3);
    await app.advance(CHEER_SHOWN_SECONDS);
    expect(socket.messages[3].contentState).not.toHaveProperty("c");

    await call(noor, "POST", `/sessions/${sid}/end`);
    await call(ava, "POST", `/sessions/${sid}/end`);
    const last = socket.messages.at(-1);
    expect(last.status).toBe("ended");
    expect(last.contentState.m.map((member: { s: number }) => member.s)).toEqual([4, 4]);
    expect(socket.closed).toEqual({ code: 1000, reason: "Session ended" });

    // The room's own route checks the header too, and pings are answered.
    const room = app.rooms.entry(sid).object;
    const pinged = new (await import("./rooms.ts")).FakeWebSocket();
    await room.webSocketMessage(pinged, JSON.stringify({ type: "ping" }));
    await room.webSocketMessage(pinged, "not json");
    expect(pinged.messages).toEqual([{ type: "pong" }]);
  });

  test("only for the session's members and squad", async () => {
    const sid = (await start(ava, { minutes: 25 })).session.id;
    const response = await call(noor, "GET", `/sessions/${sid}/live`, undefined, { upgrade: "websocket" });
    expect(response.body.code).toBe("not_member");
    expect(app.rooms.entry(sid).state.sockets).toHaveLength(0);
  });
});

describe("deleting an account mid-session", () => {
  test("takes them out of the room, and ends it if nobody's left running", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await start(ava, { squadId, minutes: 25 })).session.id;
    await upload(ava, sid, 1);
    await start(noor, { squadId, minutes: 25 });
    await upload(noor, sid, 2);
    await app.advance(COALESCE_SECONDS);
    app.apns.clear();

    expect((await app.request("DELETE", "/me", { token: noor.token })).status).toBe(204);
    await app.advance(COALESCE_SECONDS);
    expect(app.apns.requests.map((request) => [request.token, request.priority])).toEqual([[laToken(1), 10]]);
    expect(app.apns.requests[0]?.aps["content-state"].m.map((member: { i: string }) => member.i)).toEqual([ava.user.id]);
    expect(app.count("SELECT count(*) FROM participants WHERE user_id = ?", noor.user.id)).toBe(0);

    app.apns.clear();
    expect((await app.request("DELETE", "/me", { token: ava.token })).status).toBe(204);
    await app.runAlarms();
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");
  });
});
