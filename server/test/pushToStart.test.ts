// Push-to-start, the M4 spike, through the whole Worker: a join with `pushToStart` asks iOS to start
// the joiner's Live Activity, and POST /admin/push-to-start-test does the same for the demo squad.

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { APNS_BODY_LIMIT_BYTES } from "../src/apns.ts";
import { DEMO_ME, DEMO_SID } from "../src/demo.ts";
import { type ContentState, MemberState, PAYLOAD_BUDGET_BYTES, payloadByteCount, staleDateFor } from "../src/liveActivity.ts";
import { lockedInWith, pushToStartPayload } from "../src/pushToStart.ts";
import { BUNDLE_ID, type SignedIn, T0, type TestApp, read, testApp } from "./app.ts";
import { JWT_IN_LOG } from "./helpers.ts";
import { laToken } from "./rooms.ts";

const ADMIN_TOKEN = "a".repeat(20) + "0123456789abcdef0123";

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
  app = await testApp({ ADMIN_TOKEN });
  ava = await app.user("ava", "Ava");
  noor = await app.user("noor", "Noor");
});

afterEach(async () => {
  await app.settle();
  vi.restoreAllMocks();
  for (const line of logs) {
    for (const secret of [...app.issued, ADMIN_TOKEN]) expect(line).not.toContain(secret);
    for (let seed = 0; seed < 8; seed++) expect(line).not.toContain(starter(seed));
    expect(line).not.toMatch(/\b(ava|noor|Ava|Noor|Library Goblins)\b/);
    expect(line).not.toMatch(JWT_IN_LOG);
    expect(line).not.toMatch(/bearer/i);
  }
});

/** A push-to-start token: 64 hex characters, distinct from the other tokens in the tests. */
const starter = (seed: number) => laToken(0xc0 + seed);

const call = async (who: SignedIn, method: string, path: string, body?: unknown) => read(await app.request(method, path, { token: who.token, body }));

async function squad(owner: SignedIn, ...members: SignedIn[]): Promise<string> {
  const created = await call(owner, "POST", "/squads", { name: "Library Goblins" });
  const id = created.body.squad.id as string;
  const code = (await call(owner, "POST", `/squads/${id}/invite`)).body.code as string;
  for (const member of members) expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
  return id;
}

/** The push-to-starts APNs got, by their `event`. */
const starts = () => app.apns.requests.filter((request) => request.aps.event === "start");

