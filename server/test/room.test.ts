// The Room Durable Object on its own: what only the Worker may send it, surviving eviction, D1
// outages, and the six-member cap. Behaviour through the routes is in test/sessions.test.ts.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { ApnsAuthState } from "../src/apnsAuth.ts";
import { D1_RETRY_SECONDS, ROOM_SESSION_HEADER, ROOM_USER_HEADER, type RoomState } from "../src/room.ts";
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
});

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));

/** Straight to the room, as the Worker would call it. */
const direct = (sid: string, userId: string, action: string, body?: unknown) =>
  app.rooms
    .get(app.rooms.idFromName(sid))
    .fetch(`https://room/${action}`, {
      method: body === undefined ? "GET" : "POST",
      headers: { [ROOM_USER_HEADER]: userId, [ROOM_SESSION_HEADER]: sid, "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    .then(read);

test("the runtime's DurableObjectState fits the interfaces the objects use", () => {
  // Compile-time: tsc fails here if Room or ApnsAuth use something DurableObjectState doesn't have.
  const fits = (state: DurableObjectState): [RoomState, ApnsAuthState] => [state, state];
  expect(fits).toBeTypeOf("function");
});

test("only takes requests that carry the user and session the Worker vouches for", async () => {
  const sid = (await call(ava, "POST", "/sessions", { minutes: 25 })).body.session.id;
  const stub = app.rooms.get(app.rooms.idFromName(sid));
  expect((await stub.fetch("https://room/state")).status).toBe(400);
  expect((await stub.fetch("https://room/state", { headers: { [ROOM_USER_HEADER]: ava.user.id } })).status).toBe(400);
  expect((await direct(sid, ava.user.id, "state")).status).toBe(200);
  expect((await direct(sid, ava.user.id, "nonsense", {})).status).toBe(404);
  // A room nobody opened has nothing to say.
  expect((await direct("Zz00000000", ava.user.id, "state")).body.code).toBe("session_not_found");
  expect((await direct("Zz00000000", ava.user.id, "pause", {})).body.code).toBe("session_not_found");
  // The Worker never forwards the client's headers: setting the room's own header changes nothing.
  const spoofed = await app.request("POST", `/sessions/${sid}/end`, { token: noor.token, headers: { [ROOM_USER_HEADER]: ava.user.id } });
  expect((await read(spoofed)).body.code).toBe("not_member");
});

test("carries on from storage after the runtime evicts it", async () => {
  const created = await call(ava, "POST", "/squads", { name: "Night Owls" });
  const squadId = created.body.squad.id;
  const code = (await call(ava, "POST", `/squads/${squadId}/invite`)).body.code;
  await call(noor, "POST", `/squads/join/${code}`);
  const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
  await call(ava, "POST", `/sessions/${sid}/la-token`, { token: "ab".repeat(32), env: "sandbox" });

  app.rooms.evict(sid);
  const joined = await call(noor, "POST", "/sessions", { squadId, minutes: 50 });
  expect(joined.body.session.id).toBe(sid);
  expect(joined.body.contentState.v).toBe(2);
  app.rooms.evict(sid);
  await app.advance(2);
  expect(app.apns.requests.map((request) => request.token)).toEqual(["ab".repeat(32)]);
  app.rooms.evict(sid);
  await app.advance(25 * 60);
  expect(app.value("SELECT state FROM participants WHERE session_id = ? AND user_id = ?", sid, ava.user.id)).toBe(3);
});

test("a D1 write that fails is tried again, and the room keeps going meanwhile", async () => {
  const sid = (await call(ava, "POST", "/sessions", { minutes: 25 })).body.session.id;
  const batch = app.d1.batch.bind(app.d1);
  app.d1.batch = async () => {
    throw new Error("D1_ERROR: Network connection lost.");
  };
  app.clock.now = T0 + 60;
  const paused = await call(ava, "POST", `/sessions/${sid}/pause`);
  expect(paused.status).toBe(200);
  expect(paused.body.contentState.m[0].s).toBe(2);
  expect(app.value("SELECT state FROM participants WHERE session_id = ?", sid)).toBe(0);
  expect(logs).toContain(`room ${sid}: D1 write failed (Error), trying again in ${D1_RETRY_SECONDS} s`);

  app.d1.batch = batch;
  await app.advance(D1_RETRY_SECONDS);
  expect(app.value("SELECT state FROM participants WHERE session_id = ?", sid)).toBe(2);
  expect(app.value("SELECT paused_at FROM participants WHERE session_id = ?", sid)).toBe(T0 + 60);
  expect(app.count("SELECT count(*) FROM events WHERE session_id = ? AND type = 'pause'", sid)).toBe(1);
});

describe("opening", () => {
  const profile = { name: "Ava", avatar: "b0.c0.e0.h0" };

  test("D1 refuses a second running timer for one user, whoever checked first", async () => {
    const sid = (await call(ava, "POST", "/sessions", { minutes: 25 })).body.session.id;
    // Past the Worker's own check, as a request racing it would be.
    expect(await direct("Ra00000001", ava.user.id, "open", { squadId: null, minutes: 25, profile })).toEqual({
      status: 409,
      body: { error: expect.any(String), code: "already_in_session", sessionId: sid },
    });
    // Nothing was left behind: no second session, and the room stays empty.
    expect(app.count("SELECT count(*) FROM sessions")).toBe(1);
    expect((await direct("Ra00000001", ava.user.id, "state")).body.code).toBe("session_not_found");
  });

  test("D1 refuses a second open room for a squad: room_exists, which the Worker answers by joining", async () => {
    const squadId = (await call(ava, "POST", "/squads", { name: "Goblins" })).body.squad.id;
    const code = (await call(ava, "POST", `/squads/${squadId}/invite`)).body.code;
    await call(noor, "POST", `/squads/join/${code}`);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    expect((await direct("Ra00000002", noor.user.id, "open", { squadId, minutes: 25, profile })).body.code).toBe("room_exists");
    expect((await direct(sid, noor.user.id, "open", { squadId, minutes: 25, profile })).body.code).toBe("room_exists");
    expect(app.count("SELECT count(*) FROM sessions")).toBe(1);
    expect(app.count("SELECT count(*) FROM participants WHERE user_id = ?", noor.user.id)).toBe(0);
  });

  test("refuses bodies the Worker would never send", async () => {
    expect((await direct("Ra00000003", ava.user.id, "open", { squadId: null, minutes: 0, profile })).body.code).toBe("minutes_invalid");
    expect((await direct("Ra00000003", ava.user.id, "open", { squadId: null, minutes: 25 })).status).toBe(400);
    expect((await direct("Ra00000003", ava.user.id, "open", { squadId: "nope", minutes: 25, profile })).status).toBe(400);
    expect((await direct("Ra00000003", ava.user.id, "open", { squadId: "Zz00000000", minutes: 25, profile })).body.code).toBe("not_member");
    expect(app.count("SELECT count(*) FROM sessions")).toBe(0);
  });
});

describe("six members at most", () => {
  test("a seventh takes the place of someone who left, or finds the room full", async () => {
    const owner = await app.user("owner");
    app.sqlite.prepare("UPDATE users SET plus_until = ? WHERE id = ?").run(T0 + 86_400, owner.user.id);
    const squadId = (await call(owner, "POST", "/squads", { name: "Big Squad" })).body.squad.id;
    const code = (await call(owner, "POST", `/squads/${squadId}/invite`)).body.code;
    const members = [owner];
    for (const handle of ["m1", "m2", "m3", "m4", "m5"].map((suffix) => `member${suffix}`)) {
      const member = await app.user(handle);
      await call(member, "POST", `/squads/join/${code}`);
      members.push(member);
    }
    let sid = "";
    for (const member of members) sid = (await call(member, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;

    // Someone who left the squad and was replaced could still be in the room: the room itself
    // holds six. (The Worker only lets squad members in; straight to the room here.)
    const seventh = await app.user("seventh");
    const profile = { name: "Seventh", avatar: "b0.c0.e0.h0" };
    expect((await direct(sid, seventh.user.id, "join", { minutes: 25, profile })).body.code).toBe("room_full");

    await call(members[2] as SignedIn, "POST", `/sessions/${sid}/end`);
    const joined = await direct(sid, seventh.user.id, "join", { minutes: 25, profile });
    expect(joined.status).toBe(200);
    const ids = joined.body.contentState.m.map((member: { i: string }) => member.i);
    expect(ids).toHaveLength(6);
    expect(ids).not.toContain(members[2]?.user.id);
    expect(ids.at(-1)).toBe(seventh.user.id);
    // Their row stays in D1.
    expect(app.value("SELECT state FROM participants WHERE session_id = ? AND user_id = ?", sid, members[2]?.user.id ?? "")).toBe(4);
  });
});

test("the WebSocket close handler copes with a socket that's already closed", async () => {
  const sid = (await call(ava, "POST", "/sessions", { minutes: 25 })).body.session.id;
  await app.request("GET", `/sessions/${sid}/live`, { token: ava.token, headers: { upgrade: "websocket" } });
  const socket = app.socket(sid);
  const room = app.rooms.entry(sid).object;
  await room.webSocketClose(socket, 1000, "bye");
  await room.webSocketClose(socket, 1000, "bye");
  expect(socket.closed).toEqual({ code: 1000, reason: "bye" });
  // Changes after that don't try to reach it.
  expect((await call(ava, "POST", `/sessions/${sid}/pause`)).status).toBe(200);
  expect(socket.sent).toHaveLength(1);
});

describe("M5", () => {
  test("a room saved before M5 (no credits, the old pet) carries on, credits and shows the pet", async () => {
    const created = await call(ava, "POST", "/squads", { name: "Night Owls" });
    const squadId = created.body.squad.id;
    const code = (await call(ava, "POST", `/squads/${squadId}/invite`)).body.code;
    await call(noor, "POST", `/squads/join/${code}`);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    // What M3 stored: no credits or finishers, and the pet as species, stage, XP and mood.
    const storage = app.rooms.entry(sid).state.storage;
    const record = storage.data.get("room") as Record<string, unknown>;
    delete record.credits;
    delete record.finishers;
    record.pet = { species: null, stage: 0, xp: 0, mood: 1 };
    app.rooms.evict(sid);

    expect((await direct(sid, ava.user.id, "state")).body.contentState.p).toBeUndefined();
    const joined = await call(noor, "POST", "/sessions", { squadId, minutes: 25 });
    const species = app.value("SELECT pet_species FROM squads WHERE id = ?", squadId);
    expect(joined.body.contentState.p).toEqual({ k: `${species}.0`, md: 1, x: 0 });
    await app.advance(25 * 60);
    expect(app.value("SELECT coins FROM users WHERE id = ?", ava.user.id)).toBe(30);
    expect(app.value("SELECT hatched_at FROM squads WHERE id = ?", squadId)).toBe(T0 + 25 * 60);
  });

  test("a room saved before gentle slips: a member whose slip stopped the timer has left, and doesn't hold the room open", async () => {
    const created = await call(ava, "POST", "/squads", { name: "Night Owls" });
    const squadId = created.body.squad.id;
    const code = (await call(ava, "POST", `/squads/${squadId}/invite`)).body.code;
    await call(noor, "POST", `/squads/join/${code}`);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    await call(noor, "POST", "/sessions", { squadId, minutes: 25 });
    // What M3 stored for Noor's slip: state 5, timer stopped (endedAt), no slipUntil.
    const storage = app.rooms.entry(sid).state.storage;
    const record = storage.data.get("room") as { members: Array<Record<string, unknown>> };
    Object.assign(record.members[1] ?? {}, { s: 5, endedAt: T0 + 60, slips: 1 });
    app.rooms.evict(sid);

    expect((await direct(sid, ava.user.id, "state")).body.contentState.m[1].s).toBe(4);
    expect((await call(ava, "POST", `/sessions/${sid}/end`)).status).toBe(200);
    expect(app.value("SELECT status FROM sessions WHERE id = ?", sid)).toBe("ended");
  });

  test("the 8-hour cap credits the minutes but doesn't make the pet sad: nobody chose it", async () => {
    const created = await call(ava, "POST", "/squads", { name: "Night Owls" });
    const squadId = created.body.squad.id;
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    await app.advance(10 * 60);
    await call(ava, "POST", `/sessions/${sid}/pause`);
    await app.advance(8 * 60 * 60);
    expect(app.value("SELECT state FROM participants WHERE session_id = ?", sid)).toBe(4);
    expect(app.value("SELECT coins FROM users WHERE id = ?", ava.user.id)).toBe(10);
    expect(app.value("SELECT pet_xp FROM squads WHERE id = ?", squadId)).toBe(10);
    expect(app.value("SELECT last_sad_at FROM squads WHERE id = ?", squadId)).toBeNull();
  });

  test("tells another squad's open room only after letting go of its own, so two rooms telling each other can't wait for ever", async () => {
    // Ava and Noor are both in squads A and B, each in one of their rooms, and finish at the same
    // moment: each room tells the other. Mila and Kai keep the rooms open.
    const kai = await app.user("kai", "Kai");
    const mila = await app.user("mila", "Mila");
    for (const who of [ava, noor]) app.sqlite.prepare("UPDATE users SET plus_until = ? WHERE id = ?").run(T0 + 86_400, who.user.id);
    const a = (await call(ava, "POST", "/squads", { name: "A Squad" })).body.squad.id;
    const b = (await call(noor, "POST", "/squads", { name: "B Squad" })).body.squad.id;
    const codeA = (await call(ava, "POST", `/squads/${a}/invite`)).body.code;
    const codeB = (await call(noor, "POST", `/squads/${b}/invite`)).body.code;
    for (const [who, code] of [[noor, codeA], [mila, codeA], [ava, codeB], [kai, codeB]] as const) await call(who, "POST", `/squads/join/${code}`);
    const roomA = (await call(ava, "POST", "/sessions", { squadId: a, minutes: 25 })).body.session.id;
    const roomB = (await call(noor, "POST", "/sessions", { squadId: b, minutes: 25 })).body.session.id;
    await call(mila, "POST", "/sessions", { squadId: a, minutes: 60 });
    await call(kai, "POST", "/sessions", { squadId: b, minutes: 60 });

    // Time's up for both, and both say so at once (their alarms haven't fired yet).
    app.clock.now = T0 + 25 * 60;
    const ended = await Promise.all([call(ava, "POST", `/sessions/${roomA}/end`), call(noor, "POST", `/sessions/${roomB}/end`)]);
    expect(ended.map((response) => response.status)).toEqual([200, 200]);
    // Two of three in each squad finished today: both pets are happy, in both rooms.
    expect((await direct(roomA, ava.user.id, "state")).body.contentState.p.md).toBe(3);
    expect((await direct(roomB, noor.user.id, "state")).body.contentState.p.md).toBe(3);
    expect(app.count("SELECT count(*) FROM focus_log WHERE completed = 1")).toBe(2);
  });
});