describe("a join with pushToStart", () => {
  test("starts the joiner's Live Activity by push and says so", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    app.clock.now = T0 + 60;
    const response = await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 50, pushToStart: { token: starter(1).toUpperCase(), env: "production" } });
    expect(response.status).toBe(200);
    const { pushedToStart, ...joined } = response.body;
    expect(pushedToStart).toBe(true);
    // Otherwise the usual Joined.
    const species = app.value("SELECT pet_species FROM squads WHERE id = ?", squadId);
    expect(joined).toEqual({
      session: { id: sid, squadId, hostId: ava.user.id, status: "open", createdAt: T0 },
      attributes: { sid, me: noor.user.id, sq: "Library Goblins" },
      contentState: {
        v: 2,
        m: [
          { i: ava.user.id, n: "Ava", a: "b0.c0.e0.h0", s: 0, b: T0, e: T0 + 1500 },
          { i: noor.user.id, n: "Noor", a: "b0.c0.e0.h0", s: 0, b: T0 + 60, e: T0 + 60 + 3000 },
        ],
        // The egg (M5), hungry: nobody has finished today.
        p: { k: `${species}.0`, md: 1, x: 0 },
      },
    });

    const [request] = starts();
    expect(starts()).toHaveLength(1);
    expect(request?.url).toBe(`https://api.push.apple.com/3/device/${starter(1)}`);
    expect(request?.headers).toEqual({
      authorization: expect.stringMatching(/^bearer /),
      "apns-push-type": "liveactivity",
      "apns-topic": `${BUNDLE_ID}.push-type.liveactivity`,
      "apns-priority": "10",
      "content-type": "application/json",
    });
    expect(JSON.parse(request?.body ?? "")).toEqual({
      aps: {
        timestamp: T0 + 60,
        event: "start",
        "content-state": joined.contentState,
        "stale-date": T0 + 60 + 3000 + 300,
        alert: { title: "Library Goblins", body: "You're locked in with Ava" },
        "attributes-type": "LockinAttributes",
        attributes: { sid, me: noor.user.id, sq: "Library Goblins" },
        "input-push-token": 1,
      },
    });
    expect(logs).toContain(`push-to-start ${sid}: production -> APNs 200`);
  });

  test("POST /sessions takes it too, joining the open room or opening one; opening still alerts the squad", async () => {
    const squadId = await squad(ava, noor);
    await call(noor, "POST", "/devices", { apnsToken: laToken(0xa1), env: "sandbox", laEnabled: true, frequentPushes: false, tz: "UTC", quietHours: null });
    const opened = await call(ava, "POST", "/sessions", { squadId, minutes: 25, pushToStart: { token: starter(1), env: "sandbox" } });
    expect(opened.body.pushedToStart).toBe(true);
    expect(starts()[0]?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${starter(1)}`);
    expect(starts()[0]?.aps.alert).toEqual({ title: "Library Goblins", body: "You're locked in" });
    await app.settle();
    expect(app.apns.requests.filter((request) => request.headers["apns-push-type"] === "alert").map((request) => request.token)).toEqual([laToken(0xa1)]);

    const joined = await call(noor, "POST", "/sessions", { squadId, minutes: 25, pushToStart: { token: starter(2), env: "production" } });
    expect(joined.body.session.id).toBe(opened.body.session.id);
    expect(joined.body.pushedToStart).toBe(true);
    expect(starts()[1]?.aps.alert.body).toBe("You're locked in with Ava");
  });

  test("without it the answer is Joined as before; null counts as without", async () => {
    const squadId = await squad(ava, noor);
    const opened = await call(ava, "POST", "/sessions", { squadId, minutes: 25 });
    expect(Object.keys(opened.body).sort()).toEqual(["attributes", "contentState", "session"]);
    const joined = await call(noor, "POST", `/sessions/${opened.body.session.id}/join`, { minutes: 25, pushToStart: null });
    expect(joined.status).toBe(200);
    expect(joined.body).not.toHaveProperty("pushedToStart");
    expect(starts()).toHaveLength(0);
  });

  test("solo: nothing to start by push (no squad name for the alert), so false", async () => {
    const solo = await call(ava, "POST", "/sessions", { minutes: 25, pushToStart: { token: starter(1), env: "production" } });
    expect(solo.status).toBe(200);
    expect(solo.body.pushedToStart).toBe(false);
    expect(app.apns.requests).toHaveLength(0);
  });

  test("422 token_invalid for a malformed pushToStart, before anything happens", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    for (const pushToStart of ["nope", 5, [], {}, { token: "xyz", env: "sandbox" }, { token: starter(1) }, { token: starter(1), env: "development" }, { env: "sandbox" }]) {
      for (const [path, body] of [
        [`/sessions/${sid}/join`, { minutes: 25, pushToStart }],
        ["/sessions", { squadId, minutes: 25, pushToStart }],
      ] as const) {
        expect(await call(noor, "POST", path, body), `${path} ${JSON.stringify(pushToStart)}`).toEqual({
          status: 422,
          body: { error: expect.any(String), code: "token_invalid" },
        });
      }
    }
    expect(app.count("SELECT count(*) FROM participants WHERE user_id = ?", noor.user.id)).toBe(0);
    // The room's own errors come back as they were, with nothing pushed.
    expect((await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 0, pushToStart: { token: starter(1), env: "sandbox" } })).body.code).toBe("minutes_invalid");
    expect((await call(noor, "POST", "/sessions/Zz00000000/join", { minutes: 25, pushToStart: { token: starter(1), env: "sandbox" } })).status).toBe(404);
    expect(app.apns.requests).toHaveLength(0);
  });

  test("APNs refusing: false; 410 or BadDeviceToken also clears the stored push-to-start token", async () => {
    const squadId = await squad(ava, noor);
    const device = (seed: number, pushToStartToken: string) => ({
      apnsToken: laToken(0xa0 + seed),
      env: "production",
      pushToStartToken,
      laEnabled: true,
      frequentPushes: false,
      tz: "UTC",
    });
    expect((await call(noor, "POST", "/devices", device(1, starter(1)))).status).toBe(204);
    expect((await call(noor, "POST", "/devices", device(2, starter(2)))).status).toBe(204);
    expect((await call(ava, "POST", "/devices", device(3, starter(3)))).status).toBe(204);
    const stored = () => app.sqlite.prepare("SELECT push_to_start_token FROM devices ORDER BY apns_token").all().map((row) => row.push_to_start_token);

    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    app.apns.answers.set(starter(1), { status: 410, reason: "Unregistered" });
    const gone = await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25, pushToStart: { token: starter(1), env: "production" } });
    expect(gone.status).toBe(200);
    expect(gone.body.pushedToStart).toBe(false);
    expect(stored()).toEqual([null, starter(2), starter(3)]);
    expect(logs).toContain(`push-to-start ${sid}: production -> APNs 410 Unregistered`);

    // Asking again while joined returns the same Joined, and pushes again.
    app.apns.answers.set(starter(2), { status: 400, reason: "BadDeviceToken" });
    expect((await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25, pushToStart: { token: starter(2), env: "sandbox" } })).body.pushedToStart).toBe(false);
    expect(stored()).toEqual([null, null, starter(3)]);

    app.apns.answers.set(starter(3), { status: 429, reason: "TooManyRequests" });
    expect((await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25, pushToStart: { token: starter(3), env: "production" } })).body.pushedToStart).toBe(false);
    expect(stored()).toEqual([null, null, starter(3)]);
  });

  test("APNs out of reach: false, and joined all the same", async () => {
    const squadId = await squad(ava, noor);
    const sid = (await call(ava, "POST", "/sessions", { squadId, minutes: 25 })).body.session.id;
    app.apns.unreachable = true;
    const joined = await call(noor, "POST", `/sessions/${sid}/join`, { minutes: 25, pushToStart: { token: starter(1), env: "production" } });
    expect(joined.status).toBe(200);
    expect(joined.body.pushedToStart).toBe(false);
    expect(joined.body.contentState.m).toHaveLength(2);
    expect(logs).toContain(`push-to-start ${sid}: push failed (TypeError)`);
  });

  test("the largest squad fits the 3,584-byte budget and APNs' 4,096 bytes", async () => {
    const owner = await app.user("owner", "🦊".repeat(12));
    app.sqlite.prepare("UPDATE users SET plus_until = ?").run(T0 + 86_400);
    const created = await call(owner, "POST", "/squads", { name: "🔒".repeat(20) });
    const squadId = created.body.squad.id as string;
    app.sqlite.prepare("UPDATE squads SET pet_species = 'abcdefghij', pet_stage = 99, pet_xp = 599 WHERE id = ?").run(squadId);
    const code = (await call(owner, "POST", `/squads/${squadId}/invite`)).body.code;
    const sid = (await call(owner, "POST", "/sessions", { squadId, minutes: 240 })).body.session.id;
    for (let index = 0; index < 5; index++) {
      const member = await app.user(`member${index}`, "🐙".repeat(12));
      await app.request("PATCH", "/me", { token: member.token, body: { avatarCode: "b99.c99.e99.h99" } });
      expect((await call(member, "POST", `/squads/join/${code}`)).status).toBe(200);
      app.clock.now += 0.123456789;
      const joined = await call(member, "POST", `/sessions/${sid}/join`, { minutes: 240, pushToStart: { token: starter(index), env: "production" } });
      expect(joined.body.pushedToStart, String(index)).toBe(true);
    }

    const last = starts().at(-1);
    expect(last?.aps["content-state"].m).toHaveLength(6);
    expect(last?.aps.alert).toEqual({ title: "🔒".repeat(20), body: `You're locked in with ${"🦊".repeat(12)} and 4 others` });
    for (const request of starts()) {
      expect(payloadByteCount(request.aps.attributes, request.aps["content-state"])).toBeLessThanOrEqual(PAYLOAD_BUDGET_BYTES);
      expect(new TextEncoder().encode(request.body).length).toBeLessThanOrEqual(APNS_BODY_LIMIT_BYTES);
    }
  });
});

describe("the payload", () => {
  const member = (i: string, n: string, s: number) => ({ i, n, a: "b0.c0.e0.h0", s: s as MemberState, b: T0, e: T0 + 1500, ...(s === 2 ? { q: T0 + 60 } : {}) });
  const ids = ["me00000000", "ava0000000", "noor000000", "kai0000000", "mila000000"];

  test("names whoever else is running, host first: two by name, more counted", () => {
    const state = (...states: number[]): ContentState => ({ v: 1, m: states.map((s, index) => member(ids[index] ?? "", ["Me", "Ava", "Noor", "Kai", "Mila"][index] ?? "", s)) });
    expect(lockedInWith(state(0), "me00000000")).toBe("You're locked in");
    expect(lockedInWith(state(0, 0), "me00000000")).toBe("You're locked in with Ava");
    expect(lockedInWith(state(0, 2, 0), "me00000000")).toBe("You're locked in with Ava and Noor");
    expect(lockedInWith(state(0, 0, 1, 0, 0), "me00000000")).toBe("You're locked in with Ava and 3 others");
    // Whoever has finished or left doesn't count; someone slipped is still running (decision 0009).
    expect(lockedInWith(state(0, MemberState.done, MemberState.left, 0, 0), "me00000000")).toBe("You're locked in with Kai and Mila");
    expect(lockedInWith(state(0, MemberState.done, MemberState.left, MemberState.slipped, 0), "me00000000")).toBe("You're locked in with Kai and Mila");
    expect(lockedInWith(state(0, 0), "ava0000000")).toBe("You're locked in with Me");
  });

  test("stale-date as for updates; none for solo", () => {
    const state: ContentState = { v: 3, m: [member(ids[0] ?? "", "Me", 0), member(ids[1] ?? "", "Ava", 0)] };
    const payload = pushToStartPayload({ sid: "r7Kq2xP9aL", me: ids[0] ?? "", sq: "Goblins" }, state, T0);
    expect(payload?.aps["stale-date"]).toBe(staleDateFor(state, T0));
    expect(pushToStartPayload({ sid: "r7Kq2xP9aL", me: ids[0] ?? "" }, state, T0)).toBeNull();
  });
});

describe("POST /admin/push-to-start-test", () => {
  const admin = (body: unknown, authorization: string | null = `Bearer ${ADMIN_TOKEN}`) =>
    app.request("POST", "/admin/push-to-start-test", { body, headers: authorization === null ? {} : { authorization } });

  test("push-to-starts the demo squad on the token", async () => {
    const response = await read(await admin({ token: starter(1), env: "sandbox" }));
    expect(response.status).toBe(200);
    const [request] = app.apns.requests;
    expect(app.apns.requests).toHaveLength(1);
    expect(request?.url).toBe(`https://api.sandbox.push.apple.com/3/device/${starter(1)}`);
    expect(request?.headers).toMatchObject({ "apns-push-type": "liveactivity", "apns-topic": `${BUNDLE_ID}.push-type.liveactivity`, "apns-priority": "10" });
    const aps = request?.aps ?? {};
    expect(aps).toMatchObject({
      timestamp: T0,
      event: "start",
      "attributes-type": "LockinAttributes",
      attributes: { sid: DEMO_SID, me: DEMO_ME, sq: "Spike Squad" },
      alert: { title: "Spike Squad", body: "You're locked in with Noor and 2 others" },
      "input-push-token": 1,
    });
    expect(aps["stale-date"]).toBe(staleDateFor(aps["content-state"], T0));
    expect(response.body).toEqual({
      status: 200,
      apnsId: "apns-1",
      environment: "sandbox",
      bytes: payloadByteCount(aps.attributes, aps["content-state"]),
      event: "start",
      attributes: aps.attributes,
      contentState: aps["content-state"],
    });
    expect(logs.join("\n")).toMatch(/push-to-start-test: sandbox start \d+ bytes -> APNs 200/);
  });

  test("a refusal is a 502 with the reason, and a gone token is cleared from devices", async () => {
    await call(noor, "POST", "/devices", { apnsToken: laToken(0xa1), env: "production", pushToStartToken: starter(1), laEnabled: true, frequentPushes: false, tz: "UTC" });
    app.apns.answers.set(starter(1), { status: 410, reason: "Unregistered" });
    const response = await read(await admin({ token: starter(1), env: "production" }));
    expect(response.status).toBe(502);
    expect(response.body).toMatchObject({ status: 410, reason: "Unregistered", environment: "production", event: "start" });
    expect(app.value("SELECT push_to_start_token FROM devices")).toBeNull();
  });

  test("400s for anything but { token, env }", async () => {
    for (const body of ["nope", { token: "xyz", env: "sandbox" }, { token: starter(1) }, { token: starter(1), env: "development" }, { token: starter(1), env: "sandbox", me: "x" }]) {
      expect((await admin(body)).status, JSON.stringify(body)).toBe(400);
    }
    expect(app.apns.requests).toHaveLength(0);
  });

  test("doesn't exist in production, without the admin token, or with the wrong one", async () => {
    for (const authorization of [null, `Bearer ${ADMIN_TOKEN}x`, ADMIN_TOKEN]) {
      expect(await read(await admin({ token: starter(1), env: "sandbox" }, authorization))).toEqual({ status: 404, body: { error: "Not found", code: "not_found" } });
    }
    app.env.ENVIRONMENT = "production";
    expect((await admin({ token: starter(1), env: "sandbox" })).status).toBe(404);
    app.env.ENVIRONMENT = "development";
    app.env.ADMIN_TOKEN = "short";
    expect((await admin({ token: starter(1), env: "sandbox" }, "Bearer short")).status).toBe(404);
    expect(app.apns.requests).toHaveLength(0);
  });
});
